import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

class CineVideoControls extends StatefulWidget {
  final VideoState state;
  final String? title;
  final VoidCallback? onBack;

  const CineVideoControls(
    this.state, {
    super.key,
    this.title,
    this.onBack,
  });

  @override
  State<CineVideoControls> createState() => _CineVideoControlsState();
}

class _CineVideoControlsState extends State<CineVideoControls> {
  bool _showControls = false;
  Timer? _hideTimer;
  Timer? _indicatorTimer;

  // Main-player scrub preview
  bool _isScrubbing = false;
  Duration? _anchorPosition;
  bool? _anchorWasPlaying;
  Duration _scrubTarget = Duration.zero;
  bool _showReturnTip = false;
  Timer? _returnTipTimer;
  Timer? _seekDebounceTimer;

  static const _returnTipDuration = Duration(seconds: 30);
  static const _returnTipMinOffset = Duration(seconds: 5);

  // 进度条拖动死区（迟滞）半径，单位：物理像素。
  static const double _kSliderDeadbandPx = 10.0;
  static const double _kSliderDeadbandFloorMs = 1200.0;

  // Gestures
  double _brightness = 0.5;
  double _volume = 100.0;

  /// Only the outer [fraction] of screen width accepts brightness/volume drags.
  static const double _kEdgeGestureWidthFraction = 0.2;

  /// Ignore small vertical movement so taps / scrolls do not adjust levels.
  static const double _kVerticalGestureThresholdPx = 24.0;

  _VerticalGestureKind _activeVerticalGesture = _VerticalGestureKind.none;
  double _verticalDragDistancePx = 0.0;

  // Indicator State
  String _indicatorText = '';
  IconData? _indicatorIcon;
  bool _showIndicator = false;

  Player get player => widget.state.widget.controller.player;

  late StreamSubscription _playingSub;
  late StreamSubscription _positionSub;
  late StreamSubscription _durationSub;
  late StreamSubscription _volumeSub;
  late StreamSubscription _bufferingSub;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isBuffering = false;

  DateTime? _bufferingStartTime;
  Timer? _bufferingUiTimer;
  bool _showWeakNetHint = false;

  bool get _hasAnchorSession => _anchorPosition != null;

  @override
  void initState() {
    super.initState();
    _volume = player.state.volume;
    _playing = player.state.playing;
    _position = player.state.position;
    _duration = player.state.duration;

    ScreenBrightness().current.then((value) {
      if (mounted) setState(() => _brightness = value);
    });

    _playingSub = player.stream.playing.listen((event) {
      if (mounted) setState(() => _playing = event);
    });
    _positionSub = player.stream.position.listen((event) {
      if (mounted && !_isScrubbing) {
        _position = event;
        if (_showControls) setState(() {});
      }
    });
    _durationSub = player.stream.duration.listen((event) {
      if (mounted) setState(() => _duration = event);
    });
    _volumeSub = player.stream.volume.listen((event) {
      if (mounted) setState(() => _volume = event);
    });
    _bufferingSub = player.stream.buffering.listen((event) {
      if (!mounted) return;
      setState(() => _isBuffering = event);
      if (event) {
        _bufferingStartTime ??= DateTime.now();
        _bufferingUiTimer ??= Timer(const Duration(seconds: 5), () {
          if (mounted && _isBuffering) {
            setState(() => _showWeakNetHint = true);
          }
        });
      } else {
        _bufferingStartTime = null;
        _bufferingUiTimer?.cancel();
        _bufferingUiTimer = null;
        if (_showWeakNetHint) setState(() => _showWeakNetHint = false);
      }
    });
  }

  @override
  void dispose() {
    _returnTipTimer?.cancel();
    _seekDebounceTimer?.cancel();
    ScreenBrightness().resetScreenBrightness();
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    _bufferingUiTimer?.cancel();
    _playingSub.cancel();
    _positionSub.cancel();
    _durationSub.cancel();
    _volumeSub.cancel();
    _bufferingSub.cancel();
    super.dispose();
  }

  void _toggleControls() {
    final willShow = !_showControls;
    setState(() => _showControls = willShow);
    if (willShow) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing && !_isScrubbing) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showActionIndicator(IconData icon, String text) {
    setState(() {
      _indicatorIcon = icon;
      _indicatorText = text;
      _showIndicator = true;
    });
    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showIndicator = false);
    });
  }

  void _clearAnchorSession() {
    _returnTipTimer?.cancel();
    _returnTipTimer = null;
    _anchorPosition = null;
    _anchorWasPlaying = null;
    _showReturnTip = false;
  }

  void _scheduleReturnTip() {
    final anchor = _anchorPosition;
    if (anchor == null) return;

    final offset = (_scrubTarget - anchor).abs();
    if (offset <= _returnTipMinOffset) {
      _clearAnchorSession();
      return;
    }

    _returnTipTimer?.cancel();
    setState(() => _showReturnTip = true);
    _returnTipTimer = Timer(_returnTipDuration, () {
      if (mounted) {
        setState(() => _clearAnchorSession());
      }
    });
  }

  Future<void> _seekMain(Duration target) async {
    _scrubTarget = target;
    await player.seek(target);
  }

  void _debouncedSeekMain(Duration target) {
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) _seekMain(target);
    });
  }

  void _onScrubStart(double ms) {
    _hideTimer?.cancel();
    _seekDebounceTimer?.cancel();

    if (!_hasAnchorSession) {
      _anchorPosition = _position;
      _anchorWasPlaying = _playing;
      if (_playing) player.pause();
    }

    final target = Duration(
      milliseconds: ms.clamp(0.0, _duration.inMilliseconds.toDouble()).toInt(),
    );

    setState(() {
      _isScrubbing = true;
      _scrubTarget = target;
      if (_showReturnTip) {
        _showReturnTip = false;
        _returnTipTimer?.cancel();
        _returnTipTimer = null;
      }
    });

    _seekMain(target);
  }

  void _onScrubUpdate(double milliseconds) {
    final screenWidth = MediaQuery.of(context).size.width;
    final trackWidth = (screenWidth - 132) > 100 ? (screenWidth - 132) : 100;
    final msPerPixel = _duration.inMilliseconds / trackWidth;

    var thresholdMs = msPerPixel * _kSliderDeadbandPx;
    if (thresholdMs < _kSliderDeadbandFloorMs) {
      thresholdMs = _kSliderDeadbandFloorMs;
    }

    if ((milliseconds - _scrubTarget.inMilliseconds.toDouble()).abs() < thresholdMs) {
      return;
    }

    final clampedMs = milliseconds.clamp(
      0.0,
      _duration.inMilliseconds.toDouble(),
    );
    setState(() {
      _scrubTarget = Duration(milliseconds: clampedMs.toInt());
    });
    _debouncedSeekMain(_scrubTarget);
  }

  void _onScrubEnd() {
    _seekDebounceTimer?.cancel();
    setState(() => _isScrubbing = false);
    _scheduleReturnTip();
    _startHideTimer();
  }

  Future<void> _returnToAnchor() async {
    final anchor = _anchorPosition;
    if (anchor == null) return;

    _seekDebounceTimer?.cancel();
    await _seekMain(anchor);
    if (_anchorWasPlaying == true) {
      await player.play();
    } else {
      await player.pause();
    }

    if (mounted) {
      setState(() {
        _position = anchor;
        _clearAnchorSession();
      });
    }
  }

  void _onVerticalDragStart(DragStartDetails details, double screenWidth) {
    if (!widget.state.isFullscreen()) return;
    _verticalDragDistancePx = 0.0;
    _activeVerticalGesture =
        _verticalGestureKindForX(details.globalPosition.dx, screenWidth);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double screenWidth) {
    if (!widget.state.isFullscreen()) return;
    if (_activeVerticalGesture == _VerticalGestureKind.none) return;

    _verticalDragDistancePx += details.delta.dy.abs();
    if (_verticalDragDistancePx < _kVerticalGestureThresholdPx) return;

    _startHideTimer();
    final dy = details.delta.dy;
    switch (_activeVerticalGesture) {
      case _VerticalGestureKind.brightness:
        setState(() {
          _brightness -= dy * 0.005;
          _brightness = _brightness.clamp(0.0, 1.0);
        });
        ScreenBrightness().setScreenBrightness(_brightness);
        _showActionIndicator(
          Icons.brightness_medium,
          '${(_brightness * 100).round()}%',
        );
      case _VerticalGestureKind.volume:
        setState(() {
          _volume -= dy * 0.5;
          _volume = _volume.clamp(0.0, 100.0);
        });
        player.setVolume(_volume);
        _showActionIndicator(
          _volume == 0 ? Icons.volume_off : Icons.volume_up,
          '${_volume.round()}%',
        );
      case _VerticalGestureKind.none:
        break;
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _activeVerticalGesture = _VerticalGestureKind.none;
    _verticalDragDistancePx = 0.0;
  }

  _VerticalGestureKind _verticalGestureKindForX(double dx, double screenWidth) {
    final edge = screenWidth * _kEdgeGestureWidthFraction;
    if (dx <= edge) return _VerticalGestureKind.brightness;
    if (dx >= screenWidth - edge) return _VerticalGestureKind.volume;
    return _VerticalGestureKind.none;
  }

  void _onDoubleTapDown(TapDownDetails details, double screenWidth) {
    if (!widget.state.isFullscreen()) return;

    if (_hasAnchorSession) _clearAnchorSession();

    if (details.globalPosition.dx < screenWidth / 2) {
      final target = _position - const Duration(seconds: 10);
      player.seek(target < Duration.zero ? Duration.zero : target);
      _showActionIndicator(Icons.replay_10, '-10s');
    } else {
      final target = _position + const Duration(seconds: 10);
      player.seek(target > _duration ? _duration : target);
      _showActionIndicator(Icons.forward_10, '+10s');
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final screenWidth = MediaQuery.of(context).size.width;
    final sliderValue = (_isScrubbing
            ? _scrubTarget.inMilliseconds.toDouble()
            : _position.inMilliseconds.toDouble())
        .clamp(
          0.0,
          _duration.inMilliseconds.toDouble() > 0
              ? _duration.inMilliseconds.toDouble()
              : 1.0,
        );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _toggleControls,
            onDoubleTapDown: (details) => _onDoubleTapDown(details, screenWidth),
            onVerticalDragStart: (details) =>
                _onVerticalDragStart(details, screenWidth),
            onVerticalDragUpdate: (details) =>
                _onVerticalDragUpdate(details, screenWidth),
            onVerticalDragEnd: _onVerticalDragEnd,
            behavior: HitTestBehavior.opaque,
          ),
        ),

        if (_showIndicator)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_indicatorIcon != null)
                    Icon(_indicatorIcon, color: Colors.white, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    _indicatorText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (_isScrubbing)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _formatDuration(_scrubTarget),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),

        if (_isBuffering && !_isScrubbing)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
                if (_showWeakNetHint) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            color: Colors.white54, size: 14),
                        SizedBox(width: 6),
                        Text(
                          '网络较弱，缓冲中…',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

        AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !_showControls,
            child: Stack(
              children: [
                if (widget.state.isFullscreen())
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + 4,
                        bottom: 8,
                        left: 16,
                        right: 16,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          if (widget.onBack != null)
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new,
                                  color: Colors.white),
                              onPressed: widget.onBack,
                            ),
                          if (widget.title != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.title!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.state.isFullscreen()) ...[
                        IconButton(
                          icon: const Icon(Icons.replay_10,
                              color: Colors.white, size: 48),
                          onPressed: () {
                            _startHideTimer();
                            final target =
                                _position - const Duration(seconds: 10);
                            player.seek(
                              target < Duration.zero ? Duration.zero : target,
                            );
                          },
                        ),
                        const SizedBox(width: 40),
                      ],
                      GestureDetector(
                        onTap: () {
                          _startHideTimer();
                          player.playOrPause();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primaryColor.withOpacity(0.8),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Icon(
                            _playing ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ),
                      if (widget.state.isFullscreen()) ...[
                        const SizedBox(width: 40),
                        IconButton(
                          icon: const Icon(Icons.forward_10,
                              color: Colors.white, size: 48),
                          onPressed: () {
                            _startHideTimer();
                            final target =
                                _position + const Duration(seconds: 10);
                            player.seek(
                              target > _duration ? _duration : target,
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.only(
                      top: 8,
                      bottom: MediaQuery.of(context).padding.bottom + 8,
                      left: 16,
                      right: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _formatDuration(_position),
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: primaryColor,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: primaryColor,
                              trackHeight: 4.0,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6.0,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14.0,
                              ),
                            ),
                            child: Slider(
                              value: sliderValue,
                              min: 0.0,
                              max: _duration.inMilliseconds.toDouble() > 0
                                  ? _duration.inMilliseconds.toDouble()
                                  : 1.0,
                              onChangeStart: _onScrubStart,
                              onChanged: _onScrubUpdate,
                              onChangeEnd: (_) => _onScrubEnd(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          _formatDuration(_duration),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            widget.state.isFullscreen()
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            _startHideTimer();
                            if (widget.state.isFullscreen()) {
                              widget.state.exitFullscreen();
                            } else {
                              widget.state.enterFullscreen();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_showReturnTip && _anchorPosition != null)
          Positioned(
            top: widget.state.isFullscreen()
                ? MediaQuery.of(context).padding.top + 56
                : 16,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _returnToAnchor,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: primaryColor.withOpacity(0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.undo, color: primaryColor, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '回到 ${_formatDuration(_anchorPosition!)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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
    );
  }
}

enum _VerticalGestureKind { none, brightness, volume }
