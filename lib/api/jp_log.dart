import 'dart:developer' as dev;

void jpLog(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  final line = '[$ts] [$tag] $msg';
  dev.log(line, name: 'jianpian');
  // Also print to stderr
  // ignore: avoid_print
  print('🎬 $line');
}
