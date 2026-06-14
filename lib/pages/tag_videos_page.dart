import 'dart:ui';
import 'package:flutter/material.dart';
import '../api/mubu_api_client.dart';
import '../api/mubu_constants.dart';
import '../models/mubu_models.dart';
import '../widgets/movie_sliver_grid.dart';
import '../widgets/movie_info_dialog.dart';
import 'player_page.dart';

import '../widgets/load_more_button.dart';

class TagVideosPage extends StatefulWidget {
  final TagItem tag;

  const TagVideosPage({
    super.key,
    required this.tag,
  });

  @override
  State<TagVideosPage> createState() => _TagVideosPageState();
}

class _TagVideosPageState extends State<TagVideosPage> {
  // ── Design tokens ──────────────────────────────────────────────────────
  static const _primaryRed  = Color(0xFFE50914);
  static const _bgColor     = Color(0xFF070708);
  static const _glassBg     = Color(0xFF16161A);
  static final _borderColor = Colors.white.withOpacity(0.05);

  // ── State ──────────────────────────────────────────────────────────────
  final _api = MubuApiClient.instance;
  final _scrollController = ScrollController();
  final List<VideoItem> _videos = [];

  int _page = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMore();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= 200) {
      _loadMore();
    }
  }

  // ── Data ───────────────────────────────────────────────────────────────
  Future<void> _refresh() async {
    setState(() {
      _videos.clear();
      _page = 1;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final vids = await _api.getTagVideos(
        widget.tag.id,
        tpl: widget.tag.template,
        page: _page,
        count: 30,
      );
      if (!mounted) return;
      setState(() {
        _videos.addAll(vids);
        _page++;
        _isLoading = false;
        if (vids.isEmpty || vids.length < 8) _hasMore = false;
      });
    } catch (e) {
      debugPrint('TAG_VIDEOS: Failed to load | tag: ${widget.tag.name} | page: $_page | error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '加载数据失败';
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────
  void _playVideo(VideoItem video) {
    debugPrint('TAG_VIDEOS: click video | id=${video.id} title="${video.title}"');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(video: video),
      ),
    );
  }

  void _showVideoInfo(VideoItem video) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: _primaryRed)),
    );
    try {
      final detail = await _api.getVideoDetail(video.id, isShort: video.category == '短剧' || video.coverPath.contains('short'));
      if (!mounted) return;
      Navigator.pop(context);
      if (detail != null) {
        showDialog(
          context: context,
          builder: (ctx) => MovieInfoDialog(
            detail: detail,
            video: video,
            imgDomain: _api.imgDomain,
            onPlay: () {
              Navigator.pop(ctx);
              _playVideo(video);
            },
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        left: !isLandscape,
        right: !isLandscape,
        top: true,
        bottom: !isLandscape,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.only(
            top: 12,
            left: 20,
            right: 20,
            bottom: 14,
          ),
          decoration: BoxDecoration(
            color: _glassBg.withOpacity(0.85),
            border: Border(bottom: BorderSide(color: _borderColor)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Back-to-home icon button on the left
              _BackButton(onTap: _goHome),
              const SizedBox(width: 16),
              // Current tag name
              Expanded(
                child: Text(
                  widget.tag.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
}
  // ── Body ───────────────────────────────────────────────────────────────
  Widget _buildBody() {
    // Initial loading
    if (_videos.isEmpty && _isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _primaryRed, strokeWidth: 2.5),
      );
    }

    // Error state (no data yet)
    if (_videos.isEmpty && _error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 52, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.white38, fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refresh,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // Empty state
    if (_videos.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_filter_outlined, size: 52, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 12),
            const Text('暂无相关影片', style: TextStyle(color: Colors.white38, fontSize: 15)),
          ],
        ),
      );
    }

    // Grid with results
    return RefreshIndicator(
      onRefresh: _refresh,
      color: _primaryRed,
      backgroundColor: _glassBg,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Results count
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                '共 ${_videos.length} 部影片',
                style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
              ),
            ),
          ),

          // Video grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: MovieSliverGrid(
              videos: _videos,
              onPlay: _playVideo,
              onInfo: _showVideoInfo,
            ),
          ),

          // Bottom actions: loading / load more / end
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: _primaryRed, strokeWidth: 2),
                  ),
                ),
              ),
            )
          else if (_hasMore && _videos.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: LoadMoreButton(onTap: _loadMore)),
              ),
            )
          else if (!_hasMore && _videos.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    MubuConstants.reachedBottom,
                    style: const TextStyle(color: Colors.white24, fontSize: 13),
                  ),
                ),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
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
          child: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 18),
        ),
      ),
    );
  }
}

