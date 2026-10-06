import 'dart:async';

/// 图片域竞速。主域和备用域一起探；备用先成功时只再等 [preferGrace]，
/// 不等主域自己的连接超时。
const Duration kImgDomainPreferGrace = Duration(milliseconds: 400);

Future<String?> pickImgDomain({
  required String prefer,
  required List<String> domains,
  required Future<bool> Function(String domain) probe,
  Duration preferGrace = kImgDomainPreferGrace,
}) async {
  final list = <String>[];
  void add(String raw) {
    final domain = raw.trim();
    if (domain.isEmpty || list.contains(domain)) return;
    list.add(domain);
  }

  add(prefer);
  for (final domain in domains) {
    add(domain);
  }
  if (list.isEmpty) return null;

  final completer = Completer<String?>();
  var preferState = list.contains(prefer) ? 'pending' : 'fail';
  String? backupHit;
  var pending = list.length;
  Timer? graceTimer;

  void finish(String? value) {
    if (completer.isCompleted) return;
    graceTimer?.cancel();
    completer.complete(value);
  }

  void onProgress() {
    if (completer.isCompleted) return;
    if (preferState == 'ok') {
      finish(prefer);
      return;
    }
    if (backupHit != null && preferState == 'fail') {
      finish(backupHit);
      return;
    }
    if (backupHit != null && preferState == 'pending' && graceTimer == null) {
      graceTimer = Timer(preferGrace, () {
        if (preferState == 'ok') {
          finish(prefer);
          return;
        }
        finish(backupHit);
      });
    }
    if (pending == 0) finish(backupHit);
  }

  for (final domain in list) {
    probe(domain).then((ok) {
      pending--;
      if (ok) {
        if (domain == prefer) {
          preferState = 'ok';
        } else {
          backupHit ??= domain;
        }
      } else if (domain == prefer) {
        preferState = 'fail';
      }
      onProgress();
    }, onError: (_) {
      pending--;
      if (domain == prefer) preferState = 'fail';
      onProgress();
    });
  }

  return completer.future;
}
