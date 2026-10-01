/// Episode identity helpers (source_name preferred, weight fallback).
import '../models/mubu_models.dart';

/// Normalized episode key for matching and [SourcePicker] filters.
///
/// Uses [VideoSource.sourceName] first so CDN mirrors sharing the same episode
/// label stay in scope even when API assigns per-line [VideoSource.weight] values.
String episodeRef(VideoSource source) {
  if (source.sourceName.isNotEmpty) return source.sourceName;
  if (source.weight.isNotEmpty) return source.weight;
  return '';
}

/// Whether [source] is the same episode as [ref] (source_name or weight).
bool matchesEpisode(VideoSource source, String ref) {
  if (ref.isEmpty) return false;
  if (source.sourceName.isNotEmpty && source.sourceName == ref) return true;
  if (source.weight.isNotEmpty && source.weight == ref) return true;
  return false;
}

/// Index of the probe/display representative for [lineName].
///
/// Prefers a source matching [episodeRef] (current episode). If none — e.g. film
/// CDNs with divergent `source_name` labels — falls back to the first source on
/// that line so line lists and speed tests still cover every distinct line.
int representativeIndexForLine(
  List<VideoSource> sources,
  String lineName, {
  String episodeRef = '',
}) {
  if (lineName.isEmpty || sources.isEmpty) return -1;
  if (episodeRef.isNotEmpty) {
    final matched = sources.indexWhere(
      (s) => s.name == lineName && matchesEpisode(s, episodeRef),
    );
    if (matched >= 0) return matched;
  }
  return sources.indexWhere((s) => s.name == lineName);
}

final _seriesEpisodeLabel = RegExp(
  r'第\s*\d+\s*集|EP?\s*\d+|S\d+\s*E\s*\d+',
  caseSensitive: false,
);

/// Whether [label] looks like a numbered TV/short-drama episode.
bool looksLikeSeriesEpisodeLabel(String label) {
  final t = label.trim();
  if (t.isEmpty) return false;
  return _seriesEpisodeLabel.hasMatch(t);
}

/// Film / single-title layout: version labels (正片、BD…、1080P) rather than
/// shared「第N集」across CDNs. Used to ignore episode scope when auto-picking
/// the globally fastest line.
bool isFilmStyleSources(List<VideoSource> sources) {
  if (sources.isEmpty) return true;
  var seriesLike = 0;
  for (final s in sources) {
    if (looksLikeSeriesEpisodeLabel(s.sourceName) ||
        looksLikeSeriesEpisodeLabel(s.weight)) {
      seriesLike++;
    }
  }
  return seriesLike < 2;
}

/// Episode scope for [SourcePicker]: empty on film-style titles (global pick).
String pickScopeEpisodeName(
  List<VideoSource> sources,
  String currentEpisodeRef,
) {
  if (isFilmStyleSources(sources)) return '';
  return currentEpisodeRef;
}
