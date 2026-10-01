/// 封面 CDN：URL 拼装、候选域去重置首、换域步进。
library;

const kHardcodedImgDomainBackups = <String>[
  'static2.gutaike.com',
  'static.shaxyt.com',
];

const _legacyBrokenImgHost = 'bqxqqqnf.top';
const _legacyImgHostRewrite = 'static2.gutaike.com';

String normalizeImgDomain(String domain) {
  final t = domain.trim();
  if (t.isEmpty) return '';
  if (t == _legacyBrokenImgHost) return _legacyImgHostRewrite;
  return t;
}

/// 合并候选：主域置首，再 package 列表，再硬编码；去重并改写劣质 host。
List<String> mergeImgDomainCandidates({
  required String primary,
  List<String> fromPackage = const [],
  List<String> hardcoded = kHardcodedImgDomainBackups,
}) {
  final out = <String>[];
  void add(String raw) {
    final n = normalizeImgDomain(raw);
    if (n.isEmpty) return;
    if (!out.contains(n)) out.add(n);
  }

  add(primary);
  for (final s in fromPackage) {
    add(s);
  }
  for (final s in hardcoded) {
    add(s);
  }
  return out;
}

bool _isAbsoluteUrl(String path) =>
    path.startsWith('http://') || path.startsWith('https://');

/// 与现网一致：相对路径挂 [imgDomain]；绝对 URL 仅改写 `bqxqqqnf.top`。
String buildCoverUrl(String coverPath, String imgDomain) {
  if (coverPath.isEmpty) return '';
  if (_isAbsoluteUrl(coverPath)) {
    return coverPath.replaceAll(_legacyBrokenImgHost, _legacyImgHostRewrite);
  }
  final domain = normalizeImgDomain(imgDomain);
  if (domain.isEmpty) return '';
  final path = coverPath.startsWith('/') ? coverPath : '/$coverPath';
  return 'https://$domain$path';
}

/// 换域用：强制把封面挂到 [domain]（相对拼域；绝对只换 host，保留 path/query）。
String buildCoverUrlOnDomain(String coverPath, String domain) {
  if (coverPath.isEmpty) return '';
  final host = normalizeImgDomain(domain);
  if (host.isEmpty) return '';

  if (_isAbsoluteUrl(coverPath)) {
    final rewritten =
        coverPath.replaceAll(_legacyBrokenImgHost, _legacyImgHostRewrite);
    final uri = Uri.tryParse(rewritten);
    if (uri == null || uri.host.isEmpty) return '';
    return uri.replace(host: host).toString();
  }

  final path = coverPath.startsWith('/') ? coverPath : '/$coverPath';
  return 'https://$host$path';
}

/// 从 [afterIndex] 之后取下一个可用候选；[afterIndex] 传 -1 表示从 0 开始。
({String url, String domain, int index})? nextCoverCandidate({
  required String coverPath,
  required List<String> candidates,
  int afterIndex = -1,
}) {
  if (coverPath.isEmpty) return null;
  for (var i = afterIndex + 1; i < candidates.length; i++) {
    final url = buildCoverUrlOnDomain(coverPath, candidates[i]);
    if (url.isNotEmpty) {
      return (url: url, domain: candidates[i], index: i);
    }
  }
  return null;
}
