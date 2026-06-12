// lib/pages/player_page.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../api/mubu_api_client.dart';
import '../api/mubu_storage.dart';
import '../models/mubu_models.dart';
import '../player/media_kit_player.dart';
import '../widgets/concentric_hud.dart';
import '../api/mubu_ui_adapt.dart';

enum LoadingStage { fetchingDetail, testingSpeed, initPlayer, ready, error }

class PlayerPage extends StatefulWidget {
  final VideoItem video;

  const PlayerPage({Key? key, required this.video}) : super(key: key);

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
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

  @override
  void initState() {
    super.initState();
    _checkBookmarkStatus();
    _loadAndPrepare();
  }

  Future<void> _checkBookmarkStatus() async {
    final ok = await MubuStorage.isBookmarked(widget.video.id);
    if (mounted && !_disposed) {
      setState(() {
        _isBookmarked = ok;
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
    try {
      final detail = await MubuApiClient.instance.getVideoDetail(widget.video.id, isShort: widget.video.category == '短剧' || widget.video.coverPath.contains('short'));
      if (detail == null || detail.sources.isEmpty) {
        throw Exception('暂无可用播放源');
      }
      _sources = detail.sources;
      _currentUrl = detail.bestUrl ?? '';
      if (mounted) {
        setState(() {
          _stage = LoadingStage.testingSpeed;
        });
      }
      if (_sources.length > 1) {
        await _runSpeedTest();
      }
      if (_disposed) return;
      if (mounted) {
        setState(() {
          _stage = LoadingStage.initPlayer;
        });
      }
      await _initPlayer();
      if (_disposed) return;
      if (mounted) {
        setState(() {
          _stage = LoadingStage.ready;
        });
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

  Future<void> _initPlayer() async {
    try {
      final player = MediaKitPlayerImpl(initialUrl: _currentUrl);
      await player.initialize();
      await player.pause();
      if (_disposed) {
        await player.dispose();
        return;
      }
      if (mounted) {
        setState(() {
          _player = player;
          _playerInitialized = true;
        });
      } else {
        await player.dispose();
      }
    } catch (e) {
      throw Exception('播放器初始化失败: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _client?.close();
    _client = null;
    _player?.dispose();
    super.dispose();
  }

  Future<void> _runSpeedTest() async {
    _client = http.Client();
    _testedCount = 0;
    const maxConcurrency = 5;
    const lowLatencyThreshold = 500;
    const requiredUsableCount = 3;

    final uniqueLines = <String>{};
    final indices = <int>[];
    for (var i = 0; i < _sources.length; i++) {
      final lineName = _sources[i].name;
      if (!uniqueLines.contains(lineName)) {
        uniqueLines.add(lineName);
        indices.add(i);
      }
    }
    
    if (mounted && !_disposed) {
      setState(() {
        _indicesToTest = indices;
        _totalLinesToTest = indices.length;
      });
    }

    var nextToTest = 0;
    var activeCount = 0;
    var stopTesting = false;
    final completer = Completer<void>();

    void runNext() {
      if (_disposed || stopTesting || _client == null || nextToTest >= _indicesToTest.length) {
        if (activeCount == 0 && !completer.isCompleted) {
          completer.complete();
        }
        return;
      }
      final usableLowLatencyLines = _sources.where((s) => s.usable && s.speedMs != null && s.speedMs! < lowLatencyThreshold).length;
      if (usableLowLatencyLines >= requiredUsableCount) {
        stopTesting = true;
        if (activeCount == 0 && !completer.isCompleted) completer.complete();
        return;
      }
      final idx = _indicesToTest[nextToTest++];
      activeCount++;
      _testSource(idx, _client!).then((_) {
        activeCount--;
        if (_disposed) {
          if (activeCount == 0 && !completer.isCompleted) completer.complete();
          return;
        }
        if (mounted) setState(() => _testedCount++);
        runNext();
      }).catchError((_) {
        activeCount--;
        if (_disposed) {
          if (activeCount == 0 && !completer.isCompleted) completer.complete();
          return;
        }
        if (mounted) setState(() => _testedCount++);
        runNext();
      });
    }

    final initialWorkers = maxConcurrency < _indicesToTest.length ? maxConcurrency : _indicesToTest.length;
    for (var i = 0; i < initialWorkers; i++) {
      runNext();
    }
    await completer.future;
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
    final usable = _sources.where((s) => s.usable && s.speedMs != null).length;
    debugPrint('SPEED: done | tested=$_testedCount usable=$usable');

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
    if (_fastestIndex != _selectedSource) {
      _selectedSource = _fastestIndex!;
      _currentUrl = _sources[_fastestIndex!].url;
    }
  }

  Future<void> _testSource(int index, http.Client client) async {
    final url = _sources[index].url;
    final name = _sources[index].name;
    final sw = Stopwatch()..start();
    try {
      final resp = await client.head(Uri.parse(url)).timeout(const Duration(seconds: 4));
      sw.stop();
      final ok = resp.statusCode == 200 || resp.statusCode == 302 || resp.statusCode == 301;
      _sources[index].speedMs = ok ? sw.elapsedMilliseconds : 999999;
      if (!ok) {
        _sources[index].usable = false;
        debugPrint('SPEED: [$index] $name HEAD=${resp.statusCode} ❌');
        return;
      }
      final getResp = await client.get(Uri.parse(url), headers: {'Range': 'bytes=0-65535'}).timeout(const Duration(seconds: 5));
      final body = getResp.bodyBytes;
      final isVideo = body.length > 100 && (getResp.statusCode == 200 || getResp.statusCode == 206) && !_looksLikeHtml(body);
      _sources[index].usable = isVideo;
      debugPrint('SPEED: [$index] $name ${sw.elapsedMilliseconds}ms ${getResp.statusCode} ${body.length}B ${isVideo ? "✅" : "❌HTML"}');
    } catch (e) {
      sw.stop();
      _sources[index].speedMs = 999999;
      _sources[index].usable = false;
      debugPrint('SPEED: [$index] $name ERROR: $e');
    }
  }

  bool _looksLikeHtml(List<int> bytes) {
    final head = String.fromCharCodes(bytes.take(200));
    return head.contains('<html') || head.contains('<HTML') || head.contains('<!DOCTYPE');
  }

  void _switchSource(int index) {
    final src = _sources[index];
    _selectedSource = index;
    _currentUrl = src.url;
    _player?.setSource(_currentUrl);
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
          body: Stack(
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
                                    aspectRatio: 16 / 9,
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
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                                  child: AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: _buildVideoPlayerContainer(),
                                  ),
                                ),
                                _buildMovieInfoAndEpisodes(false),
                              ],
                            ),
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
                  targetAnchor: Alignment.bottomLeft,
                  followerAnchor: Alignment.topLeft,
                  child: _buildLineDropdownCard(),
                ),
            ],
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
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Video Widget
          if (_stage == LoadingStage.ready && _playerInitialized && _player != null && _startPlayRequested)
            Positioned.fill(child: _player!.buildVideoWidget(context)),

          // 2. 播放器封面海报图 (当播放开始后淡出，并使用 IgnorePointer 避免遮挡鼠标/触控事件)
          if (coverUrl.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !showOverlay, // 播放时忽略事件拦截，使得手势能穿透到下层播放器
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 600),
                  opacity: showOverlay ? 1.0 : 0.0,
                  curve: Curves.easeOutCubic,
                  child: CachedNetworkImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
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

          // 4. Overlays: Error view
          if (_stage == LoadingStage.error)
            _buildErrorView(),

          // 5. Overlays: ConcentricHud (only visible while loading)
          if (_stage != LoadingStage.ready)
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
                      _player?.play();
                      MubuStorage.recordWatch(widget.video);
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
                    onTap: () => setState(() => _expanded = !_expanded),
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
                          Icon(
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
          const SizedBox(height: 16),
          
          Divider(color: Colors.white.withOpacity(0.05), height: 1),
          const SizedBox(height: 16),

          Text(
            '剧集列表 (${epIndices.length})',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (epIndices.isEmpty)
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
      ),
    );
  }

  Widget _buildLineDropdownCard() {
    final lines = _uniqueLineNames;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: 280,
          decoration: BoxDecoration(
            color: const Color(0xFF16161A).withOpacity(0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.85),
                blurRadius: 50,
                offset: const Offset(0, 25),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shuffle, color: Colors.white38, size: 15),
                  const SizedBox(width: 8),
                  const Text('切换线路', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = false),
                    child: const Icon(Icons.close, color: Colors.white38, size: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
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
                        setState(() => _expanded = false);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: active ? _primaryRed : Colors.white.withAlpha(10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            _speedDot(speed),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  color: active ? Colors.white : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _speedLabel(speed),
                              style: TextStyle(
                                color: active ? Colors.white70 : _speedColor(speed),
                                fontSize: 10,
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
        ),
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

  Widget _buildErrorView() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: const Color(0xFF101024),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.redAccent.withAlpha(50)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(_errorMessage ?? '播放出错', style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadAndPrepare,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  const BreathingPlayPulse({Key? key, required this.onTap}) : super(key: key);

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
