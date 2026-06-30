import '../models/mubu_models.dart';
import 'episode_utils.dart';
import 'source_quality.dart';

QualityTier _tier(VideoSource s) => SourceQuality.effectiveTierFor(
      name: s.name,
      sourceConfigName: s.sourceConfigName,
      probedTier: s.probedTier,
    );

/// Picks playback sources: latency pool → highest tier → min latency within tier.
abstract final class SourcePicker {
  static const latencyGood = 500;
  static const latencyAcceptable = 800;

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
      if (!matchesEpisode(s, episodeName)) return false;
      if (!s.usable) return false;
      if (excludeUrl != null && s.url == excludeUrl) return false;
      return true;
    }).toList();

    if (candidates.isEmpty) return null;

    if (preferLowerTierOnWeakNet) {
      final low = _pickFromPool(
        candidates.where((s) {
          final t = _tier(s);
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

    return _bestByLatencyThenTier(candidates);
  }

  static VideoSource? pickPreview(
    List<VideoSource> sources, {
    required String episodeName,
    required String excludeUrl,
  }) {
    final candidates = sources
        .where((s) =>
            matchesEpisode(s, episodeName) &&
            s.usable &&
            s.url != excludeUrl)
        .toList();
    if (candidates.isEmpty) return null;

    final lowTiers = candidates.where((s) {
      final t = _tier(s);
      return t == QualityTier.smooth || t == QualityTier.sd;
    }).toList();

    if (lowTiers.isNotEmpty) {
      lowTiers.sort((a, b) {
        final ta = _tier(a);
        final tb = _tier(b);
        if (ta == QualityTier.smooth && tb != QualityTier.smooth) return -1;
        if (tb == QualityTier.smooth && ta != QualityTier.smooth) return 1;
        return _latency(a).compareTo(_latency(b));
      });
      return lowTiers.first;
    }

    return _bestByLatencyThenTier(candidates);
  }

  /// Fastest source within [withinTier] (same episode); omit tier for global fastest.
  static int? indexOfFastest(
    List<VideoSource> sources, {
    String? episodeName,
    QualityTier? withinTier,
  }) {
    int? bestIdx;
    var bestMs = 999999;
    for (var i = 0; i < sources.length; i++) {
      final s = sources[i];
      if (episodeName != null && !matchesEpisode(s, episodeName)) continue;
      if (withinTier != null && _tier(s) != withinTier) continue;
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
    final tested =
        pool.where((s) => s.speedMs != null && s.speedMs! <= maxMs).toList();
    if (tested.isEmpty) return null;
    return _pickBestTierChampion(tested);
  }

  /// Per-tier min latency champion, then highest-rank tier wins.
  static VideoSource? _pickBestTierChampion(List<VideoSource> list) {
    if (list.isEmpty) return null;

    final champions = <QualityTier, VideoSource>{};
    for (final s in list) {
      final tier = _tier(s);
      final existing = champions[tier];
      if (existing == null ||
          _latency(s) < _latency(existing) ||
          (_latency(s) == _latency(existing) &&
              s.listOrder < existing.listOrder)) {
        champions[tier] = s;
      }
    }

    QualityTier? bestTier;
    for (final tier in champions.keys) {
      if (bestTier == null ||
          SourceQuality.rank(tier) > SourceQuality.rank(bestTier)) {
        bestTier = tier;
      }
    }
    return bestTier != null ? champions[bestTier] : null;
  }

  static VideoSource? _bestByLatencyThenTier(List<VideoSource> list) {
    if (list.isEmpty) return null;
    list.sort((a, b) {
      final lat = _latency(a).compareTo(_latency(b));
      if (lat != 0) return lat;
      final tier = SourceQuality.effectiveRankFor(
        name: b.name,
        sourceConfigName: b.sourceConfigName,
        probedTier: b.probedTier,
      ).compareTo(
        SourceQuality.effectiveRankFor(
          name: a.name,
          sourceConfigName: a.sourceConfigName,
          probedTier: a.probedTier,
        ),
      );
      if (tier != 0) return tier;
      return a.listOrder.compareTo(b.listOrder);
    });
    return list.first;
  }

  static int _latency(VideoSource s) => s.speedMs ?? 999999;
}
