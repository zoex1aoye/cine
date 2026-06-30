/// Episode identity helpers (weight preferred, source_name fallback).
import '../models/mubu_models.dart';

/// Normalized episode key for matching and [SourcePicker] filters.
String episodeRef(VideoSource source) {
  if (source.weight.isNotEmpty) return source.weight;
  return source.sourceName;
}

/// Whether [source] is the same episode as [ref] (weight or source_name).
bool matchesEpisode(VideoSource source, String ref) {
  if (ref.isEmpty) return false;
  if (source.weight.isNotEmpty && source.weight == ref) return true;
  return source.sourceName == ref;
}
