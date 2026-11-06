// The links the app sends out. Hosting serves assetlinks.json as it is in the
// repo, so a placeholder there would stop product links opening the app on the
// next deploy; and the download link must stay a redirect, so it can move to
// the Play Store without an app update.
import 'dart:convert';
import 'dart:io';

import 'package:agritrade/services/product_share_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assetlinks.json names the app and a real signing fingerprint', () {
    final links = jsonDecode(File('web/assetlinks.json').readAsStringSync());
    final target = (links as List).single['target'] as Map<String, dynamic>;

    expect(target['package_name'], 'com.example.agritrade');
    final fingerprints = target['sha256_cert_fingerprints'] as List;
    expect(fingerprints, isNotEmpty);
    for (final fingerprint in fingerprints) {
      expect(fingerprint, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
    }
  });

  test('the shared download link is a redirect to the hosted APK', () {
    final config = jsonDecode(File('firebase.json').readAsStringSync());
    final hosting = config['hosting'] as Map<String, dynamic>;
    final redirect = (hosting['redirects'] as List).singleWhere(
      (rule) => rule['source'] == Uri.parse(kAppDownloadUrl).path,
    );

    expect(kAppDownloadUrl, startsWith('$kProductLinkBase/'));
    expect(redirect['destination'], '/downloads/agritrade.apk');
    // Temporary, so a phone never remembers it past the move to the Play Store.
    expect(redirect['type'], 302);
  });

  test(
    'Share AgriTrade+ sends the download page, a web page even with the app',
    () {
      final path = Uri.parse(kAppPageUrl).path;
      expect(kAppPageUrl, startsWith('$kProductLinkBase/'));
      expect(path, '/get/');

      // The page is in web/, which the web build copies to build/web.
      final page = File('web/get/index.html').readAsStringSync();
      // Every download button on it goes to the download link.
      expect(
        RegExp(
          r'href="([^"]*)" data-download',
        ).allMatches(page).map((m) => m.group(1)).toSet(),
        {Uri.parse(kAppDownloadUrl).path},
      );

      // '/get' without the slash shows the page, not the Admin Portal. It is
      // a rewrite: Firebase matches a redirect from '/get' on '/get/' too,
      // so one to '/get/' sends the page to itself without end.
      final config = jsonDecode(File('firebase.json').readAsStringSync());
      final hosting = config['hosting'] as Map;
      expect(
        (hosting['rewrites'] as List).any(
          (r) => r['source'] == '/get' && r['destination'] == '/get/index.html',
        ),
        isTrue,
      );
      expect(
        (hosting['redirects'] as List).any(
          (r) => (r['source'] as String).startsWith('/get'),
        ),
        isFalse,
      );

      // The app opens only /product/ links, so it never takes this one.
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      for (final m in RegExp(
        r'android:pathPrefix="([^"]*)"',
      ).allMatches(manifest)) {
        expect(path.startsWith(m.group(1)!), isFalse);
      }
    },
  );

  test(
    'search engines are pointed at the download page, not the Admin Portal',
    () {
      final page = File('web/get/index.html').readAsStringSync();
      expect(page, contains('<link rel="canonical" href="$kAppPageUrl">'));
      expect(page, isNot(contains('noindex')));

      final sitemap = File('web/sitemap.xml').readAsStringSync();
      expect(sitemap, contains('<loc>$kAppPageUrl</loc>'));
      final robots = File('web/robots.txt').readAsStringSync();
      expect(robots, contains('Sitemap: $kProductLinkBase/sitemap.xml'));

      final admin = File('web/index.html').readAsStringSync();
      expect(
        admin,
        contains('<meta name="robots" content="noindex, nofollow">'),
      );
    },
  );
}
