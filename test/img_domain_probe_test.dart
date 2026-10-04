import 'package:cine/utils/img_domain_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backup success does not wait out a dead primary', () async {
    final started = DateTime.now();
    final picked = await pickImgDomain(
      prefer: 'dead.example',
      domains: const ['dead.example', 'live.example'],
      preferGrace: const Duration(milliseconds: 80),
      probe: (domain) async {
        if (domain == 'dead.example') {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return false;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return true;
      },
    );
    final elapsed = DateTime.now().difference(started);
    expect(picked, 'live.example');
    expect(elapsed.inMilliseconds, lessThan(300));
  });

  test('primary still wins when it succeeds inside the grace window', () async {
    final picked = await pickImgDomain(
      prefer: 'primary.example',
      domains: const ['primary.example', 'backup.example'],
      preferGrace: const Duration(milliseconds: 150),
      probe: (domain) async {
        if (domain == 'backup.example') {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return true;
      },
    );
    expect(picked, 'primary.example');
  });

  test('all probes failing yields null', () async {
    final picked = await pickImgDomain(
      prefer: 'a.example',
      domains: const ['a.example', 'b.example'],
      preferGrace: const Duration(milliseconds: 20),
      probe: (_) async => false,
    );
    expect(picked, isNull);
  });
}
