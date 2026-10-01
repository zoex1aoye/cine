import 'dart:io';

import 'package:cine/api/doh_dns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DohDns.parseDnsJson', () {
    test('extracts A records and prefers IPv4 order', () {
      const body = '''
{
  "Status": 0,
  "Answer": [
    {"name": "japi.zxfmj.com.", "type": 5, "TTL": 30, "data": "all.example.com."},
    {"name": "all.example.com.", "type": 28, "TTL": 60, "data": "2001:db8::1"},
    {"name": "all.example.com.", "type": 1, "TTL": 45, "data": "1.2.3.4"}
  ]
}
''';
      final r = DohDns.parseDnsJson(body);
      expect(r.addrs.length, 2);
      expect(r.addrs.first.type, InternetAddressType.IPv4);
      expect(r.addrs.first.address, '1.2.3.4');
      expect(r.ttl, const Duration(seconds: 45));
    });

    test('non-zero Status throws', () {
      expect(
        () => DohDns.parseDnsJson('{"Status": 3, "Answer": []}'),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('DohDns TTL clamp', () {
    test('clamps to min/max', () {
      final bootstrap = HttpClient();
      final dns = DohDns(
        bootstrapClient: bootstrap,
        minTtl: const Duration(seconds: 60),
        maxTtl: const Duration(seconds: 600),
      );
      expect(dns.clampTtlForTest(const Duration(seconds: 10)).inSeconds, 60);
      expect(dns.clampTtlForTest(const Duration(seconds: 120)).inSeconds, 120);
      expect(dns.clampTtlForTest(const Duration(seconds: 9999)).inSeconds, 600);
      bootstrap.close(force: true);
    });
  });
}
