// lib/pages/category_filter_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/mubu_api_client.dart';
import '../api/mubu_constants.dart';
import '../models/mubu_models.dart';
import '../widgets/movie_info_dialog.dart';
import '../widgets/movie_card.dart';
import '../widgets/movie_sliver_grid.dart';
import 'player_page.dart';

import '../api/mubu_ui_adapt.dart';

const _kPrimaryRed = Color(0xFFE50914);
const _kBackground = Color(0xFF070708);
const _kCardBg = Color(0xFF121215);
const _kGlassPanel = Color(0xFF16161A);
const _kBorder = Color(0x0DFFFFFF);
const _kChipInactive = Color(0x0DFFFFFF);
const _kChipHover = Color(0x1AFFFFFF);

class CategoryFilterPage extends StatefulWidget {
  final int? initialCategoryId;

  const CategoryFilterPage({
    super.key,
    this.initialCategoryId,
  });

  @override
  State<CategoryFilterPage> createState() => _CategoryFilterPageState();
}

class _CategoryFilterPageState extends State<CategoryFilterPage> {
  final _api = MubuApiClient.instance;
  final _scrollController = ScrollController();

  List<CategoryItem> _categories = [];
  int? _activeCategoryId;

  List<FilterGroup> _filterGroups = [];
  List<VideoItem> _videos = [];

  // Populated dynamically from API filter groups; seed with common keys.
  final Map<String, String> _selectedFilters = {
    'type': '',
    'area': '',
    'year': '',
    'sort': '',
  };

  bool _loadingFilters = true;
  bool _loadingVideos = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  static const int _pageSize = 15;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loadingFilters = true;
      _error = null;
    });

    try {
      final cats = await _api.getHomeCategorys();
      if (!mounted) return;
      // Filter out '推荐' (Recommend) and 'Netflix' categories since they are homepage promo boards, not filterable大类
      _categories = cats.where((c) => 
        c.name != '推荐' && c.id != 88 && 
        c.name.toLowerCase() != 'netflix' && c.id != 99
      ).toList();
      if (_categories.isNotEmpty) {
        final hasInitial = widget.initialCategoryId != null &&
            _categories.any((c) => c.id == widget.initialCategoryId);
        _activeCategoryId = hasInitial ? widget.initialCategoryId : _categories.first.id;
      }
      await _loadFiltersAndVideos();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载分类列表失败: $e';
        _loadingFilters = false;
      });
    }
  }

  Future<void> _loadFiltersAndVideos() async {
    if (_activeCategoryId == null) return;
    setState(() {
      _loadingFilters = true;
      _error = null;
    });

    try {
      final filters = await _api.getFilterOptions(_activeCategoryId!);
      if (!mounted) return;
      setState(() {
        _filterGroups = filters;
        _loadingFilters = false;
        
        // Initialize default selected filters from loaded API filter groups.
        // Dynamically register any keys the API returns (handles non-standard
        // keys like 'category_id' from 短剧/纪录片 categories).
        for (final group in filters) {
          if (group.items.isNotEmpty) {
            _selectedFilters[group.key] = group.items.first.id;
          } else {
            _selectedFilters.putIfAbsent(group.key, () => '');
          }
        }
      });
      await _loadVideos(reset: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载筛选选项失败: $e';
        _loadingFilters = false;
      });
    }
  }

  Future<void> _loadVideos({bool reset = false}) async {
    if (_activeCategoryId == null || _loadingVideos) return;

    int targetPage = reset ? 1 : _page + 1;

    setState(() {
      _loadingVideos = true;
      _error = null;
      if (reset) {
        _videos = [];
        _hasMore = true;
        _page = 1;
      }
    });

    try {
      String typeVal = '';
      String areaVal = '';
      String yearVal = '';
      String sortVal = '';

      _selectedFilters.forEach((k, v) {
        final lowerK = k.toLowerCase();
        if (lowerK == 'type' || lowerK.contains('cate') || lowerK.contains('type')) {
          typeVal = v;
        } else if (lowerK == 'area' || lowerK.contains('area') || lowerK.contains('region')) {
          areaVal = v;
        } else if (lowerK == 'year' || lowerK.contains('year')) {
          yearVal = v;
        } else if (lowerK == 'sort' || lowerK.contains('sort') || lowerK.contains('order')) {
          sortVal = v;
        }
      });

      final newVideos = await _api.getFilteredVideos(
        fcatePid: _activeCategoryId!,
        type: typeVal,
        area: areaVal,
        year: yearVal,
        sort: sortVal,
        page: targetPage,
      );
      if (!mounted) return;

      if (reset && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }

      setState(() {
        if (reset) {
          _videos = newVideos;
        } else {
          _videos.addAll(newVideos);
        }
        _page = targetPage;
        _hasMore = newVideos.length >= _pageSize;
        _loadingVideos = false;
      });
    } catch (e) {
      debugPrint('FILTER: Failed to load videos: $e');
      if (!mounted) return;
      setState(() {
        _loadingVideos = false;
        _error = '加载视频列表失败: $e';
      });
    }
  }

  void _onFilterSelected(String key, String val) {
    if (_selectedFilters[key] == val) return;
    setState(() {
      _selectedFilters[key] = val;
    });
    _loadVideos(reset: true);
  }

  void _changeCategory(int categoryId) {
    if (_activeCategoryId == categoryId) return;
    setState(() {
      _activeCategoryId = categoryId;
      _selectedFilters.forEach((key, value) {
        _selectedFilters[key] = '';
      });
    });
    _loadFiltersAndVideos();
  }

  void _playVideo(VideoItem video) {
    debugPrint('FILTER: click video | id=${video.id} title="${video.title}"');
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
      builder: (_) => const Center(child: CircularProgressIndicator(color: _kPrimaryRed)),
    );
    try {
      final detail = await _api.getVideoDetail(video.id, isShort: _activeCategoryId == 67 || video.category == '短剧' || video.coverPath.contains('short'));
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



  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _buildCategorySelector(),
        if (_loadingFilters)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: _kPrimaryRed),
            ),
          )
        else if (_error != null && _videos.isEmpty)
          Expanded(child: _buildErrorWidget())
        else
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(child: _buildFilterPanel()),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  sliver: _buildVideosGrid(),
                ),
                SliverToBoxAdapter(child: _buildFooter()),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCategorySelector() {
    if (_categories.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = cat.id == _activeCategoryId;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              label: Text(
                cat.name,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  _changeCategory(cat.id);
                }
              },
              selectedColor: _kPrimaryRed,
              backgroundColor: _kGlassPanel,
              side: BorderSide(
                color: isSelected ? _kPrimaryRed : Colors.white.withOpacity(0.08),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterPanel() {
    if (_filterGroups.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: _kGlassPanel.withOpacity(0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorder),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Column(
              children: List.generate(_filterGroups.length, (i) {
                final isLast = i == _filterGroups.length - 1;
                return Column(
                  children: [
                    _buildFilterRow(_filterGroups[i]),
                    if (!isLast)
                      Divider(
                        color: Colors.white.withOpacity(0.05),
                        height: 1,
                        thickness: 1,
                      ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterRow(FilterGroup group) {
    final selectedId = _selectedFilters[group.key] ?? '';

    // Map API key to a human-readable label.
    // Some categories (短剧, 纪录片) return non-standard keys like
    // 'category_id' instead of 'type', so we match with contains() too.
    final k = group.key.toLowerCase();
    String label;
    if (k == 'type' || k.contains('cate') || k.contains('type')) {
      label = '频道';
    } else if (k == 'area' || k.contains('area') || k.contains('region')) {
      label = '地区';
    } else if (k == 'year' || k.contains('year')) {
      label = '年份';
    } else if (k == 'sort' || k.contains('sort') || k.contains('order')) {
      label = '排序';
    } else {
      label = '筛选';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: group.items.map((item) {
                  final isSelected = item.id == selectedId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterChip(
                      label: item.name,
                      isSelected: isSelected,
                      onTap: () => _onFilterSelected(group.key, item.id),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideosGrid() {
    if (_videos.isEmpty && !_loadingVideos) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 80),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.movie_creation_outlined, size: 52, color: Colors.white24),
                SizedBox(height: 14),
                Text(
                  '没有找到符合条件的视频',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MovieSliverGrid(
      videos: _videos,
      onPlay: _playVideo,
      onInfo: _showVideoInfo,
    );
  }

  Widget _buildFooter() {
    if (_loadingVideos) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: CircularProgressIndicator(color: _kPrimaryRed),
        ),
      );
    }

    if (!_hasMore && _videos.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            MubuConstants.reachedBottomWithCount(_videos.length),
            style: const TextStyle(color: Colors.white30, fontSize: 13, letterSpacing: 0.5),
          ),
        ),
      );
    }

    if (_videos.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 20),
        child: Center(
          child: _LoadMoreButton(
            onTap: () => _loadVideos(reset: false),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: Colors.white38),
          const SizedBox(height: 16),
          Text(_error ?? '出错了', style: const TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _loadInitialData(),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimaryRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('重试', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isSelected
        ? _kPrimaryRed
        : _hovered
            ? _kChipHover
            : _kChipInactive;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isSelected ? Colors.white : Colors.white60,
              fontSize: 12.5,
              fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}


class _LoadMoreButton extends StatefulWidget {
  final VoidCallback onTap;
  const _LoadMoreButton({required this.onTap});

  @override
  State<_LoadMoreButton> createState() => _LoadMoreButtonState();
}

class _LoadMoreButtonState extends State<_LoadMoreButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 13),
              decoration: BoxDecoration(
                color: _hovered ? _kPrimaryRed : _kGlassPanel.withOpacity(0.8),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _hovered ? _kPrimaryRed : Colors.white.withOpacity(0.08),
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: _kPrimaryRed.withOpacity(0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: _hovered ? Colors.white : Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    MubuConstants.loadMore,
                    style: TextStyle(
                      color: _hovered ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
