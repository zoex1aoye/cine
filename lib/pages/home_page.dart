import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import '../api/mubu_api_client.dart';
import '../api/mubu_storage.dart';
import '../models/mubu_models.dart';
import '../widgets/movie_info_dialog.dart';
import '../widgets/movie_card.dart';
import '../widgets/movie_sliver_grid.dart';
import '../widgets/mubu_error_widget.dart';
import 'player_page.dart';
import 'category_filter_page.dart';
import 'search_page.dart';
import 'tag_videos_page.dart';

import '../api/mubu_ui_adapt.dart';
import '../api/mubu_constants.dart';
import '../widgets/load_more_button.dart';

// ─── Design Tokens ───────────────────────────────────────────
const Color kRed = Color(0xFFE50914);
const Color kBg = Color(0xFF070708);
const Color kSurface = Color(0xFF0A0A0C);
const Color kCard = Color(0xFF121215);
const Color kGlass = Color(0xFF16161A);

// ─── Root Page ───────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _api = MubuApiClient.instance;

  // Initialization lock
  bool _isInitializing = false;

  // Data
  List<CategoryItem> _categories = [];
  bool _loadingCategories = true;
  TabController? _tabController;
  bool _isLoadingVideoInfo = false;
  String? _error;

  // Bookmarks & History lists
  List<VideoItem> _bookmarksList = [];
  List<VideoItem> _historyList = [];

  // Bookmarks pagination
  static const int _pageSize = 20;
  int _bookmarkPage = 1;
  bool _bookmarkHasMore = false;
  bool _bookmarkLoadingMore = false;
  final _bookmarkScrollController = ScrollController();

  // History pagination
  int _historyPage = 1;
  bool _historyHasMore = false;
  bool _historyLoadingMore = false;
  final _historyScrollController = ScrollController();

  // Unified Navigation State
  // 0 = 首页/热门, 1 = 发现/多维筛选, 2 = 收藏夹, 3 = 历史
  int _currentTabIndex = 0;
  int? _filterCategoryId;
  int? _selectedHomeCategoryId;

  @override
  void initState() {
    super.initState();
    _bookmarkScrollController.addListener(_onBookmarkScroll);
    _historyScrollController.addListener(_onHistoryScroll);
    _initAndLoad();
    _loadBookmarksAndHistory();
  }

  void _onBookmarkScroll() {
    if (!_bookmarkScrollController.hasClients) return;
    final maxScroll = _bookmarkScrollController.position.maxScrollExtent;
    final currentScroll = _bookmarkScrollController.position.pixels;
    if (maxScroll - currentScroll <= 200) _loadMoreBookmarks();
  }

  void _onHistoryScroll() {
    if (!_historyScrollController.hasClients) return;
    final maxScroll = _historyScrollController.position.maxScrollExtent;
    final currentScroll = _historyScrollController.position.pixels;
    if (maxScroll - currentScroll <= 200) _loadMoreHistory();
  }

  @override
  void dispose() {
    _bookmarkScrollController.removeListener(_onBookmarkScroll);
    _historyScrollController.removeListener(_onHistoryScroll);
    _bookmarkScrollController.dispose();
    _historyScrollController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    if (_isInitializing) return;
    _isInitializing = true;
    setState(() {
      _loadingCategories = true;
      _error = null;
    });
    try {
      await _api.init();
      if (!mounted) return;
      final cats = await _api.getHomeCategorys();
      if (!mounted) return;
      _categories = cats;
      
      if (cats.isNotEmpty) {
        _tabController?.dispose();
        _tabController = TabController(length: cats.length, vsync: this);
        _tabController!.addListener(() {
          if (!_tabController!.indexIsChanging) {
            final targetId = cats[_tabController!.index].id;
            if (_selectedHomeCategoryId != targetId) {
              if (mounted) {
                setState(() {
                  _selectedHomeCategoryId = targetId;
                });
              }
            }
          }
        });
        
        final navCats = MubuConstants.filterNavigableCategories(cats);
        _filterCategoryId = navCats.isNotEmpty ? navCats.first.id : cats.first.id;
        _selectedHomeCategoryId = cats.first.id;
      }
      
      if (mounted) {
        setState(() {
          _loadingCategories = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loadingCategories = false;
        });
      }
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _loadBookmarksAndHistory() async {
    final results = await Future.wait([
      MubuStorage.getBookmarks(),
      MubuStorage.getHistory(),
    ]);
    final b = results[0];
    final h = results[1];
    if (mounted) {
      setState(() {
        _bookmarksList = b;
        _historyList = h;
        _bookmarkPage = 1;
        _bookmarkHasMore = b.length > _pageSize;
        _bookmarkLoadingMore = false;
        _historyPage = 1;
        _historyHasMore = h.length > _pageSize;
        _historyLoadingMore = false;
      });
    }
  }

  /// Client-side pagination: returns items for the current page
  List<VideoItem> _paginatedList(List<VideoItem> fullList, int page) {
    final end = page * _pageSize;
    if (end >= fullList.length) return fullList;
    return fullList.sublist(0, end);
  }

  Future<void> _loadMoreBookmarks() async {
    if (_bookmarkLoadingMore || !_bookmarkHasMore) return;
    setState(() => _bookmarkLoadingMore = true);
    if (!mounted) return;
    setState(() {
      _bookmarkPage++;
      _bookmarkHasMore = _bookmarkPage * _pageSize < _bookmarksList.length;
      _bookmarkLoadingMore = false;
    });
  }

  Future<void> _loadMoreHistory() async {
    if (_historyLoadingMore || !_historyHasMore) return;
    setState(() => _historyLoadingMore = true);
    if (!mounted) return;
    setState(() {
      _historyPage++;
      _historyHasMore = _historyPage * _pageSize < _historyList.length;
      _historyLoadingMore = false;
    });
  }

  void _playVideo(VideoItem video) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(video: video),
      ),
    ).then((_) => _loadBookmarksAndHistory());
  }

  void _showInfoError(BuildContext ctx, String title) {
    showDialog(
      context: ctx,
      builder: (ctx) => _InfoErrorDialog(title: title),
    );
  }

  void _showVideoInfo(VideoItem video) async {
    if (_isLoadingVideoInfo) return;
    setState(() {
      _isLoadingVideoInfo = true;
    });

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const Center(child: CircularProgressIndicator(color: kRed));
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
        ).then((_) => _loadBookmarksAndHistory());
      } else {
        if (context.mounted) {
          _showInfoError(context, video.title);
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (dialogContext != null) {
        Navigator.of(dialogContext!).pop();
        dialogContext = null;
      }
      if (context.mounted) {
        _showInfoError(context, video.title);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingVideoInfo = false;
        });
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isDesktop = w >= 800;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        left: !isLandscape,
        right: !isLandscape,
        top: true,
        bottom: !isLandscape,
        child: Column(
          children: [
            if (isDesktop)
              _TopBar(
                onNavTap: (i) {
                  setState(() {
                    _currentTabIndex = i;
                  });
                },
                onSearch: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage()));
                },
              ),
            Expanded(
            child: Row(
              children: [
                if (isDesktop)
                  _LeftNavRail(
                    categories: _categories,
                    currentTabIndex: _currentTabIndex,
                    selectedHomeCategoryId: _selectedHomeCategoryId,
                    isLoading: _loadingCategories,
                    onCategoryTap: (cat) {
                      final idx = _categories.indexWhere((c) => c.id == cat.id);
                      if (idx != -1 && _tabController != null) {
                        _tabController!.animateTo(idx);
                      }
                      setState(() {
                        _currentTabIndex = 0;
                        _selectedHomeCategoryId = cat.id;
                      });
                    },
                    onFilterTap: () {
                      if (_currentTabIndex == 1) return;
                      setState(() {
                        _currentTabIndex = 1;
                      });
                    },
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _currentTabIndex,
                    children: [
                      _buildMainContent(), // 0: Home/Hot
                      CategoryFilterPage(
                        key: ValueKey(_filterCategoryId),
                        initialCategoryId: _filterCategoryId,
                        preloadedCategories: MubuConstants.filterNavigableCategories(_categories),
                      ), // 1: Discover
                      _buildBookmarksView(), // 2: Bookmarks
                      _buildHistoryView(), // 3: History
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
      bottomNavigationBar: isDesktop
          ? null
          : BottomNavigationBar(
              currentIndex: _currentTabIndex >= 2 ? _currentTabIndex + 1 : _currentTabIndex,
              onTap: (i) {
                if (i == 2) {
                  // Search button in the middle
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage()));
                  return;
                }
                final adjustedIndex = i > 2 ? i - 1 : i;
                setState(() {
                  _currentTabIndex = adjustedIndex;
                });
              },
              backgroundColor: kSurface,
              selectedItemColor: kRed,
              unselectedItemColor: Colors.white30,
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
                BottomNavigationBarItem(icon: Icon(Icons.tune), label: '筛选'),
                BottomNavigationBarItem(icon: Icon(Icons.search), label: '搜索'),
                BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: '收藏'),
                BottomNavigationBarItem(icon: Icon(Icons.history), label: '历史'),
              ],
            ),
    );
  }

  Widget _buildMainContent() {
    if (_loadingCategories || _error != null) {
      return _MubuSplashScreen(
        error: _error,
        onRetry: _initAndLoad,
      );
    }
    if (_categories.isEmpty) {
      return const Center(child: Text('没有分类数据', style: TextStyle(color: Colors.white54)));
    }
    if (_tabController == null || _tabController!.length != _categories.length) {
      return const Center(child: CircularProgressIndicator(color: kRed));
    }

    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Stack(
      children: [
        TabBarView(
          controller: _tabController,
          children: _categories.asMap().entries.map((entry) {
            final idx = entry.key;
            final cat = entry.value;
            return CategoryContentView(
              category: cat,
              api: _api,
              onPlay: _playVideo,
              onInfo: _showVideoInfo,
              hasTopPadding: !isDesktop,
              tabController: _tabController!,
              index: idx,
            );
          }).toList(),
        ),
        if (!isDesktop)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  height: 48,
                  width: double.infinity,
                  color: kBg.withOpacity(0.7),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    physics: const BouncingScrollPhysics(),
                    indicatorColor: kRed,
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white30,
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    unselectedLabelStyle: const TextStyle(fontSize: 14),
                    tabAlignment: TabAlignment.start,
                    tabs: _categories.map((cat) {
                      final isHot = cat.name == '推荐' || cat.id == 88;
                      final label = isHot ? '热门' : cat.name;
                      return Tab(text: label);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBookmarksView() {
    if (_bookmarksList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_outline, size: 52, color: Colors.white24),
            const SizedBox(height: 14),
            const Text('暂无收藏影片', style: TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      );
    }
    return CustomScrollView(
      controller: _bookmarkScrollController,
      slivers: [
        SliverAppBar(
          pinned: true,
          automaticallyImplyLeading: false,
          backgroundColor: kBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Text(
                  '我的收藏',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const SizedBox(
                  width: 100,
                  height: 40,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          sliver: MovieSliverGrid(
            videos: _paginatedList(_bookmarksList, _bookmarkPage),
            onPlay: _playVideo,
            onInfo: _showVideoInfo,
            onDelete: (video) async {
              await MubuStorage.toggleBookmark(video);
              await _loadBookmarksAndHistory();
            },
            showSubtitle: false,
          ),
        ),
        if (_bookmarkLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: kRed, strokeWidth: 2),
                ),
              ),
            ),
          )
        else if (_bookmarkHasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: LoadMoreButton(onTap: _loadMoreBookmarks)),
            ),
          )
        else if (_bookmarksList.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  MubuConstants.reachedBottomWithCount(_bookmarksList.length),
                  style: const TextStyle(color: Colors.white24, fontSize: 13),
                ),
              ),
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }

  Widget _buildHistoryView() {
    if (_historyList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 52, color: Colors.white24),
            const SizedBox(height: 14),
            const Text('暂无播放历史', style: TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      );
    }
    return CustomScrollView(
      controller: _historyScrollController,
      slivers: [
        SliverAppBar(
          pinned: true,
          automaticallyImplyLeading: false,
          backgroundColor: kBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Text(
                  '播放历史',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                SizedBox(
                  width: 100,
                  height: 40,
                  child: TextButton.icon(
                    onPressed: () async {
                      await MubuStorage.clearHistory();
                      await _loadBookmarksAndHistory();
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerRight,
                    ),
                    icon: const Icon(Icons.delete_sweep, color: kRed, size: 18),
                    label: const Text('清空', style: TextStyle(color: kRed, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          sliver: MovieSliverGrid(
            videos: _paginatedList(_historyList, _historyPage),
            onPlay: _playVideo,
            onInfo: _showVideoInfo,
            onDelete: (video) async {
              await MubuStorage.deleteHistoryItem(video.id);
              await _loadBookmarksAndHistory();
            },
            showSubtitle: false,
          ),
        ),
        if (_historyLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: kRed, strokeWidth: 2),
                ),
              ),
            ),
          )
        else if (_historyHasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: LoadMoreButton(onTap: _loadMoreHistory)),
            ),
          )
        else if (_historyList.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  MubuConstants.reachedBottomWithCount(_historyList.length),
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

// ─── TOP BAR (Glass AppBar) ───────────────────────────────────
class _TopBar extends StatelessWidget {
  final ValueChanged<int> onNavTap;
  final VoidCallback onSearch;

  const _TopBar({
    required this.onNavTap,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: kGlass.withOpacity(0.8),
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              _buildLogo(),
              const Spacer(),

              if (w >= 600)
                _buildSearchBar()
              else
                IconButton(
                  onPressed: onSearch,
                  icon: Icon(Icons.search, color: Colors.white.withOpacity(0.6), size: 22),
                ),

              const SizedBox(width: 16),
              _buildAvatar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: const Text(
            '幕布',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: 4,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'CINE',
          style: TextStyle(
            color: Colors.white.withOpacity(0.3),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onSearch,
        child: Container(
          width: 280,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '搜索电影、电视剧、动漫...',
                  style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 13),
                ),
              ),
              Icon(Icons.search, size: 16, color: Colors.white.withOpacity(0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: Colors.white.withOpacity(0.05),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: PopupMenuButton<int>(
        tooltip: '用户菜单',
        offset: const Offset(0, 48), // Float below the navbar
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        color: kGlass.withOpacity(0.95),
        elevation: 8,
        onSelected: (index) {
          onNavTap(index);
        },
        itemBuilder: (ctx) {
          return [
            const PopupMenuItem<int>(
              value: 2,
              height: 38,
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.bookmark_outline_rounded, size: 16, color: Colors.white70),
                  SizedBox(width: 8),
                  Text(
                    '收藏夹',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuItem<int>(
              value: 3,
              height: 38,
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 16, color: Colors.white70),
                  SizedBox(width: 8),
                  Text(
                    '历史记录',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2A2A2E),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Icon(Icons.person, size: 16, color: Colors.white.withOpacity(0.5)),
              ),
              if (MediaQuery.sizeOf(context).width >= 800) ...[
                const SizedBox(width: 8),
                Text(
                  '用户',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 16, color: Colors.white.withOpacity(0.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── LEFT NAV RAIL ───────────────────────────────────────────
class _LeftNavRail extends StatefulWidget {
  final List<CategoryItem> categories;
  final int currentTabIndex;
  final int? selectedHomeCategoryId;
  final ValueChanged<CategoryItem> onCategoryTap;
  final VoidCallback onFilterTap;
  final bool isLoading;

  const _LeftNavRail({
    required this.categories,
    required this.currentTabIndex,
    required this.selectedHomeCategoryId,
    required this.onCategoryTap,
    required this.onFilterTap,
    required this.isLoading,
  });

  @override
  State<_LeftNavRail> createState() => _LeftNavRailState();
}

class _LeftNavRailState extends State<_LeftNavRail> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isLoading) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _LeftNavRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading != oldWidget.isLoading) {
      if (widget.isLoading) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _getCategoryIcon(String name) {
    if (name.contains('推荐') || name.contains('热门')) {
      return Icons.local_fire_department_rounded;
    } else if (name.contains('电影')) {
      return Icons.movie_creation_outlined;
    } else if (name.contains('电视剧')) {
      return Icons.tv_rounded;
    } else if (name.contains('短剧')) {
      return Icons.video_library_outlined;
    } else if (name.contains('动漫')) {
      return Icons.auto_awesome_rounded;
    } else if (name.contains('综艺')) {
      return Icons.theater_comedy_rounded;
    } else if (name.contains('纪录片')) {
      return Icons.public_rounded;
    } else if (name.toLowerCase().contains('netflix')) {
      return Icons.video_collection_rounded;
    }
    return Icons.movie_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: kSurface,
        border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            if (widget.isLoading)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: 0.25 + 0.45 * _controller.value,
                    child: Column(
                      children: List.generate(8, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            width: 64,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.04),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: 32,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.04),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                },
              )
            else
              ...widget.categories.map((cat) {
                final isHot = cat.name == '推荐' || cat.id == 88;
                final label = isHot ? '热门' : cat.name;
                final icon = _getCategoryIcon(cat.name);
                final active = widget.currentTabIndex == 0 && widget.selectedHomeCategoryId == cat.id;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _railBtn(icon, label, active, () => widget.onCategoryTap(cat)),
                );
              }),

            // Filter item
            _railBtn(
              Icons.tune,
              '筛选',
              widget.currentTabIndex == 1,
              widget.onFilterTap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _railBtn(IconData icon, String label, bool active, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? Colors.white.withOpacity(0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: active ? kRed.withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: active ? kRed : Colors.white.withOpacity(0.4),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? kRed : Colors.white.withOpacity(0.4),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── HERO BANNER ─────────────────────────────────────────────
class _HeroBanner extends StatefulWidget {
  final TagItem tag;
  final VideoItem video;
  final String imgDomain;
  final ValueChanged<VideoItem> onPlay;
  final ValueChanged<VideoItem> onInfo;

  const _HeroBanner({
    required this.tag,
    required this.video,
    required this.imgDomain,
    required this.onPlay,
    required this.onInfo,
  });

  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  bool _playHovered = false;
  bool _infoHovered = false;
  VideoDetail? _detail;
  bool _loadingDetail = false;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  @override
  void didUpdateWidget(_HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id) {
      _fetchDetail();
    }
  }

  Future<void> _fetchDetail() async {
    if (!mounted) return;
    setState(() {
      _loadingDetail = true;
      _detail = null;
    });
    try {
      final detail = await MubuApiClient.instance.getVideoDetail(
        widget.video.id,
        isShort: widget.video.isShortDrama,
      );
      if (mounted) {
        setState(() {
          _detail = detail;
          _loadingDetail = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingDetail = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isSmall = w < 600;
    // Netflix 风格：移动端短标签，大屏完整标签
    final playLabel = isSmall ? '播放' : '立即播放';
    final playMinW = isSmall ? 120.0 : UIAdapt.px(context, 150);
    return Container(
      height: isSmall ? 260 : UIAdapt.px(context, 420),
      margin: const EdgeInsets.only(bottom: 8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.video.hasCover)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: MediaQuery.of(context).size.width * 0.6,
              child: CachedNetworkImage(
                imageUrl: widget.video.coverUrl(widget.imgDomain),
                fit: BoxFit.cover,
                color: Colors.white.withOpacity(0.5),
                colorBlendMode: BlendMode.modulate,
                placeholder: (_, __) => Container(color: Colors.black38),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [kBg, kBg, Colors.transparent],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [kBg, Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            left: isSmall ? 16.0 : UIAdapt.px(context, 40),
            bottom: isSmall ? 16.0 : UIAdapt.px(context, 40),
            right: isSmall ? 16.0 : UIAdapt.px(context, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: UIAdapt.px(context, 8),
                    vertical: UIAdapt.px(context, 3),
                  ),
                  decoration: BoxDecoration(
                    color: kRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: kRed.withOpacity(0.3), width: 1),
                  ),
                  child: Text(
                    widget.tag.name,
                    style: TextStyle(
                      color: kRed,
                      fontSize: UIAdapt.fontSize(context, 10),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                SizedBox(height: UIAdapt.px(context, 16)),
                Text(
                  widget.video.title,
                  maxLines: isSmall ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isSmall ? 20 : UIAdapt.fontSize(context, 36),
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                SizedBox(height: UIAdapt.px(context, 10)),
                Row(
                  children: [
                    if (widget.video.score.isNotEmpty) ...[
                      Icon(Icons.star, color: Colors.amber, size: UIAdapt.px(context, 14)),
                      SizedBox(width: UIAdapt.px(context, 4)),
                      Text(
                        widget.video.score,
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: UIAdapt.fontSize(context, 13),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: UIAdapt.px(context, 16)),
                    ],
                    if (widget.video.year.isNotEmpty)
                      Text(
                        widget.video.year,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: UIAdapt.fontSize(context, 13),
                        ),
                      ),
                  ],
                ),
                if (_detail != null && _detail!.description.isNotEmpty) ...[
                  SizedBox(height: UIAdapt.px(context, 12)),
                  SizedBox(
                    width: isSmall ? double.infinity : MediaQuery.of(context).size.width * 0.5,
                    child: Text(
                      _detail!.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: UIAdapt.fontSize(context, 14),
                        height: 1.5,
                      ),
                    ),
                  ),
                  SizedBox(height: UIAdapt.px(context, 20)),
                ] else if (_loadingDetail) ...[
                  SizedBox(height: UIAdapt.px(context, 12)),
                  Container(
                    width: isSmall ? double.infinity : MediaQuery.of(context).size.width * 0.35,
                    height: UIAdapt.px(context, 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  SizedBox(height: UIAdapt.px(context, 4)),
                  Container(
                    width: isSmall ? double.infinity : MediaQuery.of(context).size.width * 0.25,
                    height: UIAdapt.px(context, 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  SizedBox(height: UIAdapt.px(context, 20)),
                ] else ...[
                  SizedBox(height: UIAdapt.px(context, 24)),
                ],
                // Netflix 风格：播放按钮宽而突出，详情按钮紧凑低调
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Play Button
                    MouseRegion(
                      onEnter: (_) => setState(() => _playHovered = true),
                      onExit: (_) => setState(() => _playHovered = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        transform: _playHovered
                            ? (Matrix4.identity()..translate(0.0, -UIAdapt.px(context, 2.0)))
                            : Matrix4.identity(),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(isSmall ? 8 : 12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE50914).withOpacity(_playHovered ? 0.5 : 0.35),
                              blurRadius: UIAdapt.px(context, _playHovered ? 20 : 12),
                              spreadRadius: 1,
                              offset: Offset(0, UIAdapt.px(context, _playHovered ? 6 : 4)),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: () => widget.onPlay(widget.video),
                          icon: Icon(Icons.play_circle_fill_rounded, size: UIAdapt.px(context, 20)),
                          label: Text(
                            playLabel,
                            style: TextStyle(
                              fontSize: UIAdapt.fontSize(context, 14),
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: Size(playMinW, UIAdapt.px(context, 48)),
                            padding: isSmall
                                ? EdgeInsets.symmetric(horizontal: UIAdapt.px(context, 20))
                                : EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(isSmall ? 8 : 12),
                            ),
                          ).copyWith(
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.hovered)) {
                                return const Color(0xFFF40F1D);
                              }
                              return const Color(0xFFE50914);
                            }),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: UIAdapt.px(context, 12)),
                    // Detail Icon Button (Netflix 风格 ℹ️ 纯图标)
                    MouseRegion(
                      onEnter: (_) => setState(() => _infoHovered = true),
                      onExit: (_) => setState(() => _infoHovered = false),
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => widget.onInfo(widget.video),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          transform: _infoHovered
                              ? (Matrix4.identity()..scale(1.1))
                              : Matrix4.identity(),
                          width: UIAdapt.px(context, 28),
                          height: UIAdapt.px(context, 28),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(_infoHovered ? 0.08 : 0.02),
                            border: Border.all(
                              color: Colors.white.withOpacity(_infoHovered ? 0.15 : 0.05),
                            ),
                          ),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: UIAdapt.px(context, 16),
                            color: Colors.white.withOpacity(_infoHovered ? 0.75 : 0.45),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── TAG SECTION (Stateful with Lazy Loading) ──────────────────
class _TagSection extends StatefulWidget {
  final TagItem tag;
  final String imgDomain;
  final ValueChanged<VideoItem> onPlay;
  final ValueChanged<VideoItem> onInfo;
  final VoidCallback onSeeAll;
  final List<VideoItem>? initialVideos;

  const _TagSection({
    Key? key,
    required this.tag,
    required this.imgDomain,
    required this.onPlay,
    required this.onInfo,
    required this.onSeeAll,
    this.initialVideos,
  }) : super(key: key);

  @override
  State<_TagSection> createState() => _TagSectionState();
}

class _TagSectionState extends State<_TagSection> {
  List<VideoItem> _videos = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialVideos != null) {
      _videos = widget.initialVideos!;
    } else {
      _loadVideos();
    }
  }

  Future<void> _loadVideos() async {
    if (mounted) setState(() => _loading = true);
    try {
      final vids = await MubuApiClient.instance.getTagVideos(
        widget.tag.id,
        tpl: widget.tag.template,
        count: 12,
      );
      if (mounted) {
        setState(() {
          _videos = vids;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildSkeletonLoader();
    }
    if (_error != null || _videos.isEmpty) {
      return const SizedBox.shrink(); // Hide failed/empty tags quietly
    }

    final w = MediaQuery.of(context).size.width;
    final contentWidth = w - 48.0;
    final cols = MovieSliverGrid.calculateColumns(contentWidth);

    final displayVideos = _videos.take(cols).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.tag.name,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton(
                onPressed: widget.onSeeAll,
                child: Row(
                  children: [
                    Text('查看全部', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
                    Icon(Icons.chevron_right, size: 16, color: Colors.white.withOpacity(0.4)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (ctx, constraints) {
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: displayVideos.map((v) {
                  final cardWidth = (constraints.maxWidth - (cols - 1) * 14) / cols;
                  return SizedBox(
                    width: cardWidth,
                    child: MovieCard(
                      video: v,
                      imgDomain: widget.imgDomain,
                      onPlay: () => widget.onPlay(v),
                      onInfo: () => widget.onInfo(v),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          const _SkeletonGrid(),
        ],
      ),
    );
  }
}

// pulsing skeleton shimmer effect widget
class _SkeletonGrid extends StatefulWidget {
  const _SkeletonGrid({Key? key}) : super(key: key);

  @override
  State<_SkeletonGrid> createState() => _SkeletonGridState();
}

class _SkeletonGridState extends State<_SkeletonGrid> with SingleTickerProviderStateMixin {
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
          opacity: 0.25 + 0.45 * _controller.value,
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final cols = MovieSliverGrid.calculateColumns(constraints.maxWidth);
              final cardWidth = (constraints.maxWidth - (cols - 1) * 14) / cols;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: List.generate(cols, (index) {
                  return SizedBox(
                    width: cardWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 11,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: cardWidth * 0.7,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: cardWidth * 0.4,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              );
            },
          ),
        );
      },
    );
  }
}

// ─── CATEGORY CONTENT VIEW ────────────────────────────────────
class CategoryContentView extends StatefulWidget {
  final CategoryItem category;
  final MubuApiClient api;
  final ValueChanged<VideoItem> onPlay;
  final ValueChanged<VideoItem> onInfo;
  final bool hasTopPadding;
  final TabController tabController;
  final int index;

  const CategoryContentView({
    super.key,
    required this.category,
    required this.api,
    required this.onPlay,
    required this.onInfo,
    required this.hasTopPadding,
    required this.tabController,
    required this.index,
  });

  @override
  State<CategoryContentView> createState() => _CategoryContentViewState();
}

class _CategoryContentViewState extends State<CategoryContentView> with AutomaticKeepAliveClientMixin {
  List<TagItem> _tags = [];
  Map<int, List<VideoItem>> _tagVideos = {};
  bool _loading = true;
  String? _error;
  int _currentLoadSession = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_onTabChanged);
    // Only load immediately if this tab is the active one
    if (widget.tabController.index == widget.index) {
      _loadContent();
    } else {
      // Not active: show progress indicator or skeleton without hitting network yet
      _loading = false;
    }
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.tabController.index == widget.index && _tags.isEmpty && !_loading && _error == null) {
      _loadContent();
    }
  }

  Future<void> _loadContent() async {
    if (!mounted) return;
    final session = ++_currentLoadSession;
    setState(() {
      _loading = true;
      _error = null;
      _tags = [];
      _tagVideos = {};
    });
    try {
      final tags = await widget.api.getHomeTags(widget.category.id);
      if (!mounted || session != _currentLoadSession) return;
      
      setState(() {
        _tags = tags;
      });
      
      if (tags.isNotEmpty) {
        final firstTag = tags.first;
        final firstVids = await widget.api.getTagVideos(firstTag.id, tpl: firstTag.template, count: 12);
        if (!mounted || session != _currentLoadSession) return;
        setState(() {
          _tagVideos[firstTag.id] = firstVids;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted || session != _currentLoadSession) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // If we haven't loaded anything yet because we were lazy-loaded (and are now the active tab),
    // we trigger the load. Just a fallback safety check.
    if (widget.tabController.index == widget.index && _tags.isEmpty && !_loading && _error == null) {
      // Defer state mutation to next frame to avoid build phase setState crashes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadContent();
      });
    }

    if (_loading && _tags.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: kRed));
    }
    
    if (_error != null && _tags.isEmpty) {
      return MubuErrorWidget(
        title: '加载失败',
        error: _error!,
        onRetry: _loadContent,
      );
    }

    if (_tags.isEmpty && !_loading) {
      // Lazy load hasn't triggered yet or empty category
      return const Center(child: CircularProgressIndicator(color: kRed));
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        if (widget.hasTopPadding)
          const SliverPadding(padding: EdgeInsets.only(top: 60)),
        
        // Hero banner
        if (_tags.isNotEmpty && (_tagVideos[_tags.first.id]?.isNotEmpty ?? false))
          SliverToBoxAdapter(
            child: _HeroBanner(
              tag: _tags.first,
              video: _tagVideos[_tags.first.id]!.first,
              imgDomain: widget.api.imgDomain,
              onPlay: widget.onPlay,
              onInfo: widget.onInfo,
            ),
          ),

        // Tag sections
        for (final tag in _tags)
          SliverToBoxAdapter(
            child: _TagSection(
              tag: tag,
              imgDomain: widget.api.imgDomain,
              onPlay: widget.onPlay,
              onInfo: widget.onInfo,
              initialVideos: _tagVideos[tag.id],
              onSeeAll: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TagVideosPage(tag: tag),
                  ),
                );
              },
            ),
          ),

        const SliverPadding(padding: EdgeInsets.only(bottom: 60)),
      ],
    );
  }
}

// ─── INFO ERROR DIALOG ────────────────────────────────────────
class _InfoErrorDialog extends StatelessWidget {
  final String title;
  const _InfoErrorDialog({required this.title});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      title: const Text('加载失败', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      content: Text('无法获取影片 "$title" 的详细信息，请稍后重试。', style: const TextStyle(color: Colors.white70, fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('确定', style: TextStyle(color: kRed)),
        ),
      ],
    );
  }
}

// ─── CUSTOM BEAUTIFUL SPLASH SCREEN ───────────────────────────
class _MubuSplashScreen extends StatefulWidget {
  final String? error;
  final VoidCallback? onRetry;

  const _MubuSplashScreen({
    this.error,
    this.onRetry,
  });

  @override
  State<_MubuSplashScreen> createState() => _MubuSplashScreenState();
}

class _MubuSplashScreenState extends State<_MubuSplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();
  }

  @override
  void didUpdateWidget(_MubuSplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.error != oldWidget.error) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          // Ambient back glow
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Color(0x15E50914), // subtle red glow
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: child,
                  ),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo container
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                      boxShadow: [
                        BoxShadow(
                          color: kRed.withOpacity(0.08),
                          blurRadius: 24,
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: const Text(
                      '幕布',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 32,
                        letterSpacing: 8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'CINE',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 48),
                  if (!hasError) ...[
                    // Custom glowing loading bar
                    SizedBox(
                      width: 160,
                      height: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: const LinearProgressIndicator(
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(kRed),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Error Container
                    MubuErrorWidget(
                      title: '加载失败',
                      error: widget.error!,
                      onRetry: widget.onRetry!,
                      isCard: true,
                      iconSize: 40,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


