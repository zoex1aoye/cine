import 'dart:math';

import 'package:cine/api/jp_domain_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JpDomainDiscovery', () {
    test('isBadRoot flags ipixiv and release', () {
      expect(JpDomainDiscovery.isBadRoot('api.ipixiv.com'), isTrue);
      expect(JpDomainDiscovery.isBadRoot('release.ipixiv.com'), isTrue);
      expect(JpDomainDiscovery.isBadRoot('https://api.ipixiv.com/api'), isTrue);
      expect(JpDomainDiscovery.isBadRoot('japi.zxfmj.com'), isFalse);
      expect(JpDomainDiscovery.isBadRoot('hzhnl.com'), isFalse);
    });

    test('rootFromLegacyBaseUrl parses host', () {
      expect(
        JpDomainDiscovery.rootFromLegacyBaseUrl('https://japi.zxfmj.com/api'),
        'japi.zxfmj.com',
      );
      expect(
        JpDomainDiscovery.rootFromLegacyBaseUrl('https://api.ipixiv.com/api'),
        'api.ipixiv.com',
      );
      expect(JpDomainDiscovery.rootFromLegacyBaseUrl(null), isNull);
    });

    test('buildApiBaseUrl uses plain japi and random subdomain otherwise', () {
      final d = JpDomainDiscovery(random: Random(42));
      expect(d.buildApiBaseUrl('japi.zxfmj.com'), 'https://japi.zxfmj.com/api');
      final url = d.buildApiBaseUrl('hzhnl.com');
      expect(url.startsWith('https://'), isTrue);
      expect(url.endsWith('.hzhnl.com/api'), isTrue);
      final host = Uri.parse(url).host;
      expect(host.split('.').first.length, 6);
    });
  });
}
