import 'package:http/http.dart' as http;

import 'source_quality.dart';

/// Result of a two-phase stream probe (availability + M3U8 analysis).
class StreamProbeResult {
  final bool success;
  final int latencyMs;
  final int width;
  final int height;
  final int bitrateKbps;
  final int firstFrameMs;
  final QualityTier effectiveTier;

  const StreamProbeResult({
    required this.success,
    this.latencyMs = 999999,
    this.width = 0,
    this.height = 0,
    this.bitrateKbps = 0,
    this.firstFrameMs = 0,
    this.effectiveTier = QualityTier.unknown,
  });

  static const failed = StreamProbeResult(success: false);
}

/// Lightweight availability + HLS stream metadata probe.
abstract final class StreamProbe {
  static const _probeTimeout = Duration(seconds: 6);
  static const _availTimeout = Duration(seconds: 4);

  /// Phase 1: HEAD + small Range fetch; rejects HTML/non-video.
  static Future<bool> checkAvailability(String url, http.Client client) async {
    try {
      final uri = Uri.parse(url);
      final head = await client.head(uri).timeout(_availTimeout);
      final headOk = head.statusCode == 200 ||
          head.statusCode == 302 ||
          head.statusCode == 301;
      if (!headOk) return false;

      final getResp = await client
          .get(uri, headers: {'Range': 'bytes=0-8191'})
          .timeout(const Duration(seconds: 5));
      final body = getResp.bodyBytes;
      if (body.length <= 100) return false;
      if (getResp.statusCode != 200 && getResp.statusCode != 206) return false;
      return !_looksLikeHtml(body);
    } catch (_) {
      return false;
    }
  }

  /// Phase 2: parse M3U8, sample first segment, derive tier metrics.
  static Future<StreamProbeResult> probe(
    String playlistUrl,
    http.Client client, {
    String label = '',
    Duration timeout = _probeTimeout,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final playlistUri = Uri.parse(playlistUrl);
      final playlistResp =
          await client.get(playlistUri).timeout(timeout);
      if (playlistResp.statusCode != 200) return StreamProbeResult.failed;

      final playlistLatency = sw.elapsedMilliseconds;
      final body = playlistResp.body;
      if (body.isEmpty || _looksLikeHtml(playlistResp.bodyBytes)) {
        return StreamProbeResult.failed;
      }

      var width = 0;
      var height = 0;
      var bitrateKbps = 0;
      String? segmentUrl;

      if (isMasterPlaylist(body)) {
        final variant = pickBestVariant(body, playlistUri);
        if (variant == null) return StreamProbeResult.failed;
        bitrateKbps = variant.key ~/ 1000;
        final mediaResp = await client.get(variant.value).timeout(timeout);
        if (mediaResp.statusCode != 200) return StreamProbeResult.failed;
        final resolution = parseResolutionFromInf(body) ??
            parseResolutionFromInf(mediaResp.body);
        if (resolution != null) {
          width = resolution.$1;
          height = resolution.$2;
        }
        segmentUrl = firstSegmentUrl(mediaResp.body, variant.value)?.toString();
        if (bitrateKbps == 0) {
          bitrateKbps = (parseBandwidthFromInf(mediaResp.body) ?? 0) ~/ 1000;
        }
      } else {
        final resolution = parseResolutionFromInf(body);
        if (resolution != null) {
          width = resolution.$1;
          height = resolution.$2;
        }
        bitrateKbps = (parseBandwidthFromInf(body) ?? 0) ~/ 1000;
        segmentUrl = firstSegmentUrl(body, playlistUri)?.toString();
      }

      var firstFrameMs = 0;
      if (segmentUrl != null && segmentUrl.isNotEmpty) {
        final segSw = Stopwatch()..start();
        final segResp = await client
            .get(
              Uri.parse(segmentUrl),
              headers: {'Range': 'bytes=0-262143'},
            )
            .timeout(timeout);
        segSw.stop();
        if (segResp.statusCode == 200 || segResp.statusCode == 206) {
          firstFrameMs = segSw.elapsedMilliseconds;
          if (segResp.bodyBytes.length > 100) {
            // keep firstFrameMs
          }
        }
      }

      sw.stop();
      final tier = SourceQuality.tierFromProbe(
        width,
        height,
        bitrateKbps,
        label: label,
      );

      return StreamProbeResult(
        success: true,
        latencyMs: playlistLatency,
        width: width,
        height: height,
        bitrateKbps: bitrateKbps,
        firstFrameMs: firstFrameMs,
        effectiveTier: tier,
      );
    } catch (_) {
      return StreamProbeResult.failed;
    }
  }

  static bool isMasterPlaylist(String content) =>
      content.contains('#EXT-X-STREAM-INF');

  /// Returns (bandwidth, media playlist URI) for highest-bandwidth variant.
  static MapEntry<int, Uri>? pickBestVariant(String masterContent, Uri baseUri) {
    final lines = masterContent.split('\n');
    var bestBw = -1;
    Uri? bestUri;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final bw = _attrInt(line, 'BANDWIDTH') ?? 0;
      Uri? mediaUri;
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j].trim();
        if (next.isEmpty || next.startsWith('#')) continue;
        mediaUri = baseUri.resolve(next);
        break;
      }
      if (mediaUri == null) continue;
      if (bw > bestBw) {
        bestBw = bw;
        bestUri = mediaUri;
      }
    }
    if (bestUri == null) return null;
    return MapEntry(bestBw > 0 ? bestBw : 0, bestUri);
  }

  static Uri? firstSegmentUrl(String mediaContent, Uri baseUri) {
    final lines = mediaContent.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].trim().startsWith('#EXTINF')) continue;
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j].trim();
        if (next.isEmpty || next.startsWith('#')) continue;
        return baseUri.resolve(next);
      }
    }
    return null;
  }

  static (int, int)? parseResolutionFromInf(String content) {
    final match = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(content);
    if (match == null) return null;
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  static int? parseBandwidthFromInf(String content) {
    return _attrInt(content, 'BANDWIDTH');
  }

  static int? _attrInt(String line, String key) {
    final match = RegExp('$key=(\\d+)').firstMatch(line);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  static bool _looksLikeHtml(List<int> bytes) {
    final head = String.fromCharCodes(bytes.take(200));
    return head.contains('<html') ||
        head.contains('<HTML') ||
        head.contains('<!DOCTYPE');
  }
}

/// Hive cache key for a distinct line within one video.
abstract final class SourceProbeKeys {
  static String lineKey(int videoId, String lineName) => '$videoId|$lineName';
}
