// lib/pages/category_filter_page.dart
import 'package:flutter/material.dart';
import '../api/mubu_api_client.dart';
import '../api/mubu_constants.dart';
import '../models/mubu_models.dart';
import '../widgets/movie_info_dialog.dart';
import '../widgets/movie_sliver_grid.dart';
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

  // Track the *display name* for each selected filter key (for active tags)
  final Map<String, String> _selectedFilterLabels = {};

  bool _loadingFilters = true;
  bool _loadingVideos = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

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
    if (maxScroll - currentScroll <= 200) {
      _loadVideos(reset: false);
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
      final cats = await _api.getHomeCategorys();
      if (!mounted) return;
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
      await _loadVideos(reset: true);
      if (!mounted) return;
      setState(() {
        _loadingFilters = false;
      });
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

  void _changeCategory(int categoryId) {
    if (_activeCategoryId == categoryId) return;
    // Don't setState here — _loadFiltersAndVideos handles loading state entirely
    _activeCategoryId = categoryId;
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
    _loadVideos(reset: true);
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
                    final k = entry.key.toLowerCase();
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
          child: LoadMoreButton(onTap: () => _loadVideos(reset: false)),
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

  String _groupLabel(String key) {
    final k = key.toLowerCase();
    if (k == 'type' || k.contains('cate') || k.contains('type')) return '频道';
    if (k == 'area' || k.contains('area') || k.contains('region')) return '地区';
    if (k == 'year' || k.contains('year')) return '年份';
    if (k == 'sort' || k.contains('sort') || k.contains('order')) return '排序';
    return '筛选';
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
