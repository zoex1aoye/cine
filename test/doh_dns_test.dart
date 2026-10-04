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

  group('DohDns lookup', () {
    test('parallel miss is negative-cached and skips the next DoH round', () async {
      final bootstrap = HttpClient();
      var queries = 0;
      var systemLookups = 0;
      final dns = DohDns(
        bootstrapClient: bootstrap,
        minTtl: const Duration(seconds: 60),
        maxTtl: const Duration(seconds: 600),
        endpoints: [
          DohEndpoint(uri: Uri.parse('https://1.1.1.1/resolve'), typeParam: '1'),
          DohEndpoint(uri: Uri.parse('https://1.0.0.1/resolve'), typeParam: '1'),
        ],
        queryOverride: (_, __) async {
          queries++;
          return DohEndpointResult.miss();
        },
        systemLookup: (_) async {
          systemLookups++;
          throw const SocketException('down');
        },
      );

      await expectLater(
        dns.lookup('dead.example'),
        throwsA(isA<SocketException>()),
      );
      expect(queries, 2);
      expect(systemLookups, 1);

      await expectLater(
        dns.lookup('dead.example'),
        throwsA(isA<SocketException>()),
      );
      expect(queries, 2);
      expect(systemLookups, 1);
      bootstrap.close(force: true);
    });

    test('keeps endpoint order when a later endpoint answers first', () async {
      final bootstrap = HttpClient();
      var systemLookups = 0;
      final dns = DohDns(
        bootstrapClient: bootstrap,
        endpoints: [
          DohEndpoint(uri: Uri.parse('https://1.1.1.1/resolve'), typeParam: '1'),
          DohEndpoint(uri: Uri.parse('https://8.8.8.8/resolve'), typeParam: '1'),
        ],
        queryOverride: (endpoint, _) async {
          if (endpoint.uri.host == '1.1.1.1') {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return DohEndpointResult.hit([InternetAddress('1.2.3.4')]);
          }
          return DohEndpointResult.hit([InternetAddress('9.9.9.9')]);
        },
        systemLookup: (_) async {
          systemLookups++;
          throw const SocketException('down');
        },
      );

      final addrs = await dns.lookup('alive.example');
      expect(addrs.single.address, '1.2.3.4');
      expect(systemLookups, 0);
      bootstrap.close(force: true);
    });

    test('an early hit does not wait for a later endpoint', () async {
      final bootstrap = HttpClient();
      final dns = DohDns(
        bootstrapClient: bootstrap,
        endpoints: [
          DohEndpoint(uri: Uri.parse('https://1.1.1.1/resolve'), typeParam: '1'),
          DohEndpoint(uri: Uri.parse('https://8.8.8.8/resolve'), typeParam: '1'),
        ],
        queryOverride: (endpoint, _) async {
          if (endpoint.uri.host == '8.8.8.8') {
            await Future<void>.delayed(const Duration(seconds: 2));
            return DohEndpointResult.miss();
          }
          return DohEndpointResult.hit([InternetAddress('1.2.3.4')]);
        },
        systemLookup: (_) async => throw const SocketException('down'),
      );
      final started = DateTime.now();
      final addrs = await dns.lookup('fast.example');
      expect(addrs.single.address, '1.2.3.4');
      expect(DateTime.now().difference(started).inMilliseconds, lessThan(500));
      bootstrap.close(force: true);
    });

    test('Status 3 classifies as a definitive miss', () {
      final result = DohDns.classifyDnsJson('{"Status": 3, "Answer": []}');
      expect(result.definitiveMiss, isTrue);
      expect(result.addresses, isEmpty);
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
