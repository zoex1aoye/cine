// lib/pages/category_filter_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../api/mubu_api_client.dart';
import '../widgets/hover_close_button.dart';
import '../api/mubu_constants.dart';
import '../models/mubu_models.dart';
import '../widgets/movie_info_dialog.dart';
import '../widgets/movie_sliver_grid.dart';
import '../widgets/mubu_dialog.dart';
import 'player_page.dart';

import '../widgets/load_more_button.dart';

const _kPrimaryRed = Color(0xFFE50914);
const _kBackground = Color(0xFF070708);
const _kGlassPanel = Color(0xFF16161A);
const _kBorder = Color(0x0DFFFFFF);
const _kChipInactive = Color(0x0DFFFFFF);
const _kChipHover = Color(0x1AFFFFFF);

class CategoryFilterPage extends StatefulWidget {
  final int? initialCategoryId;
  /// 可选：由父级预加载的分类列表，传入后跳过 API 请求
  final List<CategoryItem>? preloadedCategories;

  const CategoryFilterPage({
    super.key,
    this.initialCategoryId,
    this.preloadedCategories,
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

  // Track the *display name* for each selected filter key (for active tags)
  final Map<String, String> _selectedFilterLabels = {};

  bool _loadingFilters = true;
  bool _loadingVideos = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;
  int _videoReqId = 0;

  static const int _pageSize = 15;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialData();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= 200 && _hasMore) {
      if (_activeCategoryId != null) {
        _loadVideos(_activeCategoryId!, reset: false);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loadingFilters = true;
      _error = null;
    });

    try {
      // 优先使用父级预加载的分类，避免重复 API 请求
      if (widget.preloadedCategories != null) {
        _categories = widget.preloadedCategories!;
      } else {
        final cats = await _api.getHomeCategorys();
        if (!mounted) return;
        _categories = MubuConstants.filterNavigableCategories(cats);
      }
      if (_categories.isNotEmpty) {
        final hasInitial = widget.initialCategoryId != null &&
            _categories.any((c) => c.id == widget.initialCategoryId);
        _activeCategoryId = hasInitial ? widget.initialCategoryId : _categories.first.id;
      }
      if (_activeCategoryId != null) {
        await _loadFiltersAndVideos(_activeCategoryId!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载分类列表失败: $e';
        _loadingFilters = false;
      });
    }
  }

  Future<void> _loadFiltersAndVideos(int catId) async {
    setState(() {
      _loadingFilters = true;
      _error = null;
    });

    try {
      final filters = await _api.getFilterOptions(catId);
      if (!mounted) return;
      if (catId != _activeCategoryId) return;

      setState(() {
        _filterGroups = filters;
        _selectedFilters.clear();
        _selectedFilterLabels.clear();
        for (final group in filters) {
          if (group.items.isNotEmpty) {
            _selectedFilters[group.key] = group.items.first.id;
            _selectedFilterLabels[group.key] = group.items.first.name;
          } else {
            _selectedFilters.putIfAbsent(group.key, () => '');
          }
        }
      });
      // Keep _loadingFilters true until _loadVideos completes so the build
      // never sees an empty _videos + no-loading state.
      await _loadVideos(catId, reset: true);
      if (!mounted) return;
      if (catId != _activeCategoryId) return;

      setState(() {
        _loadingFilters = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (catId != _activeCategoryId) return;
      setState(() {
        _error = '加载筛选选项失败: $e';
        _loadingFilters = false;
      });
    }
  }

  Future<void> _loadVideos(int catId, {bool reset = false}) async {
    if (_loadingVideos && !reset) return;

    final int reqId = ++_videoReqId;
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
        switch (MubuConstants.classifyFilterKey(k)) {
          case FilterParam.type:
            typeVal = v;
          case FilterParam.area:
            areaVal = v;
          case FilterParam.year:
            yearVal = v;
          case FilterParam.sort:
            sortVal = v;
          case FilterParam.unknown:
            break;
        }
      });

      final newVideos = await _api.getFilteredVideos(
        fcatePid: catId,
        type: typeVal,
        area: areaVal,
        year: yearVal,
        sort: sortVal,
        page: targetPage,
      );
      if (!mounted) return;
      if (reqId != _videoReqId) return;
      if (catId != _activeCategoryId) return;

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
      if (reqId != _videoReqId) return;
      if (catId != _activeCategoryId) return;
      setState(() {
        _loadingVideos = false;
        _error = '加载视频列表失败: $e';
      });
    }
  }

  void _changeCategory(int categoryId) {
    if (_activeCategoryId == categoryId) return;
    // Don't setState here — _loadFiltersAndVideos handles loading state entirely
    _activeCategoryId = categoryId;
    _loadFiltersAndVideos(categoryId);
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

  void _showVideoInfo(VideoItem video) {
    MovieInfoDialog.show(
      context: context,
      video: video,
      isShort: _activeCategoryId == 67 || video.isShortDrama,
      imgDomain: _api.imgDomain,
      onPlay: () => _playVideo(video),
    );
  }

  /// Open picker for a single filter dimension (e.g. just "频道")
  void _openSingleFilterSheet(String groupKey) {
    try {
      final group = _filterGroups.firstWhere((g) => g.key == groupKey);
      final currentId = _selectedFilters[groupKey] ?? '';
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _SingleFilterSheet(
          group: group,
          selectedId: currentId,
          onChanged: (id, name) {
            _applySingleFilter(groupKey, id, name);
          },
          onClose: () => Navigator.pop(ctx),
        ),
      );
    } catch (_) {}
  }

  void _applySingleFilter(String key, String id, String name) {
    setState(() {
      _selectedFilters[key] = id;
      if (name.isNotEmpty) {
        _selectedFilterLabels[key] = name;
      } else {
        _selectedFilterLabels.remove(key);
      }
    });
    if (_activeCategoryId != null) {
      _loadVideos(_activeCategoryId!, reset: true);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _buildCategorySelector(),
        // Sticky filter bar (outside scroll view so it stays pinned)
        _buildFilterBar(),
        Expanded(
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
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

  /// Build the filter bar
  Widget _buildFilterBar() {
    // Show skeleton when filters are loading
    if (_loadingFilters) {
      return _buildFilterBarSkeleton();
    }

    final hasActiveFilters = _selectedFilterLabels.isNotEmpty;

    return Container(
      color: _kBackground,
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Row(
        children: [
          _FilterLabel(),
          if (hasActiveFilters) ...[
            const SizedBox(width: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _selectedFilterLabels.entries.map((entry) {
                    final label = MubuConstants.filterKeyLabel(entry.key);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _ActiveFilterChip(
                        label: '$label: ${entry.value}',
                        onTap: () => _openSingleFilterSheet(entry.key),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
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

  Widget _buildVideosGrid() {
    if (_loadingFilters) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 80),
          child: Center(
            child: CircularProgressIndicator(color: _kPrimaryRed),
          ),
        ),
      );
    }

    if (_error != null && _videos.isEmpty) {
      return SliverToBoxAdapter(child: _buildErrorWidget());
    }

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
    // Don't show footer loading when _loadingFilters is already showing a full-screen spinner
    if (_loadingFilters) return const SizedBox.shrink();

    if (_loadingVideos) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(color: _kPrimaryRed, strokeWidth: 2),
          ),
        ),
      );
    }

    if (!_hasMore && _videos.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            MubuConstants.reachedBottomWithCount(_videos.length),
            style: const TextStyle(color: Colors.white24, fontSize: 13),
          ),
        ),
      );
    }

    if (_videos.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: LoadMoreButton(onTap: () {
            if (_activeCategoryId != null) {
              _loadVideos(_activeCategoryId!, reset: false);
            }
          }),
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

  // ─── Filter Bar Skeleton (loading state) ────────────────────────
  Widget _buildFilterBarSkeleton() {
    return Container(
      color: _kBackground,
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Row(
        children: [
          // Icon skeleton
          Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 6),
          // Text skeleton
          Container(
            width: 28, height: 14,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          // Chip skeletons
          ...List.generate(3, (i) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              width: i == 0 ? 72 : (i == 1 ? 60 : 48),
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          )),
        ],
      ),
    );
  }
}

// ─── Static Filter Label ────────────────────────────────────────
class _FilterLabel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.tune_rounded,
          size: 16,
          color: Colors.white.withOpacity(0.45),
        ),
        const SizedBox(width: 6),
        Text(
          '筛选',
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Active Filter Chip (click to edit) ─────────────────────────
class _ActiveFilterChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _ActiveFilterChip({
    required this.label,
    required this.onTap,
  });

  @override
  State<_ActiveFilterChip> createState() => _ActiveFilterChipState();
}

class _ActiveFilterChipState extends State<_ActiveFilterChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _kPrimaryRed.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _kPrimaryRed.withOpacity(_hovered ? 0.5 : 0.25),
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _kPrimaryRed,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Single Filter Dimension Sheet ──────────────────────────────
class _SingleFilterSheet extends StatefulWidget {
  final FilterGroup group;
  final String selectedId;
  final void Function(String id, String name) onChanged;
  final VoidCallback onClose;

  const _SingleFilterSheet({
    required this.group,
    required this.selectedId,
    required this.onChanged,
    required this.onClose,
  });

  @override
  State<_SingleFilterSheet> createState() => _SingleFilterSheetState();
}

class _SingleFilterSheetState extends State<_SingleFilterSheet> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
  }

  @override
  Widget build(BuildContext context) {
    final label = _groupLabel(widget.group.key);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      margin: const EdgeInsets.only(top: 80),
      decoration: const BoxDecoration(
        color: _kBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06), shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close_rounded, size: 20, color: Colors.white.withOpacity(0.6)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: _kBorder, height: 1, thickness: 1),
          // Options
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: widget.group.items.map((item) {
                  final isSelected = item.id == _selectedId;
                  return _FilterChip(
                    label: item.name,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() => _selectedId = item.id);
                      widget.onChanged(item.id, item.name);
                      widget.onClose();
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _groupLabel(String key) => MubuConstants.filterKeyLabel(key);
}

// ─── Info Error Dialog (when detail API fails) ─────────────────
class _InfoErrorDialog extends StatelessWidget {
  final String title;
  const _InfoErrorDialog({required this.title});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 650;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
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
                    padding: EdgeInsets.all(isMobile ? 24 : 32),
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
                        // Title
                        Text(
                          title,
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
                        // Subtitle
                        Text(
                          '暂时无法获取影片详情\n可能是数据源暂未收录该影片',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: isMobile ? 13 : 15,
                            height: 1.5,
                          ),
                        ),
                        SizedBox(height: isMobile ? 28 : 36),
                        // OK button
                        SizedBox(
                          width: double.infinity,
                          height: isMobile ? 46 : 52,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPrimaryRed,
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
                                return _kPrimaryRed;
                              }),
                            ),
                            child: const Text(
                              '知道了',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
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
    );
  }
}

// ─── Filter Chip (used inside the bottom sheet) ────────────────
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isSelected ? Colors.white : Colors.white60,
              fontSize: 13,
              fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
