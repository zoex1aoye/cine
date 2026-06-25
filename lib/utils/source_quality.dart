/// Quality tier classification for playback sources.
///
/// Labels come from API audit (`source_list_source` / `vip_source_list_source`):
/// - Quality tiers: 高清线路*, 极速蓝光, 高速蓝光, 蓝光线路, VIP线路
/// - CDN mirrors: LZ线路, SN线路, … (ends with 线路, no quality keyword)
/// - Short drama: source_config_name often "常规线路"
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

  static String _normalize(String raw) => raw.toLowerCase().trim();
}
