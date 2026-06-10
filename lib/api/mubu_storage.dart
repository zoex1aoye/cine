// lib/api/mubu_storage.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mubu_models.dart';

class MubuStorage {
  static const _keyBookmarks = 'mubu_bookmarks';
  static const _keyHistory = 'mubu_history';

  // --- Bookmarks ---
  static Future<List<VideoItem>> getBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_keyBookmarks) ?? [];
    return data.map((item) {
      try {
        return VideoItem.fromJson(json.decode(item));
      } catch (e) {
        return null;
      }
    }).whereType<VideoItem>().toList();
  }

  static Future<void> toggleBookmark(VideoItem video) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getBookmarks();
    final index = list.indexWhere((item) => item.id == video.id);
    if (index >= 0) {
      list.removeAt(index);
    } else {
      list.insert(0, video);
    }
    final serialized = list.map((item) => json.encode(item.toJson())).toList();
    await prefs.setStringList(_keyBookmarks, serialized);
  }

  static Future<bool> isBookmarked(int videoId) async {
    final list = await getBookmarks();
    return list.any((item) => item.id == videoId);
  }

  // --- Watch History ---
  static Future<List<VideoItem>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_keyHistory) ?? [];
    return data.map((item) {
      try {
        return VideoItem.fromJson(json.decode(item));
      } catch (e) {
        return null;
      }
    }).whereType<VideoItem>().toList();
  }

  static Future<void> recordWatch(VideoItem video) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getHistory();
    // Remove duplicates
    list.removeWhere((item) => item.id == video.id);
    // Insert at front
    list.insert(0, video);
    // Capacity limit
    if (list.length > 100) list.removeLast();
    final serialized = list.map((item) => json.encode(item.toJson())).toList();
    await prefs.setStringList(_keyHistory, serialized);
  }

  static Future<void> deleteHistoryItem(int videoId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getHistory();
    list.removeWhere((item) => item.id == videoId);
    final serialized = list.map((item) => json.encode(item.toJson())).toList();
    await prefs.setStringList(_keyHistory, serialized);
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHistory);
  }
}
