import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/mubu_models.dart';
import '../api/mubu_ui_adapt.dart';
import '../utils/platform_utils.dart';
import 'mubu_button.dart';

class MovieCard extends StatefulWidget {
  final VideoItem video;
  final String imgDomain;
  final VoidCallback onPlay;
  final VoidCallback onInfo;
  final double? buttonSize;
  final VoidCallback? onDelete;
  final bool? showSubtitle;

  const MovieCard({
    super.key,
    required this.video,
    required this.imgDomain,
    required this.onPlay,
    required this.onInfo,
    this.buttonSize,
    this.onDelete,
    this.showSubtitle,
  });

  @override
  State<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<MovieCard> {
  static const Color _kRed = Color(0xFFE50914);
  static const Color _kCardBg = Color(0xFF121215);

  bool _hovered = false;

  /// Only show hover buttons on desktop platforms
  bool get _isDesktop => isDesktopPlatform;

  @override
  Widget build(BuildContext context) {
    final hasScore = widget.video.score.isNotEmpty && widget.video.score != '0';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPlay,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          transform: _hovered
              ? (Matrix4.identity()..scale(1.05)..translate(0.0, -8.0))
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? _kRed.withOpacity(0.5) : Colors.white.withOpacity(0.05),
              width: _hovered ? 1.5 : 1.0,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: _kRed.withOpacity(0.12),
                      blurRadius: 24,
                      spreadRadius: 1,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.75),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // AspectRatio forces a strictly uniform aspect ratio for all images
                AspectRatio(
                  aspectRatio: 16 / 11,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.imgDomain.isEmpty
                          ? Container(
                              color: const Color(0xFF1A1A1E),
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _kRed,
                                  ),
                                ),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: widget.video.coverUrl(widget.imgDomain),
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: const Color(0xFF1A1A1E),
                                child: const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _kRed,
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (_, url, error) => Container(
                                color: const Color(0xFF1A1A1E),
                                child: Icon(
                                  Icons.movie,
                                  color: Colors.white.withOpacity(0.1),
                                  size: 32,
                                ),
                              ),
                            ),
                      
                      // Rating score badge
                      if (hasScore)
                        Positioned(
                          // On mobile with delete: place left to avoid overlap with the top-right delete button
                          top: 8,
                          left: (widget.onDelete != null && !_isDesktop) ? 8 : null,
                          right: (widget.onDelete != null && !_isDesktop) ? null : 8,
                          child: AnimatedOpacity(
                            // Hide on desktop hover (delete button appears), always visible on mobile
                            opacity: (widget.onDelete != null && _hovered && _isDesktop) ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 250),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.video.score,
                                style: const TextStyle(
                                  color: _kRed,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Play progress bar
                      if (widget.video.lastPositionMs != null &&
                          widget.video.lastDurationMs != null &&
                          widget.video.lastDurationMs! > 0 &&
                          widget.video.lastPositionMs! > 0)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: AnimatedOpacity(
                            opacity: _hovered ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 250),
                            child: Container(
                              height: 3,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(1.5),
                                child: LinearProgressIndicator(
                                  value: (widget.video.lastPositionMs! / widget.video.lastDurationMs!).clamp(0.0, 1.0),
                                  backgroundColor: Colors.white.withOpacity(0.15),
                                  valueColor: const AlwaysStoppedAnimation<Color>(_kRed),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Hover overlay – play, info, and delete buttons sharing the same plane
                      // Only render on desktop/web to avoid invisible-but-tappable buttons on mobile
                      if (_isDesktop)
                        AnimatedOpacity(
                          opacity: _hovered ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                            ),
                            child: Stack(
                              children: [
                                // Play & Info buttons centered
                                Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      MubuButton(
                                        icon: Icons.play_arrow_rounded,
                                        type: MubuButtonType.primary,
                                        onPressed: widget.onPlay,
                                        customHeight: widget.buttonSize ?? UIAdapt.px(context, widget.onDelete != null ? 36 : 44),
                                      ),
                                      SizedBox(width: UIAdapt.px(context, widget.onDelete != null ? 14 : 20)),
                                      MubuButton(
                                        icon: Icons.info_outline_rounded,
                                        type: MubuButtonType.icon,
                                        onPressed: widget.onInfo,
                                        customHeight: widget.buttonSize ?? UIAdapt.px(context, widget.onDelete != null ? 36 : 44),
                                      ),
                                    ],
                                  ),
                                ),
                                // Delete button in the top-right corner
                                if (widget.onDelete != null)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: MubuButton(
                                      icon: Icons.delete_outline_rounded,
                                      type: MubuButtonType.icon, // Using icon variant for subtle glassmorphism delete
                                      onPressed: () {
                                        widget.onDelete!();
                                      },
                                      customHeight: 28,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      // Mobile: always-visible delete button (no hover needed)
                      if (!_isDesktop && widget.onDelete != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: MubuButton(
                            icon: Icons.delete_outline_rounded,
                            type: MubuButtonType.icon,
                            onPressed: () {
                              widget.onDelete!();
                            },
                            customHeight: 28,
                          ),
                        ),
                    ],
                  ),
                ),
                
                // 底部文字详情区
                Builder(
                  builder: (context) {
                    // 动态合成副标题：若包含年份或类型则用中间点拼接；若均为空则返回空字符串
                    final showSubtitle = widget.showSubtitle ?? (widget.onDelete == null);
                    final subtitle = showSubtitle
                        ? [
                            if (widget.video.year.isNotEmpty) widget.video.year,
                            if (widget.video.category.isNotEmpty) widget.video.category
                          ].join(' • ')
                        : '';
                    final hasSubtitle = subtitle.isNotEmpty;
                    return SizedBox(
                      height: hasSubtitle ? 52 : 40, // 无副标题时压缩底部高度
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center, // 开启垂直居中排列
                          children: [
                            Text(
                              widget.video.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            // 关键优化：若副标题(年份与分类)为空，则完全不渲染副标题组件与间距。
                            // 此时 Column 只有一个子项 Title，并在垂直方向上被 `mainAxisAlignment.center` 自动居中。
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.3),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
