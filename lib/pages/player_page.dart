// lib/pages/player_page.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/mubu_models.dart';
import '../api/mubu_api_client.dart';
import '../api/mubu_storage.dart';
import '../api/mubu_ui_adapt.dart';
import '../utils/platform_utils.dart';
import '../utils/episode_utils.dart';
import '../utils/source_picker.dart';
import '../utils/source_quality.dart';
import '../utils/stream_probe.dart';
import '../widgets/mubu_dialog.dart';
import 'package:hive/hive.dart';
import '../models/mubu_hive.dart';
import '../player/media_kit_player.dart';
import '../widgets/concentric_hud.dart';
import '../widgets/hover_close_button.dart';

enum LoadingStage { fetchingDetail, testingSpeed, initPlayer, ready, error }

class PlayerPage extends StatefulWidget {
  final VideoItem video;

  const PlayerPage({super.key, required this.video});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  static const _primaryRed = Color(0xFFE50914);
  static const kRed = Color(0xFFE50914);
  static const kGlass = Color(0xFF16161A);

  // UI and state variables
  LoadingStage _stage = LoadingStage.fetchingDetail;
  String? _errorMessage;
  bool _startPlayRequested = false;
  bool _isBookmarked = false;

  // Video source data
  List<VideoSource> _sources = [];
  String _currentUrl = '';
  int _selectedSource = 0;
  int? _fastestIndex;
  String? _recommendedLineName;
  String _description = '';

  // Speed‑test progress
  int _testedCount = 0;
  int _totalLinesToTest = 0;
  List<int> _indicesToTest = [];

  // Player instance
  MediaKitPlayerImpl? _player;
  bool _playerInitialized = false;

  // Async control
  bool _disposed = false;
  http.Client? _client;

  // UI state
  bool _expanded = false;
  final LayerLink _lineLink = LayerLink();

  // 视频宽高比（默认 16:9，加载后动态调整）
  double _videoAspectRatio = 16 / 9;
  VoidCallback? _widthListener;
  VoidCallback? _heightListener;

  // Progress save timer
  Timer? _progressTimer;
  int _lastSavedPositionMs = -1; // skip save when position hasn't changed

  // Saved progress from history
  int? _savedPositionMs;
  int? _savedDurationMs;
  String? _savedEpisodeName;
  String? _savedLineName;

  // 弱网自动切换：持续缓冲超时后的看门狗
  Timer? _bufferingWatchdog;
  VoidCallback? _bufferingListener;
  // 上次自动切换时间，防止短时间内多次切换
  int _lastAutoSwitchMs = 0;
  // 播放开始后中止后台测速，避免与主播放器抢带宽
  bool _abortSpeedTest = false;
  // 连续触发弱网看门狗的次数（用于逐步放大 cache-pause-wait）
  int _weakNetworkCount = 0;

  // 防止并行测速期间多次并发 init；切后台后用于判断是否可重试
  Future<void>? _initPlayerFuture;

  // Sticky player for portrait videos
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _checkBookmarkStatus();
    _loadAndPrepare();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // 切后台时关闭测速 HTTP，避免挂起的请求阻塞恢复后的加载流程
      _client?.close();
      _client = null;
    } else if (state == AppLifecycleState.resumed) {
      _recoverStuckLoading();
    }
  }

  /// 切回前台时：若播放器已就绪但 stage 未更新，或 init 在后台挂起，则恢复/重试
  Future<void> _recoverStuckLoading() async {
    if (_disposed || !mounted) return;
    if (_stage == LoadingStage.ready || _stage == LoadingStage.error) return;

    if (_playerInitialized && _player != null) {
      setState(() => _stage = LoadingStage.ready);
      return;
    }

    if (_stage == LoadingStage.initPlayer &&
        _initPlayerFuture == null &&
        _currentUrl.isNotEmpty) {
      debugPrint('PLAYER: retrying init after app resume');
      try {
        await _initPlayer();
      } catch (e) {
        debugPrint('PLAYER: resume init failed: $e');
        if (mounted && !_disposed) {
          setState(() {
            _stage = LoadingStage.error;
            _errorMessage = '播放器初始化失败，请重试';
          });
        }
      }
    }
  }

  Future<void> _checkBookmarkStatus() async {
    final ok = await MubuStorage.isBookmarked(widget.video.id);
    if (mounted && !_disposed) {
      setState(() {
        _isBookmarked = ok;
      });
    }
  }

  /// 从历史记录中加载上次播放进度
  Future<void> _loadSavedProgress() async {
    final history = await MubuStorage.getHistory();
    final saved = history.where((item) => item.id == widget.video.id).firstOrNull;
    if (saved != null && mounted && !_disposed) {
      setState(() {
        _savedPositionMs = saved.lastPositionMs;
        _savedDurationMs = saved.lastDurationMs;
        _savedEpisodeName = saved.lastEpisodeName;
        _savedLineName = saved.lastLineName;
      });
    }
  }

  Future<void> _toggleBookmark() async {
    await MubuStorage.toggleBookmark(widget.video);
    await _checkBookmarkStatus();
  }

  Future<void> _loadAndPrepare() async {
    setState(() {
      _stage = LoadingStage.fetchingDetail;
      _errorMessage = null;
    });
    if (_disposed) return;
    // Load saved progress first to avoid race condition
    await _loadSavedProgress();
    try {
      final detail = await MubuApiClient.instance.getVideoDetail(widget.video.id, isShort: widget.video.isShortDrama);
      if (detail == null || detail.sources.isEmpty) {
        throw Exception('暂无可用播放源');
      }
      _sources = detail.sources;
      _currentUrl = detail.bestUrl ?? '';
      _description = detail.description;
      if (mounted) {
        setState(() {
          _stage = LoadingStage.testingSpeed;
        });
      }
      if (_sources.length > 1) {
        await _runSpeedTest();
      }
      if (_disposed) return;

      if (_playerInitialized) {
        if (mounted && _stage != LoadingStage.ready) {
          setState(() => _stage = LoadingStage.ready);
        }
      } else if (_savedEpisodeName != null && _savedEpisodeName!.isNotEmpty) {
        _applySavedEpisodeSelection();
        if (mounted) {
          setState(() { _stage = LoadingStage.initPlayer; });
        }
        await _initPlayer();
        if (_disposed) return;
        if (mounted) {
          setState(() { _stage = LoadingStage.ready; });
        }
      } else {
        if (mounted) {
          setState(() { _stage = LoadingStage.initPlayer; });
        }
        await _initPlayer();
        if (_disposed) return;
        if (mounted) {
          setState(() { _stage = LoadingStage.ready; });
        }
      }
    } catch (e) {
      if (_disposed) return;
      debugPrint('PLAYER: Failed during prepare: $e');
      if (mounted) {
        setState(() {
          _stage = LoadingStage.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _initPlayer() {
    return _initPlayerFuture ??= _initPlayerOnce().whenComplete(() {
      _initPlayerFuture = null;
    });
  }

  Future<void> _initPlayerOnce() async {
    MediaKitPlayerImpl? player;
    try {
      if (_player != null) {
        if (_widthListener != null) _player!.videoWidthNotifier.removeListener(_widthListener!);
        if (_heightListener != null) _player!.videoHeightNotifier.removeListener(_heightListener!);
        await _player!.dispose();
        _player = null;
        _playerInitialized = false;
      }
      final activePlayer = MediaKitPlayerImpl(
        initialUrl: _currentUrl,
        isShort: widget.video.isShortDrama,
      );
      player = activePlayer;
      await activePlayer.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('播放器加载超时'),
      );
      await activePlayer.pause();
      if (_disposed) {
        await activePlayer.dispose();
        return;
      }
      if (activePlayer.durationNotifier.value <= Duration.zero) {
        final completer = Completer<void>();
        void listener() {
          if (activePlayer.durationNotifier.value > Duration.zero && !completer.isCompleted) {
            completer.complete();
            activePlayer.durationNotifier.removeListener(listener);
          }
        }
        activePlayer.durationNotifier.addListener(listener);
        await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
          if (!completer.isCompleted) {
            activePlayer.durationNotifier.removeListener(listener);
            completer.complete();
          }
        });
      }
      _widthListener = () => _updateAspectRatio(activePlayer);
      _heightListener = () => _updateAspectRatio(activePlayer);
      activePlayer.videoWidthNotifier.addListener(_widthListener!);
      activePlayer.videoHeightNotifier.addListener(_heightListener!);
      _updateAspectRatio(activePlayer);
      if (mounted) {
        setState(() {
          _player = activePlayer;
          _playerInitialized = true;
          if (_stage != LoadingStage.error) {
            _stage = LoadingStage.ready;
          }
        });
      } else {
        await activePlayer.dispose();
      }
    } catch (e) {
      if (player != null && player != _player) {
        await player.dispose();
      }
      throw Exception('播放器初始化失败: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _bufferingWatchdog?.cancel();
    if (_bufferingListener != null) {
      _player?.isBufferingNotifier.removeListener(_bufferingListener!);
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    if (_widthListener != null) _player?.videoWidthNotifier.removeListener(_widthListener!);
    if (_heightListener != null) _player?.videoHeightNotifier.removeListener(_heightListener!);
    // Save final playback position
    _saveProgress();
    _client?.close();
    _client = null;
    _player?.dispose();
    super.dispose();
  }

  /// 根据视频原始宽高更新播放器宽高比，限制在合理范围内
  void _updateAspectRatio(MediaKitPlayerImpl player) {
    final w = player.videoWidthNotifier.value;
    final h = player.videoHeightNotifier.value;
    if (w != null && h != null && w > 0 && h > 0) {
      double ratio = w / h;
      // 限制最大宽高比防止超宽银幕变形，竖屏视频（如短剧）不限制
      if (ratio > 2.39) ratio = 2.39;
      if (ratio != _videoAspectRatio && mounted) {
        setState(() {
          _videoAspectRatio = ratio;
        });
      }
    }
  }

  /// 是否为竖屏视频（高度 > 宽度）
  bool get _isPortraitVideo => _videoAspectRatio < 1.0;

  /// 计算视频区域的实际高度
  double _calculateVideoHeight(double screenHeight) {
    if (!_isPortraitVideo) {
      // 横屏视频：使用 AspectRatio，不限制
      return screenHeight * 0.5;
    }

    // 竖屏视频：根据滚动位置动态调整
    final fullHeight = screenHeight * 0.65;
    final minHeight = screenHeight * 0.40;

    // 向上滚动 80px 内完成过渡
    final scrollProgress = (_scrollOffset / 80.0).clamp(0.0, 1.0);

    return fullHeight - (fullHeight - minHeight) * scrollProgress;
  }

  /// 滚动监听回调
  void _onScroll() {
    if (_scrollController.hasClients) {
      final double offset = _scrollController.offset;
      _scrollOffset = offset;
      // 只在过渡区间 (0-80px) 内触发重绘以更新视频高度，其余位置直接跳过
      if (offset <= 80.0 && mounted) {
        setState(() {});
      }
    }
  }

  /// Save current playback position to history (no-op if position hasn't changed or is zero)
  void _saveProgress() {
    final pos = _player?.positionNotifier.value;
    final dur = _player?.durationNotifier.value;
    if (pos != null && dur != null && dur > Duration.zero && pos > Duration.zero &&
        _selectedSource >= 0 && _selectedSource < _sources.length) {
      final posMs = pos.inMilliseconds;
      // Skip save if position hasn't changed since last save (e.g. video is paused)
      if (posMs == _lastSavedPositionMs) return;
      _lastSavedPositionMs = posMs;
      final episodeName = _sources[_selectedSource].sourceName;
      final lineName = _sources[_selectedSource].name;
      MubuStorage.updateProgress(
        widget.video.id,
        posMs,
        dur.inMilliseconds,
        episodeName,
        lineName: lineName,
      );
    }
  }

  /// 用户点击播放后调用：中止仍在进行的并行测速，把带宽让给主播放器
  void _abortBackgroundSpeedTest() {
    if (_abortSpeedTest) return;
    _abortSpeedTest = true;
    _client?.close();
    _client = null;
    debugPrint('SPEED: aborted — playback started, yielding bandwidth to main player');
  }

  /// 弱网看门狗：开始监听缓冲状态，播放启动后调用一次
  void _startBufferingWatchdog() {
    if (_player == null || _bufferingListener != null) return;
    _bufferingListener = () {
      final isBuffering = _player?.isBufferingNotifier.value ?? false;
      if (isBuffering) {
        // 已在计时中，不重复启动
        if (_bufferingWatchdog?.isActive == true) return;
        // 12 秒仍在缓冲 → 触发弱网逻辑
        _bufferingWatchdog = Timer(const Duration(seconds: 12), _onBufferingTimeout);
      } else {
        _bufferingWatchdog?.cancel();
        _bufferingWatchdog = null;
      }
    };
    _player!.isBufferingNotifier.addListener(_bufferingListener!);
  }

  /// 持续缓冲 12s 后的处理：自适应调高缓冲等待 + 尝试切换备用线路
  void _onBufferingTimeout() {
    if (_disposed || !mounted) return;
    _weakNetworkCount++;

    // 逐步放大重新恢复播放所需的缓冲时间（最高 8s），减少反复暂停
    final newWait = (_weakNetworkCount + 3).clamp(4, 8);
    _player?.setMpvProperty('cache-pause-wait', '$newWait');
    debugPrint('PLAYER: weak-network #$_weakNetworkCount → cache-pause-wait=${newWait}s');

    // 防止 30s 内重复自动切换
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAutoSwitchMs < 30000) return;

    // 寻找当前集数中质量+延迟最优的备用线路（弱网允许低档）
    if (_sources.isEmpty) return;
    final currentEpisode = _currentEpisodeRef;
    final currentUrl = _sources[_selectedSource].url;

    final fallback = SourcePicker.pickMain(
      _sources,
      episodeName: currentEpisode,
      excludeUrl: currentUrl,
      preferLowerTierOnWeakNet: true,
    );

    if (fallback != null) {
      final idx = _sources.indexOf(fallback);
      debugPrint('PLAYER: buffering watchdog — auto-switch to ${fallback.name} (${fallback.playlistMs}ms)');
      _lastAutoSwitchMs = now;
      _switchSource(idx);
    }
  }

  String get _currentEpisodeRef =>
      _sources.isNotEmpty ? episodeRef(_sources[_selectedSource]) : '';

  String get _currentEpisodeName =>
      _sources.isNotEmpty ? _sources[_selectedSource].sourceName : '';

  /// 测速完成后按「延迟池 + 同档最低延迟」选定推荐源
  Future<void> _applyRecommendedSource({bool autoInit = false}) async {
    if (_sources.isEmpty) return;
    final episode = _currentEpisodeRef.isNotEmpty
        ? _currentEpisodeRef
        : _sources.first.sourceName.isNotEmpty
            ? episodeRef(_sources.first)
            : '';

    final idx = SourcePicker.pickMainIndex(_sources, episodeName: episode);
    if (idx == null) return;

    final picked = _sources[idx];
    final resolution = SourceQuality.resolutionLabel(picked);
    _recommendedLineName = picked.name;
    _fastestIndex = SourcePicker.indexOfFastest(
      _sources,
      episodeName: episode,
      withinResolution: resolution,
    );

    final shouldUpgrade = _playerInitialized &&
        !_startPlayRequested &&
        idx != _selectedSource;

    if (autoInit && !_playerInitialized) {
      _selectedSource = idx;
      _currentUrl = _sources[idx].url;
      debugPrint('PLAYER: auto-pick ${resolution ?? _sources[idx].name} (${_sources[idx].playlistMs}ms) for $episode');
      if (mounted) setState(() { _stage = LoadingStage.initPlayer; });
      await _initPlayer();
    } else if (shouldUpgrade) {
      debugPrint('PLAYER: upgrade to recommended ${resolution ?? _sources[idx].name}');
      _switchSource(idx);
    } else if (!_playerInitialized) {
      _selectedSource = idx;
      _currentUrl = _sources[idx].url;
    }

    if (mounted) setState(() {});
  }

  /// Re-enter 时根据保存的集数名 + 线路名选择播放源（三级优先级）
  void _applySavedEpisodeSelection() {
    if (_savedEpisodeName == null || _savedEpisodeName!.isEmpty) return;
    final savedRef = _savedEpisodeName!;
    var matched = false;
    if (_savedLineName != null && _savedLineName!.isNotEmpty) {
      final exactIdx = _sources.indexWhere((s) =>
          matchesEpisode(s, savedRef) &&
          s.name == _savedLineName &&
          s.usable &&
          s.playlistMs != null &&
          s.playlistMs! < 999999);
      if (exactIdx != -1) {
        _selectedSource = exactIdx;
        _currentUrl = _sources[exactIdx].url;
        matched = true;
        debugPrint('PLAYER: exact match — ${_sources[exactIdx].name} / $_savedEpisodeName');
      }
    }
    // 优先级2: 集数名匹配（任意线路）
    if (!matched) {
      for (var i = 0; i < _sources.length; i++) {
        if (matchesEpisode(_sources[i], savedRef) &&
            _sources[i].usable &&
            _sources[i].playlistMs != null &&
            _sources[i].playlistMs! < 999999) {
          _selectedSource = i;
          _currentUrl = _sources[i].url;
          matched = true;
          debugPrint('PLAYER: episode match (any line) — ${_sources[i].name} / $_savedEpisodeName');
          break;
        }
      }
    }
    // 优先级3: 保存线路不可用，用最快线路匹配同名集数
    if (!matched && _fastestIndex != null) {
      final fastestLineName = _sources[_fastestIndex!].name;
      final matchIdx = _sources.indexWhere((s) =>
          s.name == fastestLineName && matchesEpisode(s, savedRef) && s.usable);
      if (matchIdx != -1) {
        _selectedSource = matchIdx;
        _currentUrl = _sources[matchIdx].url;
      } else {
        _selectedSource = _fastestIndex!;
        _currentUrl = _sources[_fastestIndex!].url;
      }
      debugPrint('PLAYER: fallback to fastest — $fastestLineName');
    }
  }

  int _representativeIndexForLine(String lineName) {
    final ref = _currentEpisodeRef.isNotEmpty
        ? _currentEpisodeRef
        : (_savedEpisodeName?.isNotEmpty == true
            ? _savedEpisodeName!
            : (_sources.isNotEmpty ? episodeRef(_sources.first) : ''));
    if (ref.isNotEmpty) {
      final episodeIdx = _sources.indexWhere(
        (s) => s.name == lineName && matchesEpisode(s, ref),
      );
      if (episodeIdx != -1) return episodeIdx;
    }
    return _sources.indexWhere((s) => s.name == lineName);
  }

  void _applyProbeRecord(VideoSource target, SourceProbeRecord record) {
    QualityTier? tier;
    if (record.usable &&
        record.effectiveTierIndex >= 0 &&
        record.effectiveTierIndex < QualityTier.values.length) {
      tier = QualityTier.values[record.effectiveTierIndex];
    }

    target.applyProbeMetrics(
      usable: record.usable,
      playlistMs: record.latencyMs,
      probeWidth: record.usable && record.width > 0 ? record.width : null,
      probeHeight: record.usable && record.height > 0 ? record.height : null,
      probeBitrateKbps:
          record.usable && record.bitrateKbps > 0 ? record.bitrateKbps : null,
      firstFrameMs:
          record.usable && record.firstFrameMs > 0 ? record.firstFrameMs : null,
      probedTier: tier,
      probeDurationSec:
          record.usable && record.durationSec > 0 ? record.durationSec : null,
      probeHasEndlist: record.usable ? record.hasEndlist : null,
    );
  }

  void _propagateLineMetrics(String lineName, VideoSource template) {
    for (var i = 0; i < _sources.length; i++) {
      if (_sources[i].name == lineName) {
        _sources[i].copyProbeFrom(template);
      }
    }
  }

  void _writeProbeCache(String lineName, String probeUrl, VideoSource src) {
    final key = SourceProbeKeys.lineKey(widget.video.id, lineName);
    final tier = src.probedTier ?? QualityTier.unknown;
    Hive.box<SourceProbeRecord>('source_probes').put(
      key,
      SourceProbeRecord(
        probeUrl: probeUrl,
        usable: src.usable,
        latencyMs: src.playlistMs ?? 999999,
        width: src.probeWidth ?? 0,
        height: src.probeHeight ?? 0,
        bitrateKbps: src.probeBitrateKbps ?? 0,
        firstFrameMs: src.firstFrameMs ?? 0,
        effectiveTierIndex: tier.index,
        testedAtEpoch: DateTime.now().millisecondsSinceEpoch,
        durationSec: src.probeDurationSec ?? 0,
        hasEndlist: src.probeHasEndlist ?? false,
      ),
    );
  }

  Future<void> _runSpeedTest() async {
    _client = http.Client();
    _testedCount = 0;

    // distinct 线路：每种 name 测一次（代表 URL 优先当前集）
    final uniqueLines = <String>[];
    final indices = <int>[];
    for (var i = 0; i < _sources.length; i++) {
      final lineName = _sources[i].name;
      if (!uniqueLines.contains(lineName)) {
        uniqueLines.add(lineName);
        indices.add(_representativeIndexForLine(lineName));
      }
    }

    if (_savedLineName != null && _savedLineName!.isNotEmpty) {
      final savedRep = _representativeIndexForLine(_savedLineName!);
      final savedPos = indices.indexOf(savedRep);
      if (savedPos > 0) {
        final idx = indices.removeAt(savedPos);
        indices.insert(0, idx);
      }
    }

    if (mounted && !_disposed) {
      setState(() {
        _indicesToTest = indices;
        _totalLinesToTest = indices.length;
      });
    }

    final probeBox = Hive.box<SourceProbeRecord>('source_probes');
    final now = DateTime.now().millisecondsSinceEpoch;
    const ttlMs = 12 * 60 * 60 * 1000;

    // 1. 线路级缓存预热 + 传播到各集
    for (final idx in indices) {
      if (idx < 0) continue;
      final lineName = _sources[idx].name;
      final key = SourceProbeKeys.lineKey(widget.video.id, lineName);
      final record = probeBox.get(key);
      if (record != null && (now - record.testedAtEpoch) < ttlMs) {
        _applyProbeRecord(_sources[idx], record);
        _propagateLineMetrics(lineName, _sources[idx]);
        debugPrint(
          'SPEED: [$idx] CACHE HIT $lineName ${record.latencyMs}ms usable=${record.usable}',
        );
      }
    }

    // 2. Champion 快启：缓存命中的推荐线路复测阶段 1+2
    if (!_playerInitialized) {
      final episode = _savedEpisodeName?.isNotEmpty == true
          ? _savedEpisodeName!
          : (_sources.isNotEmpty ? episodeRef(_sources.first) : '');

      int? championIdx;
      if (episode.isNotEmpty) {
        championIdx = SourcePicker.pickMainIndex(_sources, episodeName: episode);
        if (championIdx != null) {
          final latency = _sources[championIdx].playlistMs;
          if (latency == null || latency >= SourcePicker.latencyGood) {
            championIdx = null;
          }
        }
      }

      if (championIdx != null && _client != null) {
        final lineName = _sources[championIdx].name;
        final repIdx = _representativeIndexForLine(lineName);
        debugPrint(
          'PLAYER: Champion $lineName cached — re-testing rep idx $repIdx...',
        );
        _sources[repIdx].playlistMs = null;
        await _testLine(repIdx, _client!);

        if (!_disposed &&
            _sources[repIdx].usable &&
            _sources[repIdx].playlistMs != null &&
            _sources[repIdx].playlistMs! < SourcePicker.latencyGood) {
          final playIdx =
              SourcePicker.pickMainIndex(_sources, episodeName: episode) ??
                  championIdx;
          _selectedSource = playIdx;
          _currentUrl = _sources[playIdx].url;
          _recommendedLineName = _sources[playIdx].name;
          debugPrint(
            'PLAYER: Champion re-test passed (${_sources[repIdx].playlistMs}ms) — init',
          );
          if (mounted) setState(() => _stage = LoadingStage.initPlayer);
          await _initPlayer();
          if (_disposed) return;
        } else {
          debugPrint('PLAYER: Champion re-test failed, continuing full test.');
        }
      }
    }

    // 3. 剩余 distinct 线路并行两阶段检测
    final pending =
        indices.where((idx) => idx >= 0 && _sources[idx].playlistMs == null).toList();
    if (pending.isNotEmpty && !_disposed && !_abortSpeedTest) {
      await Future.wait(pending.map((idx) async {
        if (_disposed || _abortSpeedTest) return;
        final localClient = http.Client();
        try {
          await _testLine(idx, localClient);
        } finally {
          localClient.close();
        }
        if (_disposed || _abortSpeedTest) return;
        if (mounted) setState(() => _testedCount++);
      }));
    } else if (mounted) {
      setState(() => _testedCount = indices.length);
    }

    _client?.close();
    _client = null;
    if (_disposed) return;

    // 4. 传播 distinct 线路结果到本剧所有同 name 源
    final lineTemplates = <String, VideoSource>{};
    for (final idx in _indicesToTest) {
      if (idx >= 0) {
        lineTemplates[_sources[idx].name] = _sources[idx];
      }
    }
    for (var i = 0; i < _sources.length; i++) {
      final template = lineTemplates[_sources[i].name];
      if (template != null) {
        _sources[i].copyProbeFrom(template);
      }
    }

    await _applyRecommendedSource(autoInit: !_playerInitialized);

    final usable = _sources.where((s) => s.usable && s.playlistMs != null).length;
    debugPrint(
      'SPEED: done | tested=$_testedCount usable=$usable recommended=$_recommendedLineName',
    );
  }

  /// 两阶段：可用性 → 流探测；写线路级缓存并传播。
  Future<void> _testLine(int index, http.Client client) async {
    if (_abortSpeedTest || index < 0 || index >= _sources.length) return;
    final src = _sources[index];
    if (!src.url.startsWith('http')) {
      src.applyProbeMetrics(usable: false, playlistMs: 999999);
      _writeProbeCache(src.name, src.url, src);
      _propagateLineMetrics(src.name, src);
      debugPrint('SPEED: [$index] ${src.name} skipped non-http URL');
      return;
    }
    final lineName = src.name;
    final url = src.url;
    final label =
        src.sourceConfigName.isNotEmpty ? src.sourceConfigName : lineName;

    try {
      final available = await StreamProbe.checkAvailability(url, client);
      if (!available) {
        src.applyProbeMetrics(usable: false, playlistMs: 999999);
        _writeProbeCache(lineName, url, src);
        _propagateLineMetrics(lineName, src);
        debugPrint('SPEED: [$index] $lineName availability ❌');
        return;
      }

      final result = await StreamProbe.probe(url, client, label: label);
      if (result.success) {
        src.applyProbeMetrics(
          usable: true,
          playlistMs: result.playlistMs > 0 ? result.playlistMs : 999999,
          probeWidth: result.width > 0 ? result.width : null,
          probeHeight: result.height > 0 ? result.height : null,
          probeBitrateKbps:
              result.bitrateKbps > 0 ? result.bitrateKbps : null,
          firstFrameMs: result.firstFrameMs > 0 ? result.firstFrameMs : null,
          probedTier: result.effectiveTier,
          probeDurationSec: result.durationSec > 0 ? result.durationSec : null,
          probeHasEndlist: result.hasEndlist,
        );
      } else {
        src.applyProbeMetrics(usable: false, playlistMs: 999999);
      }
      _writeProbeCache(lineName, url, src);
      _propagateLineMetrics(lineName, src);
      debugPrint(
        'SPEED: [$index] $lineName 清单${src.playlistMs}ms '
        '(清单${result.playlistMs}ms 首段${result.firstFrameMs}ms) '
        '${result.success ? "✅ ${src.probeWidth}x${src.probeHeight}" : "❌"}',
      );
    } catch (e) {
      src.applyProbeMetrics(usable: false, playlistMs: 999999);
      _writeProbeCache(lineName, url, src);
      _propagateLineMetrics(lineName, src);
      debugPrint('SPEED: [$index] $lineName ERROR: $e');
    }
  }
  void _switchSource(int index) {
    _saveProgress();
    final src = _sources[index];
    _selectedSource = index;
    _currentUrl = src.url;
    
    final shouldAutoPlay = _startPlayRequested && (_player?.isPlayingNotifier.value == true);
    _player?.setSource(_currentUrl, autoPlay: shouldAutoPlay);
    setState(() {});
  }

  Color _speedColor(int? ms) {
    if (ms == null) return Colors.white24;
    if (ms < 300) return Colors.green;
    if (ms < 800) return Colors.orange;
    return Colors.redAccent;
  }

  String _speedLabel(int? ms) {
    if (ms == null) return '...';
    if (ms >= 999999) return '超时';
    return '${ms}ms';
  }

  double get _loadingProgress {
    switch (_stage) {
      case LoadingStage.fetchingDetail:
        return 0.15;
      case LoadingStage.testingSpeed:
        if (_totalLinesToTest > 0) {
          return 0.3 + 0.6 * (_testedCount / _totalLinesToTest);
        }
        return 0.90;
      case LoadingStage.initPlayer:
        return 0.95;
      case LoadingStage.ready:
        return 1.0;
      case LoadingStage.error:
        return 0.0;
    }
  }

  Widget _buildBackgroundPoster() {
    // Completely remove the background poster stack once playback has started to free 100% of GPU resources
    if (_startPlayRequested) {
      return const SizedBox.shrink();
    }

    final imgDomain = MubuApiClient.instance.imgDomain;
    final coverUrl = widget.video.coverUrl(imgDomain);
    if (coverUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    // Animating only the poster image opacity (instead of BackdropFilter) removes compositing lag
    final double imgOpacity = (_stage != LoadingStage.ready) ? 0.45 : 0.0;

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 600),
            opacity: imgOpacity,
            curve: Curves.easeOutCubic,
            child: CachedNetworkImage(
              imageUrl: coverUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(color: Colors.black.withOpacity(0.2)),
            ),
          ),
        ],
      ),
    );
  }

  List<String> get _uniqueLineNames {
    final names = <String>{};
    for (final s in _sources) {
      names.add(s.name);
    }
    return names.toList();
  }

  String get _selectedLineName =>
      _sources.isNotEmpty ? _sources[_selectedSource].name : '';

  String? get _fastestLineName =>
      _fastestIndex != null &&
              _fastestIndex! >= 0 &&
              _fastestIndex! < _sources.length
          ? _sources[_fastestIndex!].name
          : null;

  VideoSource? _representativeForLine(String lineName) {
    var idx = _sources.indexWhere(
      (s) => s.name == lineName && matchesEpisode(s, _currentEpisodeRef),
    );
    if (idx == -1) {
      idx = _sources.indexWhere((s) => s.name == lineName);
    }
    return idx != -1 ? _sources[idx] : null;
  }

  String _lineQualityCaption(String lineName) {
    final s = _representativeForLine(lineName);
    if (s == null) return lineName;
    if (s.playlistMs == null) return '检测中…';
    return SourceQuality.resolutionLabel(s) ?? lineName;
  }

  Color _lineQualityColor(String lineName) {
    final s = _representativeForLine(lineName);
    if (s == null) return Colors.white24;
    return SourceQuality.resolutionColor(s);
  }

  int? _lineSpeed(String lineName) {
    final s = _representativeForLine(lineName);
    return s?.playlistMs;
  }

  bool _isLineUsable(String lineName) {
    final s = _representativeForLine(lineName);
    return s?.usable ?? true;
  }

  /// Sort by probe resolution ↓ → duration ↓ → bitrate → latency ↑.
  int _compareLineForSelector(String a, String b) {
    final sA = _representativeForLine(a);
    final sB = _representativeForLine(b);
    final rankA = sA != null ? SourceQuality.resolutionRank(sA) : 0;
    final rankB = sB != null ? SourceQuality.resolutionRank(sB) : 0;
    if (rankA != rankB) return rankB.compareTo(rankA);

    final minA = sA?.durationMinute ?? 0;
    final minB = sB?.durationMinute ?? 0;
    if (minA != minB) return minB.compareTo(minA);

    final brA = (sA?.probeBitrateKbps ?? 0) > 0;
    final brB = (sB?.probeBitrateKbps ?? 0) > 0;
    if (brA != brB) return brA ? -1 : 1;

    final latA = sA?.playlistMs ?? 999999;
    final latB = sB?.playlistMs ?? 999999;
    return latA.compareTo(latB);
  }

  List<int> get _currentLineSourceIndices {
    final indices = <int>[];
    final currentName = _selectedLineName;
    for (var i = 0; i < _sources.length; i++) {
      if (_sources[i].name == currentName) {
        indices.add(i);
      }
    }
    return indices;
  }

  /// Long episode labels (e.g. movie versions like "BD英语中字") read poorly in
  /// the fixed square grid, so we fall back to an auto-sizing wrap layout.
  bool _episodesNeedWrap(List<int> epIndices) {
    for (final i in epIndices) {
      if (_sources[i].sourceName.length > 4) return true;
    }
    return false;
  }

  /// Episode grid: square cells for short labels, wrapped pills for long ones.
  Widget _buildEpisodeGrid(
    List<int> epIndices, {
    bool closeOnTap = false,
  }) {
    void onTap(int sourceIdx) {
      _switchSource(sourceIdx);
      if (closeOnTap) Navigator.pop(context);
    }

    if (_episodesNeedWrap(epIndices)) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final sourceIdx in epIndices)
            _EpisodeButton(
              label: _sources[sourceIdx].sourceName,
              duration: SourceQuality.formatDurationMmSs(_sources[sourceIdx]),
              active: sourceIdx == _selectedSource,
              flexible: true,
              onTap: () => onTap(sourceIdx),
            ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 80).floor().clamp(3, 8);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.6,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: epIndices.length,
          itemBuilder: (context, index) {
            final sourceIdx = epIndices[index];
            final s = _sources[sourceIdx];
            return _EpisodeButton(
              label: s.sourceName,
              duration: SourceQuality.formatDurationMmSs(s),
              active: sourceIdx == _selectedSource,
              onTap: () => onTap(sourceIdx),
            );
          },
        );
      },
    );
  }

  void _switchLine(String newLineName) {
    if (newLineName == _selectedLineName) return;

    final currentEpisodeName = _sources[_selectedSource].sourceName;
    final currentEpisodeRef = _currentEpisodeRef;
    int targetIdx = -1;
    for (var i = 0; i < _sources.length; i++) {
      if (_sources[i].name == newLineName &&
          matchesEpisode(_sources[i], currentEpisodeRef)) {
        targetIdx = i;
        break;
      }
    }

    if (targetIdx == -1) {
      for (var i = 0; i < _sources.length; i++) {
        if (_sources[i].name == newLineName &&
            _sources[i].sourceName == currentEpisodeName) {
          targetIdx = i;
          break;
        }
      }
    }
    
    if (targetIdx == -1) {
      targetIdx = _sources.indexWhere((s) => s.name == newLineName);
    }

    if (targetIdx != -1) _switchSource(targetIdx);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final isWide = width >= 900;
    final isLandscape = width >= 600 && width > height;
    final useRowLayout = isWide || isLandscape;

    return PopScope(
      canPop: true,
      child: CallbackShortcuts(
        bindings: {SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
              // 1. Blurred Movie Poster Background
              _buildBackgroundPoster(),

              // 2. Main split UI
              Column(
                children: [
                  _buildTopHeader(),
                  Expanded(
                    child: useRowLayout
                        ? Padding(
                            padding: EdgeInsets.all(isWide ? 28 : 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left video panel — always 16:9
                                Expanded(
                                  flex: isWide ? 65 : 66,
                                  child: AspectRatio(
                                    aspectRatio: _videoAspectRatio,
                                    child: _buildVideoPlayerContainer(),
                                  ),
                                ),
                                SizedBox(width: isWide ? 28 : 12),
                                // Right detail / episodes panel
                                Expanded(
                                  flex: isWide ? 35 : 34,
                                  child: SingleChildScrollView(
                                    physics: const BouncingScrollPhysics(),
                                    child: _buildMovieInfoAndEpisodes(useRowLayout),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _isPortraitVideo
                            ? _buildPortraitLayout()
                            : Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                                    child: AspectRatio(
                                      aspectRatio: _videoAspectRatio,
                                      child: _buildVideoPlayerContainer(),
                                    ),
                                  ),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      physics: const BouncingScrollPhysics(),
                                      child: _buildMovieInfoAndEpisodes(false),
                                    ),
                                  ),
                                ],
                              ),
                  ),
                ],
              ),

              // 3. Dropdown click-outside mask
              if (_expanded)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _expanded = false),
                    child: Container(color: Colors.transparent),
                  ),
                ),

              // 4. Floating line dropdown card (anchored below line label)
              if (_expanded && _sources.isNotEmpty)
                CompositedTransformFollower(
                  link: _lineLink,
                  offset: const Offset(0, 8),
                  targetAnchor: useRowLayout ? Alignment.bottomRight : Alignment.bottomLeft,
                  followerAnchor: useRowLayout ? Alignment.topRight : Alignment.topLeft,
                  child: _buildLineDropdownCard(),
                ),

              // 5. Full-screen error overlay — last child = on top of everything
              if (_stage == LoadingStage.error)
                _buildFullScreenError(),
            ],
          ),
        ),
      ),
    ),
  );
  }

  /// 搜索页同款玻璃态圆形图标按钮
  Widget _glassIconButton(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Icon(icon, color: Colors.white70, size: 18),
        ),
      ),
    );
  }

  /// 构建播放页的顶部导航与状态栏
  Widget _buildTopHeader() {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: kGlass.withOpacity(0.85),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _glassIconButton(Icons.arrow_back_ios_new, onTap: () => Navigator.pop(context)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              widget.video.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 收藏胶囊按钮
          GestureDetector(
            onTap: _toggleBookmark,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _isBookmarked
                      ? _primaryRed
                      : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isBookmarked
                        ? _primaryRed
                        : Colors.white.withOpacity(0.08),
                  ),
                  boxShadow: _isBookmarked
                      ? [
                          BoxShadow(
                            color: _primaryRed.withOpacity(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bookmark,
                      color: _isBookmarked ? Colors.white : Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '收藏',
                      style: TextStyle(
                        color: _isBookmarked ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _getFastPreviewUrl() {
    if (_sources.isEmpty || _selectedSource < 0 || _selectedSource >= _sources.length) return null;
    final currentEpisode = _currentEpisodeRef;
    final currentUrl = _sources[_selectedSource].url;
    return SourcePicker.pickPreview(
      _sources,
      episodeName: currentEpisode,
      excludeUrl: currentUrl,
    )?.url;
  }

  /// Resume position with optional intro skip (titles_duration from API).
  int? _playbackStartPositionMs() {
    if (_selectedSource < 0 || _selectedSource >= _sources.length) return null;
    final introMs = _sources[_selectedSource].titlesDurationSec * 1000;
    var target = _savedPositionMs;
    if (introMs > 0 && (target == null || target < introMs)) {
      target = introMs;
    }
    if (target != null && target > 3000) return target;
    if (introMs > 0) return introMs;
    return null;
  }

  Widget _buildVideoPlayerContainer() {
    final imgDomain = MubuApiClient.instance.imgDomain;
    final coverUrl = widget.video.coverUrl(imgDomain);
    final showOverlay = _stage == LoadingStage.ready && !_startPlayRequested;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        // Sharp border is layered on top of the Stack children to avoid being blurred by BackdropFilter
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Video Widget
          if (_stage == LoadingStage.ready && _playerInitialized && _player != null && _startPlayRequested)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _player!.buildVideoWidget(
                  context,
                  title: widget.video.title,
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
            ),

          // 2. 播放器封面海报图 (当播放开始后淡出，并使用 IgnorePointer 避免遮挡鼠标/触控事件)
          if (coverUrl.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !showOverlay, // 播放时忽略事件拦截，使得手势能穿透到下层播放器
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 600),
                  opacity: showOverlay ? 1.0 : 0.0,
                  curve: Curves.easeOutCubic,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),

          // 3. 磨砂玻璃模糊层 (当播放开始后淡出，同样使用 IgnorePointer 避免遮挡手势事件)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !showOverlay, // 播放时忽略事件拦截，使得手势能穿透到下层播放器
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 600),
                opacity: showOverlay ? 1.0 : 0.0,
                curve: Curves.easeOutCubic,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      color: const Color(0xFF070708).withOpacity(0.45),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 4. Overlays: Error view — removed, now at page level

          // 5. Overlays: ConcentricHud (only visible while loading, hidden on error)
          if (_stage != LoadingStage.ready && _stage != LoadingStage.error)
            Center(
              child: ConcentricHud(
                progress: _loadingProgress,
                sources: _sources,
                indicesToTest: _indicesToTest,
              ),
            ),

          // 6. Overlays: Breathing play button (fades in/out and ignores taps when hidden)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !showOverlay,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 600),
                opacity: showOverlay ? 1.0 : 0.0,
                curve: Curves.easeOutCubic,
                child: Center(
                  child: BreathingPlayPulse(
                      onTap: () {
                        setState(() {
                          _startPlayRequested = true;
                        });
                        _abortBackgroundSpeedTest();
                        _player?.play().then((_) {
                          final episodeName = _sources.isNotEmpty ? _sources[_selectedSource].sourceName : null;
                          final lineName = _sources.isNotEmpty ? _sources[_selectedSource].name : null;
                          MubuStorage.recordWatch(
                            widget.video,
                            positionMs: _savedPositionMs,
                            durationMs: _savedDurationMs,
                            episodeName: episodeName,
                            lineName: lineName,
                          );
                          final startMs = _playbackStartPositionMs();
                          if (startMs != null) {
                            _player?.seek(Duration(milliseconds: startMs));
                          }
                          // 启动弱网看门狗（播放开始后才激活，避免加载阶段误触发）
                          _startBufferingWatchdog();
                        }).catchError((e) {
                        debugPrint('PLAYER: play() failed: $e');
                      });
                      // Start periodic progress save every 10 seconds
                      _progressTimer?.cancel();
                      _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
                        _saveProgress();
                      });
                    },
                  ),
                ),
              ),
            ),
          ),

          // 7. Sharp Border Overlay (layered last to ensure clean, crisp corners)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 竖屏视频布局（支持 sticky player）
  Widget _buildPortraitLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final videoHeight = _calculateVideoHeight(constraints.maxHeight);
        return Stack(
          children: [
            // 视频区域（sticky，固定在顶部）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: videoHeight,
              child: Container(
                color: Colors.black,
                child: _buildVideoPlayerContainer(),
              ),
            ),

            // 内容区域（从视频下方开始滚动）
            Positioned(
              top: videoHeight,
              left: 0,
              right: 0,
              bottom: 0,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                child: _buildMovieInfoAndEpisodes(false),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 弹出底部选集浮层
  void _showEpisodesBottomSheet() {
    final epIndices = _currentLineSourceIndices;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF16161A),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '剧集列表 (${epIndices.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      physics: const BouncingScrollPhysics(),
                      child: _buildEpisodeGrid(epIndices, closeOnTap: true),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMovieInfoAndEpisodes(bool isWide) {
    final epIndices = _currentLineSourceIndices;
    final metaString = [
      if (widget.video.year.isNotEmpty) widget.video.year,
      if (widget.video.category.isNotEmpty) widget.video.category,
      if (widget.video.score.isNotEmpty) '评分 ${widget.video.score}',
    ].join(' • ');

    return Container(
      padding: isWide ? const EdgeInsets.all(8) : const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info Block — clickable line selector
          Row(
            children: [
              if (_sources.isNotEmpty)
                CompositedTransformTarget(
                  link: _lineLink,
                  child: GestureDetector(
                    onTap: _showAdaptiveLineSelector,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _expanded ? _primaryRed.withOpacity(0.15) : Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _expanded ? _primaryRed.withOpacity(0.4) : Colors.white.withOpacity(0.12),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _speedDot(_sources.isNotEmpty ? _sources[_selectedSource].playlistMs : null),
                          const SizedBox(width: 6),
                          Text(
                            '${_selectedLineName.isNotEmpty ? _selectedLineName : '清晰度'} · ${_speedLabel(_sources[_selectedSource].playlistMs)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white38,
                            size: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: const Text(
                    '清晰度',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  metaString,
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.video.title,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Text(
            widget.video.score.isNotEmpty ? '评分：${widget.video.score}' : '暂无评分',
            style: const TextStyle(color: kRed, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          if (_description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _description,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, height: 1.5),
              maxLines: _isPortraitVideo ? 2 : 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 16),

          Divider(color: Colors.white.withOpacity(0.05), height: 1),
          const SizedBox(height: 16),

          // 移动竖屏短剧下显示专用的弹窗触发器按钮，从而节省首屏空间
          if (!isWide && _isPortraitVideo) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _showEpisodesBottomSheet,
                icon: const Icon(Icons.playlist_play_rounded, size: 22),
                label: Text(
                  '选集 (当前：${_sources.isNotEmpty ? _sources[_selectedSource].sourceName : '1'})',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.06),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.white.withOpacity(0.08)),
                  ),
                ),
              ),
            ),
          ] else ...[
            Text(
              '剧集列表 (${epIndices.length})',
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_stage != LoadingStage.ready && _stage != LoadingStage.error)
              _buildEpisodeSkeleton()
            else if (epIndices.isEmpty)
              const Text('暂无剧集数据', style: TextStyle(color: Colors.white24, fontSize: 12))
            else
              _buildEpisodeGrid(epIndices),
          ],
        ],
      ),
    );
  }

  /// 加载中显示的剧集骨架屏
  Widget _buildEpisodeSkeleton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 80).floor().clamp(3, 8);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.6,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: crossAxisCount * 2,
          itemBuilder: (context, index) => const _EpisodeSkeletonCell(),
        );
      },
    );
  }

  void _showAdaptiveLineSelector() {
    if (isDesktopPlatform) {
      setState(() => _expanded = !_expanded);
    } else {
      final isWide = MediaQuery.of(context).size.width >= 600;
      if (isWide) {
        // TV / Pad landscape: Center Dialog
        MubuDialog.showCustom(
          context: context,
          builder: (ctx) => Center(
            child: Material(
              color: Colors.transparent,
              child: MubuDialogContainer(
                maxWidth: 360,
                child: _buildLineSelectorContent(isDialog: true),
              ),
            ),
          ),
        );
      } else {
        // Mobile: BottomSheet
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (ctx) => Container(
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withOpacity(0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
            child: SafeArea(
              top: false,
              child: _buildLineSelectorContent(isBottomSheet: true),
            ),
          ),
        );
      }
    }
  }

  Widget _buildLineDropdownCard() {
    final screenWidth = MediaQuery.of(context).size.width;
    final dropdownMaxWidth = (screenWidth - 48).clamp(200.0, 320.0); // 左右各留24px安全边距

    return Material(
      color: Colors.transparent,
      child: MubuDialogContainer(
        maxWidth: dropdownMaxWidth,
        margin: EdgeInsets.zero,
        borderRadius: 16,
        child: _buildLineSelectorContent(),
      ),
    );
  }

  Widget _buildLineSelectorContent({bool isBottomSheet = false, bool isDialog = false}) {
    final lines = _uniqueLineNames.toList()
      ..sort((a, b) => _compareLineForSelector(a, b));
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallHeight = screenHeight < 500 && !isBottomSheet;
    
    return Padding(
      padding: EdgeInsets.all(isBottomSheet ? 24 : (isSmallHeight ? 10 : 16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shuffle, color: Colors.white38, size: 15),
              const SizedBox(width: 8),
              const Text('切换线路', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (!isDialog && !isBottomSheet)
                GestureDetector(
                  onTap: () => setState(() => _expanded = false),
                  child: const Icon(Icons.close, color: Colors.white38, size: 18),
                )
              else if (isBottomSheet)
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white54, size: 16),
                  ),
                ),
            ],
          ),
          SizedBox(height: isSmallHeight ? 8 : 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: isBottomSheet ? screenHeight * 0.5 : (isSmallHeight ? 100 : 300)),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: lines.length,
              itemBuilder: (context, idx) {
                final name = lines[idx];
                final active = name == _selectedLineName;
                final speed = _lineSpeed(name);
                final usable = _isLineUsable(name);
                final isRecommended =
                    _recommendedLineName != null && name == _recommendedLineName;
                final isFastest = _fastestLineName != null &&
                    name == _fastestLineName &&
                    !isRecommended;
                if (!usable && !active) return const SizedBox.shrink();

                return GestureDetector(
                  onTap: () {
                    _switchLine(name);
                    if (isDesktopPlatform && _expanded) {
                      setState(() => _expanded = false);
                    } else if (isBottomSheet || isDialog) {
                      Navigator.pop(context);
                    }
                  },
                  child: Container(
                    margin: EdgeInsets.only(bottom: isSmallHeight ? 4 : 8),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: isSmallHeight ? 8 : 12),
                    decoration: BoxDecoration(
                      color: active ? _primaryRed : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: active ? _primaryRed : Colors.white.withOpacity(0.05)),
                    ),
                    child: Row(
                      children: [
                        _speedDot(speed),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  color: active ? Colors.white : Colors.white.withOpacity(0.85),
                                  fontSize: 14,
                                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _lineQualityCaption(name),
                                style: TextStyle(
                                  color: _lineQualityColor(name).withOpacity(0.9),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _speedLabel(speed),
                              style: TextStyle(
                                color: active ? Colors.white70 : _speedColor(speed),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (isRecommended || isFastest) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isRecommended ? _primaryRed : Colors.green).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isRecommended ? '推荐' : '最快',
                                  style: TextStyle(
                                    color: isRecommended ? _primaryRed : Colors.greenAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _speedDot(int? ms) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _speedColor(ms),
        boxShadow: [BoxShadow(color: _speedColor(ms).withAlpha(80), blurRadius: 4)],
      ),
    );
  }

  Widget _buildFullScreenError() {
    final isMobile = MediaQuery.of(context).size.width < 650;

    return Positioned.fill(
      child: GestureDetector(
        // Block all taps through the overlay
        onTap: () {},
        child: Stack(
          children: [
            // Semi-transparent dark backdrop with blur
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(color: Colors.black.withOpacity(0.65)),
                ),
              ),
            ),
            // Centered error card
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 32),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: isMobile ? double.infinity : 420,
                      ),
                      padding: EdgeInsets.all(isMobile ? 24 : 36),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161A).withOpacity(0.95),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.85),
                            blurRadius: 50,
                            offset: const Offset(0, 25),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Close button (with hover animation)
                          Align(
                            alignment: Alignment.centerRight,
                            child: HoverCloseButton(
                              onTap: () => Navigator.pop(context),
                              size: 18,
                            ),
                          ),
                          SizedBox(height: isMobile ? 4 : 8),
                          // Video title
                          Text(
                            widget.video.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isMobile ? 17 : 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: isMobile ? 10 : 14),
                          // Error message
                          Text(
                            _errorMessage?.replaceFirst('Exception: ', '') ?? '播放出错',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.45),
                              fontSize: isMobile ? 13 : 15,
                              height: 1.5,
                            ),
                          ),
                          SizedBox(height: isMobile ? 28 : 36),
                          // Retry button
                          SizedBox(
                            width: double.infinity,
                            height: isMobile ? 46 : 52,
                            child: ElevatedButton.icon(
                              onPressed: _loadAndPrepare,
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                              label: const Text(
                                '重试',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryRed,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ).copyWith(
                                backgroundColor: WidgetStateProperty.resolveWith((states) {
                                  if (states.contains(WidgetState.hovered)) {
                                    return const Color(0xFFF40F1D);
                                  }
                                  return _primaryRed;
                                }),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Breathing Crimson Play Button with Pulsing Wave Rings
class BreathingPlayPulse extends StatefulWidget {
  final VoidCallback onTap;

  const BreathingPlayPulse({super.key, required this.onTap});

  @override
  State<BreathingPlayPulse> createState() => _BreathingPlayPulseState();
}

class _BreathingPlayPulseState extends State<BreathingPlayPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    // 移动端 64px, 桌面 80px
    final coreSize = isMobile ? 64.0 : 80.0;
    final iconSize = isMobile ? 36.0 : 46.0;
    final pulseRange = isMobile ? 32.0 : 40.0;
    final pulseRange2 = isMobile ? 16.0 : 20.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer pulse ring 2 (subtle)
              Container(
                width: coreSize + pulseRange * _controller.value,
                height: coreSize + pulseRange * _controller.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE50914).withOpacity(0.10 * (1.0 - _controller.value)),
                ),
              ),
              // Outer pulse ring 1 (subtle)
              Container(
                width: coreSize + pulseRange2 * _controller.value,
                height: coreSize + pulseRange2 * _controller.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE50914).withOpacity(0.18 * (1.0 - _controller.value)),
                ),
              ),
              // Core Play Button
              Container(
                width: coreSize,
                height: coreSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE50914),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE50914).withOpacity(0.35),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: iconSize,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EpisodeButton extends StatefulWidget {
  final String label;
  final String? duration;
  final bool active;

  /// When true, the button sizes to its content (for [Wrap] layouts with long
  /// labels) and wraps text over up to two lines instead of clipping.
  final bool flexible;
  final VoidCallback onTap;

  const _EpisodeButton({
    required this.label,
    this.duration,
    required this.active,
    this.flexible = false,
    required this.onTap,
  });

  @override
  State<_EpisodeButton> createState() => _EpisodeButtonState();
}

class _EpisodeButtonState extends State<_EpisodeButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    const primaryRed = Color(0xFFE50914);
    final flexible = widget.flexible;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment:
          flexible ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          widget.label,
          maxLines: flexible ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: flexible ? TextAlign.start : TextAlign.center,
          style: TextStyle(
            color: active
                ? Colors.white
                : (_hovered ? Colors.white : Colors.white60),
            fontSize: 12,
            height: 1.25,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        if (widget.duration != null) ...[
          const SizedBox(height: 3),
          Text(
            widget.duration!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active
                  ? Colors.white70
                  : (_hovered ? Colors.white54 : Colors.white38),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: flexible
              ? const BoxConstraints(minWidth: 64, maxWidth: 220)
              : null,
          padding: flexible
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
              : null,
          transform: _hovered
              ? (Matrix4.identity()..scale(1.05))
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? primaryRed
                : (_hovered ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.05)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? primaryRed
                  : (_hovered ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.05)),
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: primaryRed.withOpacity(_hovered ? 0.55 : 0.35),
                      blurRadius: _hovered ? 12 : 8,
                      spreadRadius: 1,
                      offset: Offset(0, _hovered ? 3 : 2),
                    )
                  ]
                : (_hovered
                    ? [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : null),
          ),
          alignment: flexible ? null : Alignment.center,
          child: content,
        ),
      ),
    );
  }
}

/// 剧集列表骨架屏单元格（脉冲动画）
class _EpisodeSkeletonCell extends StatefulWidget {
  const _EpisodeSkeletonCell();

  @override
  State<_EpisodeSkeletonCell> createState() => _EpisodeSkeletonCellState();
}

class _EpisodeSkeletonCellState extends State<_EpisodeSkeletonCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.04 + 0.08 * _controller.value,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      },
    );
  }
}
