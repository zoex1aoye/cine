import '../models/mubu_models.dart';
import 'source_quality.dart';

/// Picks playback sources by latency pool + quality rank.
abstract final class SourcePicker {
  static const latencyGood = 500;
  static const latencyAcceptable = 800;

  /// Main player: among [episodeName], pick highest quality in the best latency pool.
  static int? pickMainIndex(
    List<VideoSource> sources, {
    required String episodeName,
    String? excludeUrl,
    bool preferLowerTierOnWeakNet = false,
  }) {
    final picked = pickMain(
      sources,
      episodeName: episodeName,
      excludeUrl: excludeUrl,
      preferLowerTierOnWeakNet: preferLowerTierOnWeakNet,
    );
    if (picked == null) return null;
    return sources.indexOf(picked);
  }

  static VideoSource? pickMain(
    List<VideoSource> sources, {
    required String episodeName,
    String? excludeUrl,
    bool preferLowerTierOnWeakNet = false,
  }) {
    var candidates = sources.where((s) {
      if (s.sourceName != episodeName) return false;
      if (!s.usable) return false;
      if (excludeUrl != null && s.url == excludeUrl) return false;
      return true;
    }).toList();

    if (candidates.isEmpty) return null;

    if (preferLowerTierOnWeakNet) {
      final low = _pickFromPool(
        candidates.where((s) {
          final t = SourceQuality.classify(s.name, sourceConfigName: s.sourceConfigName);
          return t == QualityTier.smooth || t == QualityTier.sd;
        }).toList(),
        latencyGood,
      );
      if (low != null) return low;
    }

    final good = _pickFromPool(
      candidates.where((s) => _latency(s) <= latencyGood).toList(),
      latencyGood,
    );
    if (good != null) return good;

    final ok = _pickFromPool(
      candidates.where((s) => _latency(s) <= latencyAcceptable).toList(),
      latencyAcceptable,
    );
    if (ok != null) return ok;

    return _bestByQualityThenLatency(candidates);
  }

  /// Preview player: prefer 流畅 / 标清, then lowest latency.
  static VideoSource? pickPreview(
    List<VideoSource> sources, {
    required String episodeName,
    required String excludeUrl,
  }) {
    final candidates = sources
        .where((s) =>
            s.sourceName == episodeName &&
            s.usable &&
            s.url != excludeUrl)
        .toList();
    if (candidates.isEmpty) return null;

    final lowTiers = candidates.where((s) {
      final t = SourceQuality.classify(s.name, sourceConfigName: s.sourceConfigName);
      return t == QualityTier.smooth || t == QualityTier.sd;
    }).toList();

    if (lowTiers.isNotEmpty) {
      lowTiers.sort((a, b) {
        final ta = SourceQuality.classify(a.name, sourceConfigName: a.sourceConfigName);
        final tb = SourceQuality.classify(b.name, sourceConfigName: b.sourceConfigName);
        // 预览优先流畅（分片更小），同档比延迟
        if (ta == QualityTier.smooth && tb != QualityTier.smooth) return -1;
        if (tb == QualityTier.smooth && ta != QualityTier.smooth) return 1;
        return _latency(a).compareTo(_latency(b));
      });
      return lowTiers.first;
    }

    return _bestByQualityThenLatency(candidates);
  }

  static int? indexOfFastest(
    List<VideoSource> sources, {
    String? episodeName,
  }) {
    int? bestIdx;
    var bestMs = 999999;
    for (var i = 0; i < sources.length; i++) {
      final s = sources[i];
      if (episodeName != null && s.sourceName != episodeName) continue;
      if (!s.usable || s.speedMs == null) continue;
      final ms = s.speedMs!;
      if (ms >= 999999) continue;
      if (ms < bestMs) {
        bestMs = ms;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  static VideoSource? _pickFromPool(List<VideoSource> pool, int maxMs) {
    if (pool.isEmpty) return null;
    final tested = pool.where((s) => s.speedMs != null && s.speedMs! <= maxMs).toList();
    if (tested.isEmpty) return null;
    return _bestByQualityThenLatency(tested);
  }

  static VideoSource? _bestByQualityThenLatency(List<VideoSource> list) {
    if (list.isEmpty) return null;
    list.sort((a, b) {
      final q = SourceQuality.rankForSource(b.name, sourceConfigName: b.sourceConfigName)
          .compareTo(SourceQuality.rankForSource(a.name, sourceConfigName: a.sourceConfigName));
      if (q != 0) return q;
      return _latency(a).compareTo(_latency(b));
    });
    return list.first;
  }

  static int _latency(VideoSource s) => s.speedMs ?? 999999;
}
