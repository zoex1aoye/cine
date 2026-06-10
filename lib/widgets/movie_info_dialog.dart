// lib/widgets/movie_info_dialog.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/mubu_models.dart';
import '../api/mubu_storage.dart';
import '../api/mubu_api_client.dart';
import '../api/mubu_ui_adapt.dart';

class MovieInfoDialog extends StatefulWidget {
  final VideoDetail detail;
  final VideoItem video;
  final String imgDomain;
  final VoidCallback onPlay;

  const MovieInfoDialog({
    Key? key,
    required this.detail,
    required this.video,
    required this.imgDomain,
    required this.onPlay,
  }) : super(key: key);

  @override
  State<MovieInfoDialog> createState() => _MovieInfoDialogState();
}

class _MovieInfoDialogState extends State<MovieInfoDialog> {
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _checkBookmarkStatus();
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
    
    // Construct meta string matching prototype style: 2026 • 动作/科幻 • 评分 8.9
    final metaParts = [
      if (widget.detail.year.isNotEmpty) widget.detail.year,
      if (widget.video.category.isNotEmpty) widget.video.category,
      if (widget.detail.score.isNotEmpty) '评分 ${widget.detail.score}',
    ].join(' • ');

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

    Widget contentColumn() {
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
                  widget.detail.title,
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
                      widget.detail.description.isNotEmpty ? widget.detail.description : '暂无剧情简介。',
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
              // Play Button with Red Glow Shadow
              Expanded(
                flex: 3,
                child: Container(
                  height: UIAdapt.px(context, 48),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE50914).withOpacity(0.35),
                        blurRadius: UIAdapt.px(context, 12),
                        spreadRadius: 1,
                        offset: Offset(0, UIAdapt.px(context, 4)),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: widget.onPlay,
                    icon: Icon(Icons.play_circle_fill_rounded, size: UIAdapt.px(context, 20)),
                    label: Text(
                      '开始播放',
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
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ).copyWith(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.hovered)) {
                          return const Color(0xFFF40F1D); // Lighter red for hover
                        }
                        return const Color(0xFFE50914);
                      }),
                    ),
                  ),
                ),
              ),
              SizedBox(width: UIAdapt.px(context, 12)),
              // Glassmorphic Favorite Button (Rectangular Text + Icon)
              Expanded(
                flex: 2,
                child: Container(
                  height: UIAdapt.px(context, 48),
                  child: ElevatedButton.icon(
                    onPressed: _toggleBookmark,
                    icon: Icon(
                      _isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      size: UIAdapt.px(context, 18),
                    ),
                    label: Text(
                      _isBookmarked ? '已收藏' : '加入收藏',
                      style: TextStyle(
                        fontSize: UIAdapt.fontSize(context, 14),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.05),
                      foregroundColor: _isBookmarked ? const Color(0xFFE50914) : Colors.white.withOpacity(0.8),
                      shadowColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      side: BorderSide(color: Colors.white.withOpacity(0.1)),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ).copyWith(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.hovered)) {
                          return Colors.white.withOpacity(0.12);
                        }
                        return Colors.white.withOpacity(0.05);
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.hovered)) {
                          return _isBookmarked ? const Color(0xFFE50914) : Colors.white;
                        }
                        return _isBookmarked ? const Color(0xFFE50914) : Colors.white.withOpacity(0.8);
                      }),
                      side: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.hovered)) {
                          return BorderSide(color: Colors.white.withOpacity(0.2));
                        }
                        return BorderSide(color: Colors.white.withOpacity(0.1));
                      }),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: UIAdapt.px(context, 20),
        vertical: UIAdapt.px(context, 40),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: UIAdapt.px(context, 620),
            height: UIAdapt.px(context, isWide ? 380 : 540),
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
                              child: contentColumn(),
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
                              child: contentColumn(),
                            ),
                          ),
                        ],
                      ),
                // Top-right close floating button with backdrop blur
                Positioned(
                  top: UIAdapt.px(context, 14),
                  right: UIAdapt.px(context, 14),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Container(
                        color: Colors.black.withOpacity(0.3),
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withOpacity(0.8),
                            size: UIAdapt.px(context, 20),
                          ),
                          hoverColor: Colors.white.withOpacity(0.1),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.all(UIAdapt.px(context, 8)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
