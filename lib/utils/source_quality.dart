/// Quality tier classification for playback sources.
///
/// Labels come from API audit (`source_list_source` / `vip_source_list_source`):
/// - Quality tiers: 高清线路*, 极速蓝光, 高速蓝光, 蓝光线路, VIP线路
/// - CDN mirrors: LZ线路, SN线路, … (ends with 线路, no quality keyword)
/// - Short drama: source_config_name often "常规线路"
import 'package:flutter/material.dart';

import '../models/mubu_models.dart';

enum QualityTier {
  hd,
  bluRay,
  sd,
  smooth,
  vip,
  cdn,
  unknown,
}

abstract final class SourceQuality {
  /// Rank for main-player auto selection (higher = preferred when latency OK).
  /// 高清 > 蓝光/VIP > 标清 > 流畅/CDN/unknown
  static int rank(QualityTier tier) => switch (tier) {
        QualityTier.hd => 4,
        QualityTier.bluRay => 3,
        QualityTier.vip => 3,
        QualityTier.sd => 2,
        QualityTier.smooth => 1,
        QualityTier.cdn => 1,
        QualityTier.unknown => 0,
      };

  static QualityTier classify(String name, {String sourceConfigName = ''}) {
    final label = _normalize(
      sourceConfigName.isNotEmpty ? sourceConfigName : name,
    );
    if (label.contains('标清')) return QualityTier.sd;
    if (label.contains('流畅')) return QualityTier.smooth;
    if (label.contains('高清')) return QualityTier.hd;
    if (label.contains('vip') || label.contains('vip线路')) {
      return QualityTier.vip;
    }
    if (label.contains('蓝光')) return QualityTier.bluRay;
    if (label.endsWith('线路')) return QualityTier.cdn;
    return QualityTier.unknown;
  }

  static int rankForSource(String name, {String sourceConfigName = ''}) =>
      rank(classify(name, sourceConfigName: sourceConfigName));

  /// Effective tier: probed result overrides label heuristics (CDN mirrors).
  static QualityTier effectiveTierFor({
    required String name,
    String sourceConfigName = '',
    QualityTier? probedTier,
  }) =>
      probedTier ?? classify(name, sourceConfigName: sourceConfigName);

  static int effectiveRankFor({
    required String name,
    String sourceConfigName = '',
    QualityTier? probedTier,
  }) =>
      rank(effectiveTierFor(
        name: name,
        sourceConfigName: sourceConfigName,
        probedTier: probedTier,
      ));

  /// Map stream probe metrics to a quality tier.
  static QualityTier tierFromProbe(
    int width,
    int height,
    int bitrateKbps, {
    String label = '',
  }) {
    final h = height > 0 ? height : (width > 0 ? (width * 9 ~/ 16) : 0);
    final norm = _normalize(label);
    final bluRayLabel = norm.contains('蓝光') || norm.contains('vip');

    if (h >= 1080 || bitrateKbps >= 4000) {
      return bluRayLabel ? QualityTier.bluRay : QualityTier.hd;
    }
    if (h >= 720 || bitrateKbps >= 2000) {
      return QualityTier.sd;
    }
    if (h >= 480 || bitrateKbps >= 800) {
      return QualityTier.smooth;
    }
    if (norm.contains('标清')) return QualityTier.sd;
    if (norm.contains('流畅')) return QualityTier.smooth;
    if (norm.contains('高清')) return QualityTier.hd;
    if (bluRayLabel) return QualityTier.bluRay;
    return QualityTier.unknown;
  }

  static String displayLabel(String name, {String sourceConfigName = ''}) {
    if (name.isNotEmpty) return name;
    if (sourceConfigName.isNotEmpty) return sourceConfigName;
    return '未知';
  }

  static String shortBadge(QualityTier tier) => switch (tier) {
        QualityTier.hd => 'HD',
        QualityTier.bluRay => 'BD',
        QualityTier.vip => 'VIP',
        QualityTier.sd => 'SD',
        QualityTier.smooth => 'LD',
        QualityTier.cdn => 'CDN',
        QualityTier.unknown => '',
      };

  /// Standard resolution label from probe dimensions (e.g. 1080P, 720P, 4K).
  static String? resolutionLabel(VideoSource s) {
    final h = s.probeHeight;
    final w = s.probeWidth;
    if (h == null || w == null || h <= 0 || w <= 0) return null;
    if (h >= 2160 || w >= 3840) return '4K';
    if (h >= 1080 || w >= 1920) return '1080P';
    if (h >= 720 || w >= 1280) return '720P';
    if (h >= 480 || w >= 854) return '480P';
    return '${h}P';
  }

  /// Higher rank = sharper stream (used for auto-pick and selector sort).
  static int resolutionRank(VideoSource s) {
    return switch (resolutionLabel(s)) {
      '4K' => 5,
      '1080P' => 4,
      '720P' => 3,
      '480P' => 2,
      final _? => 1,
      null => 0,
    };
  }

  /// UI accent for resolution badges in the line selector.
  static Color resolutionColor(VideoSource s) => switch (resolutionLabel(s)) {
        '4K' => const Color(0xFFFFD700),
        '1080P' => Colors.lightBlueAccent,
        '720P' => Colors.white54,
        '480P' => Colors.white38,
        _ => Colors.white24,
      };

  /// Episode duration as MM:SS from probe or API fallback; null if unknown.
  static String? formatDurationMmSs(VideoSource s) {
    final totalSec = s.probeDurationSec ?? s.apiDurationSec ?? 0;
    if (totalSec <= 0) return null;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  static String _normalize(String raw) => raw.toLowerCase().trim();
}
