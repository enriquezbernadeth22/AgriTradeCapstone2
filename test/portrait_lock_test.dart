// The mobile app stays upright when the phone is turned: its screens are laid
// out for portrait (in landscape the chat overflowed). The lock is in the
// app and in the Android and iPhone settings, so it holds from launch.
import 'dart:io';

import 'package:agritrade/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the app allows upright only', () {
    expect(kAppOrientations, [DeviceOrientation.portraitUp]);
  });

  test('Android opens the app upright', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final mainActivity = RegExp(
      r'<activity\s+android:name="\.MainActivity"[^>]*>',
    ).firstMatch(manifest)!.group(0)!;
    expect(mainActivity, contains('android:screenOrientation="portrait"'));
  });

  test('an iPhone opens the app upright', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final iphone = RegExp(
      r'<key>UISupportedInterfaceOrientations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist)!.group(1)!;
    expect(iphone, contains('UIInterfaceOrientationPortrait'));
    expect(iphone, isNot(contains('Landscape')));
  });
}
