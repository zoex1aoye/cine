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
        // 播放器已在测速期间初始化；确保 stage 同步到 ready（并行测速路径可能遗漏）
        if (mounted && _stage != LoadingStage.ready) {
          setState(() => _stage = LoadingStage.ready);
        }
      } else if (_savedEpisodeName != null && _savedEpisodeName!.isNotEmpty) {
        // Re-enter: 保存线路慢，需要选源再 init
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
        // 普通场景但没有快线 — 用默认源 init
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
      // 先清理旧播放器（重试场景）
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
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('播放器加载超时'),
      );
      await activePlayer.pause();
      if (_disposed) {
        await activePlayer.dispose();
        return;
      }
      // 等待 duration > 0，确保媒体已加载到可以 seek 的程度
      if (activePlayer.durationNotifier.value <= Duration.zero) {
        final completer = Completer<void>();
        void listener() {
          if (activePlayer.durationNotifier.value > Duration.zero && !completer.isCompleted) {
            completer.complete();
            activePlayer.durationNotifier.removeListener(listener);
          }
        }
        activePlayer.durationNotifier.addListener(listener);
        // 10秒超时保护，避免永远卡住
        await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
          if (!completer.isCompleted) {
            activePlayer.durationNotifier.removeListener(listener);
            completer.complete();
          }
        });
      }
      // 监听视频尺寸，动态调整宽高比
      _widthListener = () => _updateAspectRatio(activePlayer);
      _heightListener = () => _updateAspectRatio(activePlayer);
      activePlayer.videoWidthNotifier.addListener(_widthListener!);
      activePlayer.videoHeightNotifier.addListener(_heightListener!);
      // 立即检查一次（可能已有值）
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
        await player!.dispose();
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

    // 寻找当前集数中速度最快的非当前线路
    if (_sources.isEmpty) return;
    final currentEpisode = _sources[_selectedSource].sourceName;
    final currentUrl = _sources[_selectedSource].url;

    final candidates = _sources
        .where((s) =>
            s.sourceName == currentEpisode &&
            s.usable &&
            s.url != currentUrl &&
            s.speedMs != null &&
            s.speedMs! < 999999)
        .toList()
      ..sort((a, b) => (a.speedMs ?? 999999).compareTo(b.speedMs ?? 999999));

    if (candidates.isNotEmpty) {
      final fallback = candidates.first;
      final idx = _sources.indexOf(fallback);
      debugPrint('PLAYER: buffering watchdog — auto-switch to ${fallback.name} (${fallback.speedMs}ms)');
      _lastAutoSwitchMs = now;
      _switchSource(idx);
    }
  }

  /// Re-enter 时根据保存的集数名 + 线路名选择播放源（三级优先级）
  void _applySavedEpisodeSelection() {
    if (_savedEpisodeName == null || _savedEpisodeName!.isEmpty) return;
    var matched = false;
    // 优先级1: 精确匹配 — 同集数名 + 同线路名 + 可用
    if (_savedLineName != null && _savedLineName!.isNotEmpty) {
      final exactIdx = _sources.indexWhere((s) =>
          s.sourceName == _savedEpisodeName &&
          s.name == _savedLineName &&
          s.usable &&
          s.speedMs != null &&
          s.speedMs! < 999999);
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
        if (_sources[i].sourceName == _savedEpisodeName && _sources[i].usable &&
            _sources[i].speedMs != null && _sources[i].speedMs! < 999999) {
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
          s.name == fastestLineName && s.sourceName == _savedEpisodeName && s.usable);
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

  Future<void> _runSpeedTest() async {
    _client = http.Client();
    _testedCount = 0;
    // delayBetweenTests 已废弃——测速改为并行后不再需要串行延迟

    // 收集唯一线路，re-enter 时把保存的线路排到第一个
    final uniqueLines = <String>{};
    final indices = <int>[];
    for (var i = 0; i < _sources.length; i++) {
      final lineName = _sources[i].name;
      if (!uniqueLines.contains(lineName)) {
        uniqueLines.add(lineName);
        indices.add(i);
      }
    }

    if (_savedLineName != null && _savedLineName!.isNotEmpty) {
      final savedIdx = indices.indexWhere((i) => _sources[i].name == _savedLineName);
      if (savedIdx > 0) {
        final idx = indices.removeAt(savedIdx);
        indices.insert(0, idx);
      }
    }

    if (mounted && !_disposed) {
      setState(() {
        _indicesToTest = indices;
        _totalLinesToTest = indices.length;
      });
    }

    // 逐条测速 + 延迟间隔
    final hasSavedLine = _savedLineName != null && _savedLineName!.isNotEmpty;
    final nodeBox = Hive.box<NodeSpeedRecord>('node_speeds');
    final now = DateTime.now().millisecondsSinceEpoch;
    final ttlMs = 12 * 60 * 60 * 1000; // 12 hours

    // 1. 全局第一遍：全部过一遍缓存
    for (var i = 0; i < indices.length; i++) {
      final idx = indices[i];
      final url = _sources[idx].url;
      final uri = Uri.tryParse(url);
      final domain = uri?.host ?? '';
      if (domain.isNotEmpty) {
        final record = nodeBox.get(domain);
        if (record != null && (now - record.testedAtEpoch) < ttlMs) {
          if (record.latencyMs < 500) {
            _sources[idx].speedMs = record.latencyMs;
            _sources[idx].usable = true;
            debugPrint('SPEED: [$idx] CACHE HIT ${record.latencyMs}ms for $domain');
          } else if (record.latencyMs >= 999999) {
            _sources[idx].speedMs = 999999;
            _sources[idx].usable = false;
            debugPrint('SPEED: [$idx] CACHE BLACKLISTED (timeout) for $domain');
          }
        }
      }
    }

    // 2. 找到最快缓存记录 (Champion) 并复测
    if (!_playerInitialized) {
      int? bestCachedIdx;
      int minLatency = 999999;
      
      // 优先看记忆保存的线路是否命中缓存
      if (hasSavedLine) {
        final savedIdx = indices.indexWhere((i) => _sources[i].name == _savedLineName);
        if (savedIdx != -1 && _sources[savedIdx].speedMs != null && _sources[savedIdx].speedMs! < 500) {
          bestCachedIdx = savedIdx;
          minLatency = _sources[savedIdx].speedMs!;
        }
      }
      
      // 寻找全局最快缓存线路
      if (bestCachedIdx == null) {
        for (final idx in indices) {
          final speed = _sources[idx].speedMs;
          if (speed != null && speed < 500 && speed < minLatency) {
            minLatency = speed;
            bestCachedIdx = idx;
          }
        }
      }

      // 复测 Champion
      if (bestCachedIdx != null) {
        debugPrint('PLAYER: Champion line found (idx $bestCachedIdx, cached ${minLatency}ms) — re-testing...');
        _sources[bestCachedIdx].speedMs = null; // Clear to force _testSource
        if (_client != null) await _testSource(bestCachedIdx, _client!);
        
        if (!_disposed && _sources[bestCachedIdx].usable && _sources[bestCachedIdx].speedMs != null && _sources[bestCachedIdx].speedMs! < 500) {
          _selectedSource = bestCachedIdx;
          _currentUrl = _sources[bestCachedIdx].url;
          debugPrint('PLAYER: Champion re-test passed (${_sources[bestCachedIdx].speedMs}ms) — init immediately');
          if (mounted) setState(() { _stage = LoadingStage.initPlayer; });
          await _initPlayer();
          if (_disposed) return;
        } else {
          debugPrint('PLAYER: Champion re-test failed, falling back to slow testing.');
        }
      }
    }

    // 3. 剩余未命中的线路，并行测速（每条线路独立 http.Client 以支持并发）
    final pending = indices.where((idx) => _sources[idx].speedMs == null).toList();
    if (pending.isNotEmpty && !_disposed && !_abortSpeedTest) {
      // 为每条线路创建独立 Client，避免单个 Client 的并发限制
      await Future.wait(pending.map((idx) async {
        if (_disposed || _abortSpeedTest) return;
        final localClient = http.Client();
        try {
          await _testSource(idx, localClient);
        } finally {
          localClient.close();
        }
        if (_disposed || _abortSpeedTest) return;
        if (mounted) setState(() => _testedCount++);

        if (!_playerInitialized) {
          final passes = _sources[idx].usable &&
              _sources[idx].speedMs != null &&
              _sources[idx].speedMs! < 500;
          if (passes) {
            if (hasSavedLine) {
              if (_sources[idx].name == _savedLineName) {
                _selectedSource = idx;
                _currentUrl = _sources[idx].url;
                debugPrint('PLAYER: saved line fast — init immediately');
                if (mounted) setState(() { _stage = LoadingStage.initPlayer; });
                await _initPlayer();
              }
            } else {
              _selectedSource = idx;
              _currentUrl = _sources[idx].url;
              debugPrint('PLAYER: first fast line — init immediately');
              if (mounted) setState(() { _stage = LoadingStage.initPlayer; });
              await _initPlayer();
            }
          }
        }
      }));
    } else {
      // 全部命中缓存时更新 testedCount
      if (mounted) setState(() => _testedCount = indices.length);
    }

    // 测速完成：将 _disposed / 初始化提前退出检查前置，关闭主 client
    _client?.close();
    _client = null;
    if (_disposed) return;

    final lineSpeeds = <String, int?>{};
    final lineUsable = <String, bool>{};
    for (final idx in _indicesToTest) {
      lineSpeeds[_sources[idx].name] = _sources[idx].speedMs;
      lineUsable[_sources[idx].name] = _sources[idx].usable;
    }
    for (var i = 0; i < _sources.length; i++) {
      if (!_indicesToTest.contains(i)) {
        _sources[i].speedMs = lineSpeeds[_sources[i].name];
        _sources[i].usable = lineUsable[_sources[i].name] ?? true;
      }
    }

    // 更新最快线路索引（仅用于下拉框标记，不自动切换播放源）
    var fastest = _selectedSource;
    var fastestMs = _sources[_selectedSource].speedMs ?? 999999;
    for (var i = 0; i < _sources.length; i++) {
      if (!_sources[i].usable || _sources[i].speedMs == null) continue;
      final ms = _sources[i].speedMs!;
      if (ms < fastestMs) {
        fastest = i;
        fastestMs = ms;
      }
    }
    _fastestIndex = fastest;

    final usable = _sources.where((s) => s.usable && s.speedMs != null).length;
    debugPrint('SPEED: done | tested=$_testedCount usable=$usable');
  }

  Future<void> _testSource(int index, http.Client client) async {
    if (_abortSpeedTest) return;
    final url = _sources[index].url;
    final name = _sources[index].name;
    final sw = Stopwatch()..start();
    
    void recordToCache(int latency) {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.host.isNotEmpty) {
        Hive.box<NodeSpeedRecord>('node_speeds').put(
          uri.host,
          NodeSpeedRecord(domainOrUrl: uri.host, latencyMs: latency, testedAtEpoch: DateTime.now().millisecondsSinceEpoch),
        );
      }
    }

    try {
      final resp = await client.head(Uri.parse(url)).timeout(const Duration(seconds: 4));
      sw.stop();
      final ok = resp.statusCode == 200 || resp.statusCode == 302 || resp.statusCode == 301;
      _sources[index].speedMs = ok ? sw.elapsedMilliseconds : 999999;
      if (!ok) {
        _sources[index].usable = false;
        recordToCache(999999);
        debugPrint('SPEED: [$index] $name HEAD=${resp.statusCode} ❌ (Blacklisted)');
        return;
      }
      // 8KB 足以判断是否为视频流，减少移动端流量消耗（原 64KB）
      final getResp = await client.get(Uri.parse(url), headers: {'Range': 'bytes=0-8191'}).timeout(const Duration(seconds: 5));
      final body = getResp.bodyBytes;
      final isVideo = body.length > 100 && (getResp.statusCode == 200 || getResp.statusCode == 206) && !_looksLikeHtml(body);
      _sources[index].usable = isVideo;
      
      if (isVideo) {
        if (sw.elapsedMilliseconds < 500) {
          recordToCache(sw.elapsedMilliseconds);
        }
      } else {
        _sources[index].speedMs = 999999;
        recordToCache(999999);
      }
      
      debugPrint('SPEED: [$index] $name ${sw.elapsedMilliseconds}ms ${getResp.statusCode} ${body.length}B ${isVideo ? "✅" : "❌HTML"}');
    } catch (e) {
      sw.stop();
      _sources[index].speedMs = 999999;
      _sources[index].usable = false;
      recordToCache(999999);
      debugPrint('SPEED: [$index] $name ERROR: $e (Blacklisted)');
    }
  }

  bool _looksLikeHtml(List<int> bytes) {
    final head = String.fromCharCodes(bytes.take(200));
    return head.contains('<html') || head.contains('<HTML') || head.contains('<!DOCTYPE');
  }

  void _switchSource(int index) {
    // Save progress before switching
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

  String get _selectedLineName => _sources.isNotEmpty ? _sources[_selectedSource].name : '';

  int? _lineSpeed(String lineName) {
    final idx = _sources.indexWhere((s) => s.name == lineName);
    return idx != -1 ? _sources[idx].speedMs : null;
  }

  bool _isLineUsable(String lineName) {
    final idx = _sources.indexWhere((s) => s.name == lineName);
    return idx != -1 ? _sources[idx].usable : true;
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

  void _switchLine(String newLineName) {
    if (newLineName == _selectedLineName) return;
    
    final currentEpisodeName = _sources[_selectedSource].sourceName;
    int targetIdx = -1;
    for (var i = 0; i < _sources.length; i++) {
      if (_sources[i].name == newLineName && _sources[i].sourceName == currentEpisodeName) {
        targetIdx = i;
        break;
      }
    }
    
    if (targetIdx == -1) {
      targetIdx = _sources.indexWhere((s) => s.name == newLineName);
    }
    
    if (targetIdx != -1) {
      _switchSource(targetIdx);
    }
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
    final currentEpisode = _sources[_selectedSource].sourceName;
    final currentUrl = _sources[_selectedSource].url;
    
    // Find all usable sources for the same episode
    final candidates = _sources.where((s) => s.sourceName == currentEpisode && s.usable).toList();
    if (candidates.isEmpty) return null;
    
    // Avoid main stream: If there are multiple lines, strictly exclude the one currently playing
    if (candidates.length > 1) {
      candidates.removeWhere((s) => s.url == currentUrl);
    }
    
    // Sort by speedMs (null/timeout goes to bottom)
    candidates.sort((a, b) => (a.speedMs ?? 999999).compareTo(b.speedMs ?? 999999));
    
    // Return the fastest backup line's URL (or the main line if it's the only one available)
    return candidates.first.url;
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
                  previewUrl: _getFastPreviewUrl(),
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
                          // Resume from last saved position (only seek after play starts, buffer needs to be active)
                          if (_savedPositionMs != null && _savedPositionMs! > 5000) {
                            _player?.seek(Duration(milliseconds: _savedPositionMs!));
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
                    child: GridView.builder(
                      controller: scrollController,
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 1.6,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: epIndices.length,
                      itemBuilder: (context, index) {
                        final sourceIdx = epIndices[index];
                        final s = _sources[sourceIdx];
                        final active = sourceIdx == _selectedSource;

                        return _EpisodeButton(
                          label: s.sourceName,
                          active: active,
                          onTap: () {
                            _switchSource(sourceIdx);
                            Navigator.pop(context);
                          },
                        );
                      },
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
                          _speedDot(_sources.isNotEmpty ? _sources[_selectedSource].speedMs : null),
                          const SizedBox(width: 6),
                          Text(
                            '1080P ${_sources[_selectedSource].name}',
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
                    '1080P',
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
              LayoutBuilder(
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
                      final active = sourceIdx == _selectedSource;

                      return _EpisodeButton(
                        label: s.sourceName,
                        active: active,
                        onTap: () => _switchSource(sourceIdx),
                      );
                    },
                  );
                },
              ),
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
    final lines = _uniqueLineNames;
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
                          child: Text(
                            name,
                            style: TextStyle(
                              color: active ? Colors.white : Colors.white.withOpacity(0.85),
                              fontSize: 14,
                              fontWeight: active ? FontWeight.bold : FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _speedLabel(speed),
                          style: TextStyle(
                            color: active ? Colors.white70 : _speedColor(speed),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
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
  final bool active;
  final VoidCallback onTap;

  const _EpisodeButton({
    required this.label,
    required this.active,
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
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
          alignment: Alignment.center,
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active
                  ? Colors.white
                  : (_hovered ? Colors.white : Colors.white60),
              fontSize: 12,
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
            ),
          ),
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
