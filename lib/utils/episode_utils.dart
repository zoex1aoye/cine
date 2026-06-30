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
