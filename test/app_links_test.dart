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
}
