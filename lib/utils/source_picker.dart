import '../models/mubu_models.dart';
import 'source_quality.dart';

/// Picks playback sources: latency pool → highest probe resolution → duration ranking.
///
/// Selection uses probe-derived labels (1080P, 720P, …), not API line names.
abstract final class SourcePicker {
  static const latencyGood = 500;
  static const latencyAcceptable = 800;

  static int? pickMainIndex(
    List<VideoSource> sources, {
    String? episodeName,
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
    String? episodeName,
    String? excludeUrl,
    bool preferLowerTierOnWeakNet = false,
  }) {
    final candidates = _candidates(sources, episodeName: episodeName, excludeUrl: excludeUrl);
    if (candidates.isEmpty) return null;

    if (preferLowerTierOnWeakNet) {
      final low = _pickFromPool(
        candidates
            .where((s) => SourceQuality.resolutionRank(s) <= 3)
            .toList(),
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

    return _bestByDurationThenLatency(candidates);
  }

  /// Best usable source at [resolutionLabel] (e.g. 1080P), scoped to [episodeName]
  /// when possible, otherwise any matching version group.
  static VideoSource? pickForResolution(
    List<VideoSource> sources, {
    required String resolutionLabel,
    String? episodeName,
    String? excludeUrl,
  }) {
    var candidates = sources.where((s) {
      if (!s.usable) return false;
      if (excludeUrl != null && s.url == excludeUrl) return false;
      return SourceQuality.resolutionLabel(s) == resolutionLabel;
    }).toList();

    if (episodeName != null && episodeName.isNotEmpty) {
      final scoped =
          candidates.where((s) => s.sourceName == episodeName).toList();
      if (scoped.isNotEmpty) candidates = scoped;
    }

    if (candidates.isEmpty) return null;
    return _bestByDurationThenLatency(candidates);
  }

  /// Fastest source within [withinResolution] and same max-minute bucket.
  static int? indexOfFastest(
    List<VideoSource> sources, {
    String? episodeName,
    String? withinResolution,
  }) {
    var maxMinute = 0;
    for (final s in sources) {
      if (episodeName != null &&
          episodeName.isNotEmpty &&
          s.sourceName != episodeName) {
        continue;
      }
      if (withinResolution != null &&
          SourceQuality.resolutionLabel(s) != withinResolution) {
        continue;
      }
      if (!s.usable) continue;
      final ms = _latency(s);
      if (ms >= 999999) continue;
      if (s.durationMinute > maxMinute) maxMinute = s.durationMinute;
    }

    int? bestIdx;
    var bestMs = 999999;
    for (var i = 0; i < sources.length; i++) {
      final s = sources[i];
      if (episodeName != null &&
          episodeName.isNotEmpty &&
          s.sourceName != episodeName) {
        continue;
      }
      if (withinResolution != null &&
          SourceQuality.resolutionLabel(s) != withinResolution) {
        continue;
      }
      if (!s.usable) continue;
      final ms = _latency(s);
      if (ms >= 999999) continue;
      if (s.durationMinute < maxMinute) continue;
      if (ms < bestMs) {
        bestMs = ms;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  /// Episode-scoped usable sources; falls back to all usable when the group is empty.
  static List<VideoSource> _candidates(
    List<VideoSource> sources, {
    String? episodeName,
    String? excludeUrl,
  }) {
    bool matches(VideoSource s) {
      if (!s.usable) return false;
      if (excludeUrl != null && s.url == excludeUrl) return false;
      return true;
    }

    if (episodeName != null && episodeName.isNotEmpty) {
      final scoped = sources
          .where((s) => s.sourceName == episodeName && matches(s))
          .toList();
      if (scoped.isNotEmpty) return scoped;
    }

    return sources.where(matches).toList();
  }

  static VideoSource? _pickFromPool(List<VideoSource> pool, int maxMs) {
    if (pool.isEmpty) return null;
    final tested = pool.where((s) => _latency(s) <= maxMs).toList();
    if (tested.isEmpty) return null;
    return _pickBestResolutionChampion(tested);
  }

  /// Per-resolution champion; pick the sharpest resolution bucket.
  static VideoSource? _pickBestResolutionChampion(List<VideoSource> list) {
    if (list.isEmpty) return null;

    final champions = <String, VideoSource>{};
    for (final s in list) {
      final label = SourceQuality.resolutionLabel(s) ?? '_unknown';
      final existing = champions[label];
      if (existing == null || _compareDurationThenLatency(s, existing) < 0) {
        champions[label] = s;
      }
    }

    String? bestLabel;
    var bestRank = -1;
    for (final entry in champions.entries) {
      final rank = entry.key == '_unknown'
          ? 0
          : SourceQuality.resolutionRank(entry.value);
      if (rank > bestRank) {
        bestRank = rank;
        bestLabel = entry.key;
      }
    }
    return bestLabel != null ? champions[bestLabel] : null;
  }

  static VideoSource? _bestByDurationThenLatency(List<VideoSource> list) {
    if (list.isEmpty) return null;
    list.sort((a, b) {
      final resCmp =
          SourceQuality.resolutionRank(b).compareTo(SourceQuality.resolutionRank(a));
      if (resCmp != 0) return resCmp;
      return _compareDurationThenLatency(a, b);
    });
    return list.first;
  }

  static int _compareDurationThenLatency(VideoSource a, VideoSource b) {
    final aHasBitrate = (a.probeBitrateKbps ?? 0) > 0;
    final bHasBitrate = (b.probeBitrateKbps ?? 0) > 0;
    if (aHasBitrate != bHasBitrate) return aHasBitrate ? -1 : 1;

    final aMin = a.durationMinute;
    final bMin = b.durationMinute;
    if (aMin != bMin) return bMin.compareTo(aMin);

    return _latency(a).compareTo(_latency(b));
  }

  static int _latency(VideoSource s) => s.playlistMs ?? 999999;
}
