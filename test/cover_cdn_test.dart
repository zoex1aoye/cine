import 'dart:io';

import 'package:cine/utils/cover_cdn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergeImgDomainCandidates', () {
    test('primary first, package then hardcoded, dedupe', () {
      final list = mergeImgDomainCandidates(
        primary: 'static.bjynj.com',
        fromPackage: [
          'static.hzkqw.com',
          'static.bjynj.com',
          'static2.gutaike.com',
        ],
      );
      expect(list.first, 'static.bjynj.com');
      expect(list, [
        'static.bjynj.com',
        'static.hzkqw.com',
        'static2.gutaike.com',
        'static.shaxyt.com',
      ]);
    });

    test('rewrites legacy broken host and skips empties', () {
      final list = mergeImgDomainCandidates(
        primary: 'bqxqqqnf.top',
        fromPackage: ['', ' static.hzkqw.com '],
        hardcoded: const ['static2.gutaike.com'],
      );
      expect(list, ['static2.gutaike.com', 'static.hzkqw.com']);
    });

    test('empty primary still keeps package + hardcoded', () {
      final list = mergeImgDomainCandidates(
        primary: '',
        fromPackage: ['static.hzkqw.com'],
      );
      expect(list.first, 'static.hzkqw.com');
      expect(list, contains('static2.gutaike.com'));
    });
  });

  group('buildCoverUrl', () {
    test('relative path uses imgDomain', () {
      expect(
        buildCoverUrl('/upload/a.jpg', 'static.bjynj.com'),
        'https://static.bjynj.com/upload/a.jpg',
      );
    });

    test('absolute path only rewrites legacy host', () {
      expect(
        buildCoverUrl('https://bqxqqqnf.top/upload/a.jpg', 'static.bjynj.com'),
        'https://static2.gutaike.com/upload/a.jpg',
      );
    });

    test('empty path returns empty', () {
      expect(buildCoverUrl('', 'static.bjynj.com'), '');
    });
  });

  group('buildCoverUrlOnDomain', () {
    test('relative hangs on given domain', () {
      expect(
        buildCoverUrlOnDomain('/upload/a.jpg', 'static.hzkqw.com'),
        'https://static.hzkqw.com/upload/a.jpg',
      );
    });

    test('absolute replaces host only', () {
      expect(
        buildCoverUrlOnDomain(
          'https://static.bjynj.com/upload/a.jpg?x=1',
          'static.hzkqw.com',
        ),
        'https://static.hzkqw.com/upload/a.jpg?x=1',
      );
    });
  });

  group('nextCoverCandidate', () {
    test('walks candidates after index', () {
      const path = '/upload/a.jpg';
      final candidates = ['a.com', 'b.com', 'c.com'];
      final first = nextCoverCandidate(
        coverPath: path,
        candidates: candidates,
        afterIndex: -1,
      );
      expect(first?.domain, 'a.com');
      expect(first?.index, 0);

      final second = nextCoverCandidate(
        coverPath: path,
        candidates: candidates,
        afterIndex: first!.index,
      );
      expect(second?.domain, 'b.com');
      expect(second?.url, 'https://b.com/upload/a.jpg');
    });

    test('404 does not blacklist a domain, 403 and DNS do', () {
      expect(
        coverFailureMarksDomainDead(
          Exception('NetworkImageLoadException: HTTP request failed, statusCode: 404'),
        ),
        isFalse,
      );
      expect(
        coverFailureMarksDomainDead(
          Exception('NetworkImageLoadException: HTTP request failed, statusCode: 403'),
        ),
        isTrue,
      );
      expect(
        coverFailureMarksDomainDead(
          const SocketException("Failed host lookup: 'static.example'"),
        ),
        isTrue,
      );
      expect(
        imageProbeAccepts(statusCode: 200, mimeType: 'image/jpeg'),
        isTrue,
      );
      expect(
        imageProbeAccepts(statusCode: 200, mimeType: 'application/xml'),
        isFalse,
      );
      expect(imageProbeAccepts(statusCode: 200, mimeType: null), isTrue);
      expect(imageProbeAccepts(statusCode: 403, mimeType: 'image/jpeg'), isFalse);
    });

    test('empty path yields null', () {
      expect(
        nextCoverCandidate(
          coverPath: '',
          candidates: ['a.com'],
        ),
        isNull,
      );
    });
  });

  group('CoverCdnSignals', () {
    test('域名变化才通知，相同签名不重复', () {
      CoverCdnSignals.debugReset();
      var ticks = 0;
      void onTick() => ticks++;
      CoverCdnSignals.epoch.addListener(onTick);
      addTearDown(() => CoverCdnSignals.epoch.removeListener(onTick));

      CoverCdnSignals.publish('a.com', ['a.com']);
      CoverCdnSignals.publish('a.com', ['a.com']);
      CoverCdnSignals.publish('b.com', ['b.com', 'a.com']);
      expect(ticks, 2);
    });
  });
}
