import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/mubu_models.dart';
import '../api/mubu_ui_adapt.dart';
import '../utils/cine_surface.dart';
import '../utils/device_profile.dart';
import '../utils/platform_utils.dart';
import 'failover_cover_image.dart';
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

  /// TV 方向键焦点。与 [_hovered] 分开：触摸屏上系统不会走
  /// `onShowFocusHighlight`，只靠悬停标志画不出红框。
  bool _tvFocused = false;

  /// Only show hover buttons on desktop platforms
  bool get _isDesktop => isDesktopPlatform;

  void _setTvFocused(bool focused) {
    if (_tvFocused == focused) return;
    setState(() => _tvFocused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final hasScore = widget.video.score.isNotEmpty && widget.video.score != '0';
    final dpr = MediaQuery.devicePixelRatioOf(context);

    Widget card = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPlay,
        onLongPress: _isDesktop ? null : widget.onInfo,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          transform:
              _hovered
                  ? (Matrix4.identity()
                    ..scale(1.05)
                    ..translate(0.0, -8.0))
                  : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  _tvFocused
                      ? _kRed
                      : _hovered
                      ? _kRed.withOpacity(0.5)
                      : Colors.white.withOpacity(0.05),
              width: _tvFocused ? 2.5 : (_hovered ? 1.5 : 1.0),
            ),
            boxShadow:
                _hovered
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
            // 单一 2:3 海报面：标题叠在底部 scrim 上（方案 B），无独立实心底栏。
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 只约束宽度。同时给宽高会按 BoxFit.fill 强拉成 2:3。
                  final memW = DeviceProfile.budget.coverDecodeWidth(
                    logicalWidth: constraints.maxWidth,
                    dpr: dpr,
                  );
                  final showSubtitle =
                      widget.showSubtitle ?? (widget.onDelete == null);
                  final lastEp = widget.video.lastEpisodeName?.trim() ?? '';
                  final subtitle =
                      !showSubtitle
                          ? ''
                          : lastEp.isNotEmpty
                          ? lastEp
                          : [
                            if (widget.video.year.isNotEmpty) widget.video.year,
                            if (widget.video.category.isNotEmpty)
                              widget.video.category,
                          ].join(' • ');
                  final scrimH = constraints.maxHeight * 0.30;

                  return Stack(
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
                          : FailoverCoverImage(
                            coverPath: widget.video.coverPath,
                            imgDomain: widget.imgDomain,
                            fit: BoxFit.cover,
                            filterQuality:
                                DeviceProfile.isConstrained
                                    ? FilterQuality.low
                                    : FilterQuality.high,
                            memCacheWidth: memW,
                            placeholderBuilder:
                                (_) => Container(
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
                            errorBuilder:
                                (_) => Container(
                                  color: const Color(0xFF1A1A1E),
                                  child: Icon(
                                    Icons.movie,
                                    color: Colors.white.withOpacity(0.1),
                                    size: 32,
                                  ),
                                ),
                          ),
                      // 底部 Scrim：约 30% 高，透明→深色，无 blur
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: scrimH,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.55),
                                  Colors.black.withOpacity(0.88),
                                ],
                                stops: const [0.0, 0.45, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 叠字：贴底部深色区
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.video.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    shadows: [
                                      Shadow(
                                        color: Color(0x66000000),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.75),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      shadows: const [
                                        Shadow(
                                          color: Color(0x66000000),
                                          blurRadius: 3,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Rating score badge
                      if (hasScore)
                        Positioned(
                          // On mobile with delete: place left to avoid overlap with the top-right delete button
                          top: 8,
                          left:
                              (widget.onDelete != null && !_isDesktop)
                                  ? 8
                                  : null,
                          right:
                              (widget.onDelete != null && !_isDesktop)
                                  ? null
                                  : 8,
                          child: AnimatedOpacity(
                            // Hide on desktop hover (delete button appears), always visible on mobile
                            opacity:
                                (widget.onDelete != null &&
                                        _hovered &&
                                        _isDesktop)
                                    ? 0.0
                                    : 1.0,
                            duration: const Duration(milliseconds: 250),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
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
                            child: SizedBox(
                              height: 3,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(1.5),
                                child: LinearProgressIndicator(
                                  value: (widget.video.lastPositionMs! /
                                          widget.video.lastDurationMs!)
                                      .clamp(0.0, 1.0),
                                  backgroundColor: Colors.white.withOpacity(
                                    0.15,
                                  ),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        _kRed,
                                      ),
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
                          child: ClipRRect(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                sigmaX: 8,
                                sigmaY: 8,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.4),
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
                                            customHeight:
                                                widget.buttonSize ??
                                                UIAdapt.px(
                                                  context,
                                                  widget.onDelete != null
                                                      ? 36
                                                      : 44,
                                                ),
                                          ),
                                          SizedBox(
                                            width: UIAdapt.px(
                                              context,
                                              widget.onDelete != null
                                                  ? 14
                                                  : 20,
                                            ),
                                          ),
                                          MubuButton(
                                            icon: Icons.info_outline_rounded,
                                            type: MubuButtonType.icon,
                                            onPressed: widget.onInfo,
                                            customHeight:
                                                widget.buttonSize ??
                                                UIAdapt.px(
                                                  context,
                                                  widget.onDelete != null
                                                      ? 36
                                                      : 44,
                                                ),
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
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    if (!isTvSurface) return RepaintBoundary(child: card);

    return RepaintBoundary(
      child: FocusableActionDetector(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPlay();
              return null;
            },
          ),
        },
        onFocusChange: _setTvFocused,
        child: AnimatedScale(
          scale: _tvFocused ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: card,
        ),
      ),
    );
  }
}
