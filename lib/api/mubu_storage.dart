// lib/api/mubu_storage.dart
import 'dart:async';
import 'package:hive/hive.dart';
import '../models/mubu_models.dart';

class MubuStorage {
  static Box<VideoItem> get _bookmarks => Hive.box<VideoItem>('bookmarks');
  static Box<VideoItem> get _history => Hive.box<VideoItem>('history');

  // --- Bookmarks ---

  static Future<List<VideoItem>> getBookmarks() async {
    // Hive values are in insertion order. Reversing puts newest first.
    return _bookmarks.values.toList().reversed.toList();
  }

  static Future<void> toggleBookmark(VideoItem video) async {
    final key = video.id;
    if (_bookmarks.containsKey(key)) {
      await _bookmarks.delete(key);
    } else {
      await _bookmarks.put(key, video);
    }
  }

  static Future<bool> isBookmarked(int videoId) async {
    return _bookmarks.containsKey(videoId);
  }

  // --- Watch History ---

  static Future<List<VideoItem>> getHistory() async {
    // Hive values are in insertion order. Reversing puts newest first.
    return _history.values.toList().reversed.toList();
  }

  static Future<void> recordWatch(
      VideoItem video, {
      int? positionMs,
      int? durationMs,
      String? episodeName,
      String? lineName,
  }) async {
    final item = VideoItem(
      id: video.id,
      title: video.title,
      coverPath: video.coverPath,
      year: video.year,
      score: video.score,
      category: video.category,
      description: video.description,
      lastPositionMs: positionMs,
      lastDurationMs: durationMs,
      lastEpisodeName: episodeName,
      lastLineName: lineName,
    );

    // Delete existing to move it to the end of insertion order (newest)
    if (_history.containsKey(video.id)) {
      await _history.delete(video.id);
    }
    await _history.put(video.id, item);

    // Keep max 100 items
    if (_history.length > 100) {
      // The oldest items are at the beginning of the keys
      final keysToDelete = _history.keys.toList().sublist(0, _history.length - 100);
      await _history.deleteAll(keysToDelete);
    }
  }

  /// Update progress in-place without changing list order (used by periodic save)
  static Future<void> updateProgress(
      int videoId,
      int positionMs,
      int durationMs,
      String? episodeName, {
      String? lineName,
  }) async {
    final old = _history.get(videoId);
    if (old == null) return;

    // Putting to an existing key preserves its insertion order in Hive
    await _history.put(videoId, VideoItem(
      id: old.id,
      title: old.title,
      coverPath: old.coverPath,
      year: old.year,
      score: old.score,
      category: old.category,
      description: old.description,
      lastPositionMs: positionMs,
      lastDurationMs: durationMs,
      lastEpisodeName: episodeName,
      lastLineName: lineName,
    ));
  }

  static Future<void> deleteHistoryItem(int videoId) async {
    await _history.delete(videoId);
  }

  static Future<void> clearHistory() async {
    await _history.clear();
  }
}
