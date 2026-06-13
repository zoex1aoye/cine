// lib/api/mubu_storage.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mubu_models.dart';

class MubuStorage {
  static const _keyBookmarks = 'mubu_bookmarks';
  static const _keyHistory = 'mubu_history';

  // In-memory progress cache — written synchronously so getHistory() always
  // returns fresh progress even before the async SharedPreferences write lands.
  static final Map<int, VideoItem> _progressCache = {};

  // Write queue — serializes all SharedPreferences writes to prevent
  // read-modify-write races from concurrent callers (e.g. periodic timer + source switch).
  static Future<void> _writeQueue = Future.value();

  static void cacheProgress(VideoItem item) {
    _progressCache[item.id] = item;
  }

  // --- Bookmarks ---

  /// Read bookmarks from a given [prefs] instance (queue-safe).
  static List<VideoItem> _readBookmarks(SharedPreferences prefs) {
    final data = prefs.getStringList(_keyBookmarks) ?? [];
    return data.map((item) {
      try {
        return VideoItem.fromJson(json.decode(item));
      } catch (e) {
        return null;
      }
    }).whereType<VideoItem>().toList();
  }

  /// Public getter — waits for pending writes before reading so callers always
  /// see the latest data even when a write is queued.
  static Future<List<VideoItem>> getBookmarks() async {
    await _writeQueue;
    final prefs = await SharedPreferences.getInstance();
    return _readBookmarks(prefs);
  }

  static Future<void> toggleBookmark(VideoItem video) async {
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = _readBookmarks(prefs); // use queue-safe internal reader
        final index = list.indexWhere((item) => item.id == video.id);
        if (index >= 0) {
          list.removeAt(index);
        } else {
          list.insert(0, video);
        }
        final serialized = list.map((item) => json.encode(item.toJson())).toList();
        await prefs.setStringList(_keyBookmarks, serialized);
      } catch (e) {
        debugPrint('STORAGE: write queue error: $e');
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  static Future<bool> isBookmarked(int videoId) async {
    final list = await getBookmarks();
    return list.any((item) => item.id == videoId);
  }

  // --- Watch History ---

  /// Read history from a given [prefs] instance (queue-safe).
  static List<VideoItem> _readHistory(SharedPreferences prefs) {
    final data = prefs.getStringList(_keyHistory) ?? [];
    final list = data.map((item) {
      try {
        return VideoItem.fromJson(json.decode(item));
      } catch (e) {
        return null;
      }
    }).whereType<VideoItem>().toList();
    // Merge in-memory progress cache (instant, no async gap)
    for (var i = 0; i < list.length; i++) {
      final cached = _progressCache[list[i].id];
      if (cached != null) {
        list[i] = VideoItem(
          id: list[i].id,
          title: list[i].title,
          coverPath: list[i].coverPath,
          year: list[i].year,
          score: list[i].score,
          category: list[i].category,
          description: list[i].description,
          lastPositionMs: cached.lastPositionMs,
          lastDurationMs: cached.lastDurationMs,
          lastEpisodeName: cached.lastEpisodeName,
          lastLineName: cached.lastLineName,
        );
      }
    }
    return list;
  }

  /// Public getter — waits for pending writes so callers always see the latest data.
  static Future<List<VideoItem>> getHistory() async {
    await _writeQueue;
    final prefs = await SharedPreferences.getInstance();
    return _readHistory(prefs);
  }

  static Future<void> recordWatch(VideoItem video, {int? positionMs, int? durationMs, String? episodeName, String? lineName}) async {
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
    // Sync cache first
    cacheProgress(item);
    // Then persist (queued)
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = _readHistory(prefs); // use queue-safe internal reader
        list.removeWhere((item) => item.id == video.id);
        list.insert(0, item);
        if (list.length > 100) list.removeLast();
        final serialized = list.map((item) => json.encode(item.toJson())).toList();
        await prefs.setStringList(_keyHistory, serialized);
      } catch (e) {
        debugPrint('STORAGE: write queue error: $e');
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  /// Update progress in-place without changing list order (used by periodic save)
  static Future<void> updateProgress(int videoId, int positionMs, int durationMs, String? episodeName, {String? lineName}) async {
    // Sync cache FIRST — before any awaits, so getHistory() sees fresh data instantly
    final cached = _progressCache[videoId];
    cacheProgress(VideoItem(
      id: videoId,
      title: cached?.title ?? '',
      coverPath: cached?.coverPath ?? '',
      year: cached?.year ?? '',
      score: cached?.score ?? '',
      category: cached?.category ?? '',
      description: cached?.description ?? '',
      lastPositionMs: positionMs,
      lastDurationMs: durationMs,
      lastEpisodeName: episodeName,
      lastLineName: lineName,
    ));
    // Then persist (queued to prevent concurrent read-modify-write)
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = _readHistory(prefs); // use queue-safe internal reader
        final idx = list.indexWhere((item) => item.id == videoId);
        if (idx < 0) return;
        final old = list[idx];
        list[idx] = VideoItem(
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
        );
        final serialized = list.map((item) => json.encode(item.toJson())).toList();
        await prefs.setStringList(_keyHistory, serialized);
      } catch (e) {
        debugPrint('STORAGE: write queue error: $e');
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  static Future<void> deleteHistoryItem(int videoId) async {
    _progressCache.remove(videoId);
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = _readHistory(prefs); // use queue-safe internal reader
        list.removeWhere((item) => item.id == videoId);
        final serialized = list.map((item) => json.encode(item.toJson())).toList();
        await prefs.setStringList(_keyHistory, serialized);
      } catch (e) {
        debugPrint('STORAGE: write queue error: $e');
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  static Future<void> clearHistory() async {
    _progressCache.clear();
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_keyHistory);
      } catch (e) {
        debugPrint('STORAGE: write queue error: $e');
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }
}
