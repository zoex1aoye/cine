import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/mubu_api_client.dart';
import '../utils/cover_cdn.dart';
import '../utils/device_profile.dart';
import '../utils/playback_cover_gate.dart';

/// 会话内记住某 `coverPath` 在哪个图片域加载成功。
class CoverDomainSessionCache {
  CoverDomainSessionCache._();

  static final Map<String, String> _pathToDomain = {};

  static String? domainFor(String coverPath) {
    if (coverPath.isEmpty) return null;
    return _pathToDomain[coverPath];
  }

  static void remember(String coverPath, String domain) {
    final d = normalizeImgDomain(domain);
    if (coverPath.isEmpty || d.isEmpty) return;
    _pathToDomain[coverPath] = d;
  }

  /// 仅测试用。
  @visibleForTesting
  static void clear() => _pathToDomain.clear();
}

/// 封面加载：主域失败后按候选顺序换域；全失败走 [errorBuilder]。
class FailoverCoverImage extends StatefulWidget {
  final String coverPath;
  final String imgDomain;
  final List<String>? candidates;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final Color? color;
  final BlendMode? colorBlendMode;
  final WidgetBuilder? placeholderBuilder;
  final WidgetBuilder? errorBuilder;
  /// Decode width/height hints for [CachedNetworkImage] (physical px preferred).
  final int? memCacheWidth;
  final int? memCacheHeight;

  /// 播放页自己的背景封面。为 true 时，下层列表卸封面期间这一张仍解码。
  final bool holdDuringPlayback;

  const FailoverCoverImage({
    super.key,
    required this.coverPath,
    required this.imgDomain,
    this.candidates,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.low,
    this.color,
    this.colorBlendMode,
    this.placeholderBuilder,
    this.errorBuilder,
    this.memCacheWidth,
    this.memCacheHeight,
    this.holdDuringPlayback = false,
  });

  @override
  State<FailoverCoverImage> createState() => _FailoverCoverImageState();
}

class _FailoverCoverImageState extends State<FailoverCoverImage> {
  late List<String> _candidates;
  late int _index;
  late String _url;
  bool _exhausted = false;
  bool _failoverScheduled = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.holdDuringPlayback) {
      PlaybackCoverGate.listenable.addListener(_onPlaybackCover);
    }
    _bootstrap();
    CoverCdnSignals.epoch.addListener(_onDomainChanged);
  }

  @override
  void dispose() {
    if (!widget.holdDuringPlayback) {
      PlaybackCoverGate.listenable.removeListener(_onPlaybackCover);
    }
    CoverCdnSignals.epoch.removeListener(_onDomainChanged);
    super.dispose();
  }

  void _onDomainChanged() {
    if (!mounted) return;
    _attempt = 0;
    setState(_bootstrap);
  }

  void _onPlaybackCover() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant FailoverCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverPath != widget.coverPath ||
        oldWidget.imgDomain != widget.imgDomain ||
        !_listEq(oldWidget.candidates, widget.candidates)) {
      _bootstrap();
    }
  }

  bool _listEq(List<String>? a, List<String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<String> _resolveCandidates() {
    List<String> package = const [];
    var primary = widget.imgDomain;
    if (widget.candidates != null && widget.candidates!.isNotEmpty) {
      package = widget.candidates!;
    } else {
      try {
        package = MubuApiClient.instance.imgDomainCandidates;
        final live = MubuApiClient.instance.imgDomain;
        if (live.isNotEmpty) primary = live;
      } catch (_) {
        package = const [];
      }
    }
    return mergeImgDomainCandidates(
      primary: primary,
      fromPackage: package,
    );
  }

  void _bootstrap() {
    _exhausted = false;
    _failoverScheduled = false;
    _candidates = _resolveCandidates();
    final cached = CoverDomainSessionCache.domainFor(widget.coverPath);
    var start = 0;
    if (cached != null) {
      final i = _candidates.indexOf(cached);
      if (i >= 0) start = i;
    }
    if (_candidates.isEmpty || widget.coverPath.isEmpty) {
      _index = -1;
      _url = '';
      _exhausted = true;
      return;
    }
    _index = start;
    _url = buildCoverUrlOnDomain(widget.coverPath, _candidates[_index]);
    if (_url.isEmpty) {
      _advanceOrExhaust();
    }
  }

  void _advanceOrExhaust() {
    final next = nextCoverCandidate(
      coverPath: widget.coverPath,
      candidates: _candidates,
      afterIndex: _index,
    );
    if (next == null) {
      _exhausted = true;
      _url = '';
      return;
    }
    _index = next.index;
    _url = next.url;
  }

  void _onLoadFailed() {
    if (!mounted || _exhausted) return;
    setState(() {
      _advanceOrExhaust();
    });
    if (_exhausted) _scheduleRetry();
  }

  /// 冷启动时图片域或网络还没好，候选会一次耗尽。稍后再用最新域名重试。
  void _scheduleRetry() {
    if (_attempt >= 2) return;
    _attempt++;
    final wait = Duration(milliseconds: 400 * _attempt);
    Future.delayed(wait, () {
      if (!mounted) return;
      setState(_bootstrap);
    });
  }

  void _onLoadSuccess() {
    _attempt = 0;
    if (_index >= 0 && _index < _candidates.length) {
      CoverDomainSessionCache.remember(widget.coverPath, _candidates[_index]);
    }
  }

  Widget _defaultPlaceholder(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1E),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFE50914),
          ),
        ),
      ),
    );
  }

  Widget _defaultError(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1E),
      child: Icon(
        Icons.movie,
        color: Colors.white.withOpacity(0.1),
        size: 32,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.holdDuringPlayback &&
        DeviceProfile.isConstrained &&
        PlaybackCoverGate.isHeld) {
      return const ColoredBox(color: Color(0xFF1A1A1E));
    }
    if (widget.coverPath.isEmpty || _exhausted || _url.isEmpty) {
      return (widget.errorBuilder ?? _defaultError)(context);
    }

    return CachedNetworkImage(
      key: ValueKey('$_url#$_attempt'),
      imageUrl: _url,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
      color: widget.color,
      colorBlendMode: widget.colorBlendMode,
      memCacheWidth: widget.memCacheWidth,
      memCacheHeight: widget.memCacheHeight,
      placeholder: (_, __) =>
          (widget.placeholderBuilder ?? _defaultPlaceholder)(context),
      errorWidget: (_, __, ___) {
        if (!_failoverScheduled && !_exhausted) {
          _failoverScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _failoverScheduled = false;
            _onLoadFailed();
          });
        }
        return (widget.placeholderBuilder ?? _defaultPlaceholder)(context);
      },
      imageBuilder: (context, provider) {
        _onLoadSuccess();
        return Image(
          image: provider,
          fit: widget.fit,
          filterQuality: widget.filterQuality,
          color: widget.color,
          colorBlendMode: widget.colorBlendMode,
        );
      },
    );
  }
}
