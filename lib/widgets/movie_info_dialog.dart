import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/mubu_models.dart';
import '../api/mubu_storage.dart';
import '../api/mubu_api_client.dart';
import '../api/mubu_ui_adapt.dart';
import 'mubu_button.dart';
import 'mubu_dialog.dart';
import 'mubu_skeleton.dart';

class MovieInfoDialog extends StatefulWidget {
  final VideoItem video;
  final String imgDomain;
  final VoidCallback onPlay;
  final bool isShort;
  final VideoDetail? preloadedDetail;

  const MovieInfoDialog({
    Key? key,
    required this.video,
    required this.imgDomain,
    required this.onPlay,
    required this.isShort,
    this.preloadedDetail,
  }) : super(key: key);

  static Future<void> show({
    required BuildContext context,
    required VideoItem video,
    required String imgDomain,
    required bool isShort,
    required VoidCallback onPlay,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.7),
      elevation: 0,
      builder: (ctx) => MovieInfoDialog(
        video: video,
        imgDomain: imgDomain,
        isShort: isShort,
        onPlay: () {
          Navigator.pop(ctx);
          onPlay();
        },
      ),
    );
  }

  @override
  State<MovieInfoDialog> createState() => _MovieInfoDialogState();
}

class _MovieInfoDialogState extends State<MovieInfoDialog> {
  bool _isBookmarked = false;
  VideoDetail? _detail;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _detail = widget.preloadedDetail;
    _checkBookmarkStatus();
    if (_detail == null) {
      _fetchDetail();
    }
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final detail = await MubuApiClient.instance.getVideoDetail(
        widget.video.id, 
        isShort: widget.isShort
      );
      if (mounted) {
        setState(() {
          _detail = detail;
          _isLoading = false;
          _hasError = detail == null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _checkBookmarkStatus() async {
    final ok = await MubuStorage.isBookmarked(widget.video.id);
    if (mounted) {
      setState(() {
        _isBookmarked = ok;
      });
    }
  }

  Future<void> _toggleBookmark() async {
    await MubuStorage.toggleBookmark(widget.video);
    await _checkBookmarkStatus();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 650;
    final coverUrl = widget.video.coverUrl(widget.imgDomain);
    
    Widget posterWidget() {
      if (coverUrl.isEmpty) {
        return Container(
          color: const Color(0xFF1A1A1E),
          child: Center(
            child: Icon(Icons.movie, color: Colors.white24, size: UIAdapt.px(context, 40)),
          ),
        );
      }
      return CachedNetworkImage(
        imageUrl: coverUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: const Color(0xFF1A1A1E)),
        errorWidget: (_, __, ___) => Container(
          color: const Color(0xFF1A1A1E),
          child: Icon(Icons.movie, color: Colors.white24, size: UIAdapt.px(context, 40)),
        ),
      );
    }

    Widget contentWidget() {
      if (_hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white24, size: UIAdapt.px(context, 48)),
              SizedBox(height: UIAdapt.px(context, 16)),
              Text(
                '加载影片详情失败',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: UIAdapt.fontSize(context, 14)),
              ),
              SizedBox(height: UIAdapt.px(context, 24)),
              MubuButton(
                label: '点击重试',
                icon: Icons.refresh_rounded,
                type: MubuButtonType.primary,
                onPressed: _fetchDetail,
              ),
            ],
          ),
        );
      }

      if (_isLoading || _detail == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      MubuSkeleton(width: UIAdapt.px(context, 48), height: UIAdapt.px(context, 18)),
                      SizedBox(width: UIAdapt.px(context, 8)),
                      MubuSkeleton(width: UIAdapt.px(context, 120), height: UIAdapt.px(context, 14)),
                    ],
                  ),
                  SizedBox(height: UIAdapt.px(context, 12)),
                  MubuSkeleton(width: UIAdapt.px(context, 200), height: UIAdapt.px(context, 28)),
                  SizedBox(height: UIAdapt.px(context, 16)),
                  MubuSkeleton(width: double.infinity, height: UIAdapt.px(context, 1)),
                  SizedBox(height: UIAdapt.px(context, 12)),
                  MubuSkeleton(width: UIAdapt.px(context, 48), height: UIAdapt.px(context, 12)),
                  SizedBox(height: UIAdapt.px(context, 8)),
                  MubuSkeleton(width: double.infinity, height: UIAdapt.px(context, 14)),
                  SizedBox(height: UIAdapt.px(context, 6)),
                  MubuSkeleton(width: double.infinity, height: UIAdapt.px(context, 14)),
                  SizedBox(height: UIAdapt.px(context, 6)),
                  MubuSkeleton(width: UIAdapt.px(context, 150), height: UIAdapt.px(context, 14)),
                ],
              ),
            ),
            SizedBox(height: UIAdapt.px(context, 20)),
            Row(
              children: [
                Expanded(flex: 3, child: MubuSkeleton(height: isWide ? UIAdapt.px(context, 48) : UIAdapt.px(context, 40))),
                SizedBox(width: UIAdapt.px(context, isWide ? 12 : 8)),
                Expanded(flex: 2, child: MubuSkeleton(height: isWide ? UIAdapt.px(context, 48) : UIAdapt.px(context, 40))),
              ],
            ),
          ],
        );
      }

      final metaParts = [
        if (_detail!.year.isNotEmpty) _detail!.year,
        if (widget.video.category.isNotEmpty) widget.video.category,
        if (_detail!.score.isNotEmpty) '评分 ${_detail!.score}',
      ].join(' • ');

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tag & Meta Row
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: UIAdapt.px(context, 8),
                        vertical: UIAdapt.px(context, 3),
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFE50914).withOpacity(0.3)),
                      ),
                      child: Text(
                        '影片详情',
                        style: TextStyle(
                          color: const Color(0xFFE50914),
                          fontSize: UIAdapt.fontSize(context, 9),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    SizedBox(width: UIAdapt.px(context, 8)),
                    Expanded(
                      child: Text(
                        metaParts,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: UIAdapt.fontSize(context, 11),
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: UIAdapt.px(context, 12)),
                
                // Title
                Text(
                  _detail!.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: UIAdapt.fontSize(context, 24),
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: UIAdapt.px(context, 16)),

                // Divider and Description
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.only(top: UIAdapt.px(context, 12)),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '剧情简介',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: UIAdapt.fontSize(context, 9),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: UIAdapt.px(context, 6)),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Text(
                      _detail!.description.isNotEmpty ? _detail!.description : '暂无剧情简介。',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: UIAdapt.fontSize(context, 13),
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: UIAdapt.px(context, 20)),

          // Actions row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: MubuButton(
                  label: '开始播放',
                  icon: Icons.play_circle_fill_rounded,
                  type: MubuButtonType.primary,
                  onPressed: widget.onPlay,
                  fullWidth: true,
                  customHeight: isWide ? UIAdapt.px(context, 48) : UIAdapt.px(context, 40),
                ),
              ),
              SizedBox(width: UIAdapt.px(context, isWide ? 12 : 8)),
              Expanded(
                flex: 2,
                child: MubuButton(
                  label: _isBookmarked ? '已收藏' : '收藏',
                  icon: _isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  type: _isBookmarked ? MubuButtonType.primary : MubuButtonType.secondary,
                  onPressed: _toggleBookmark,
                  fullWidth: true,
                  customHeight: isWide ? UIAdapt.px(context, 48) : UIAdapt.px(context, 40),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: MubuDialogContainer(
            maxWidth: UIAdapt.px(context, 620),
            margin: EdgeInsets.symmetric(
              horizontal: UIAdapt.px(context, 20),
              vertical: UIAdapt.px(context, 40),
            ),
            child: SizedBox(
              height: UIAdapt.px(context, isWide ? 380 : 540),
              child: Stack(
                children: [
                  isWide
                      ? Row(
                          children: [
                            // Left Poster
                            SizedBox(
                              width: UIAdapt.px(context, 240),
                              height: double.infinity,
                              child: posterWidget(),
                            ),
                            // Right Content
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.all(UIAdapt.px(context, 28)),
                                child: contentWidget(),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            // Top Poster
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: posterWidget(),
                            ),
                            // Bottom Content
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.all(UIAdapt.px(context, 20)),
                                child: contentWidget(),
                              ),
                            ),
                          ],
                        ),
                  // Top-right close floating button (Keep for desktop/tap access)
                  Positioned(
                    top: UIAdapt.px(context, 14),
                    right: UIAdapt.px(context, 14),
                    child: MubuButton(
                      icon: Icons.close_rounded,
                      type: MubuButtonType.icon,
                      onPressed: () => Navigator.pop(context),
                      customHeight: UIAdapt.px(context, 32),
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
