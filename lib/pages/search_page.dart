import 'dart:ui';
import 'package:flutter/material.dart';
import '../api/mubu_api_client.dart';
import '../api/mubu_constants.dart';
import '../models/mubu_models.dart';
import '../widgets/movie_sliver_grid.dart';
import '../widgets/movie_info_dialog.dart';
import '../widgets/mubu_dialog.dart';
import 'player_page.dart';

import '../widgets/load_more_button.dart';
import '../widgets/mubu_error_widget.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  // ── Design tokens ──────────────────────────────────────────────────────
  static const _primaryRed  = Color(0xFFE50914);
  static const _bgColor     = Color(0xFF070708);
  static const _glassBg     = Color(0xFF16161A);
  static final _borderColor = Colors.white.withOpacity(0.05);

  // ── State ──────────────────────────────────────────────────────────────
  final _api = MubuApiClient.instance;
  final _ctrl = TextEditingController();
  final _scrollController = ScrollController();

  List<VideoItem> _results = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  int _currentPage = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= 200) {
      _loadMore();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ── Search Action ──────────────────────────────────────────────────────
  Future<void> _search() async {
    final kw = _ctrl.text.trim();
    if (kw.isEmpty) return;

    setState(() {
      _loading = true;
      _searched = true;
      _error = null;
      _results = [];
      _currentPage = 1;
      _hasMore = false;
      _loadingMore = false;
    });

    try {
      final result = await _api.search(kw, page: 1);
      if (!mounted) return;
      setState(() {
        _results = result.videos;
        _hasMore = _results.length < result.total;
        _loading = false;
      });
    } catch (e) {
      debugPrint('SEARCH: Failed to search | keyword: $kw | error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '搜索失败，请重试';
      });
    }
  }

  void _playVideo(VideoItem video) {
    debugPrint('SEARCH: play video | id=${video.id} title="${video.title}"');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(video: video),
      ),
    );
  }

  void _showVideoInfo(VideoItem video) async {
    BuildContext? dialogContext;
    MubuDialog.showCustom(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const Center(child: CircularProgressIndicator(color: _primaryRed));
      },
    );
    try {
      final detail = await _api.getVideoDetail(video.id, isShort: video.isShortDrama);
      if (!mounted) return;
      if (dialogContext != null) {
        Navigator.of(dialogContext!).pop();
        dialogContext = null;
      }
      if (detail != null) {
        MubuDialog.showCustom(
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
      if (dialogContext != null) {
        Navigator.of(dialogContext!).pop();
        dialogContext = null;
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
    });
    final kw = _ctrl.text.trim();
    final nextPage = _currentPage + 1;
    try {
      final result = await _api.search(kw, page: nextPage);
      if (!mounted) return;
      setState(() {
        _currentPage = nextPage;
        _results.addAll(result.videos);
        _hasMore = _results.length < result.total;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('SEARCH: Failed to load more | error: $e');
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
      });
    }
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
            _buildTopSearchBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ── Top Search Bar (Glass) ─────────────────────────────────────────────
  Widget _buildTopSearchBar() {
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
            children: [
              // Back Button
              _glassIconButton(Icons.arrow_back_ios_new, onTap: () => Navigator.pop(context)),
              const SizedBox(width: 16),
              // Search Input
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 16, right: 10),
                        child: Icon(Icons.search, color: Colors.white38, size: 20),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          autofocus: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.2,
                          ),
                          textAlignVertical: TextAlignVertical.center,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _search(),
                          decoration: InputDecoration(
                            hintText: '搜索影片、导演、演员...',
                            hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (_ctrl.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                            onPressed: () {
                              setState(() {
                                _ctrl.clear();
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Search Button
              _searchButton(),
            ],
          ),
        ),
      ),
    );
  }

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
            border: Border.all(color: _borderColor),
          ),
          child: Icon(icon, color: Colors.white70, size: 18),
        ),
      ),
    );
  }

  Widget _searchButton() {
    return GestureDetector(
      onTap: _search,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: _primaryRed,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33E50914),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Text(
            '搜索',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────
  Widget _buildBody() {
    // Initial State: Not searched yet
    if (!_searched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_outlined, size: 64, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 16),
            Text(
              '发现精彩影片',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '输入您想寻找的影片名称或关键字',
              style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Loading State
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _primaryRed, strokeWidth: 2.5),
      );
    }

    // Error State
    if (_error != null) {
      return MubuErrorWidget(
        error: _error!,
        buttonText: '重新搜索',
        onRetry: _search,
        iconSize: 52,
      );
    }

    // Empty Results State
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sentiment_dissatisfied_outlined, size: 56, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 16),
            Text(
              '抱歉，未找到相关影片',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              '试着换个词搜搜看吧',
              style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12),
            ),
          ],
        ),
      );
    }

    // Search Results Grid
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              '为您找到 ${_results.length} 部影片',
              style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: MovieSliverGrid(
            videos: _results,
            onPlay: _playVideo,
            onInfo: _showVideoInfo,
          ),
        ),
        // Bottom actions: loading / load more / end
        if (_loadingMore)
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
        else if (_hasMore && _results.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: LoadMoreButton(onTap: _loadMore)),
            ),
          )
        else if (!_hasMore && _results.isNotEmpty)
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
    );
  }
}

