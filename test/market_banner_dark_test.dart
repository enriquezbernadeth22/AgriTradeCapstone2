// The Market's welcome banner is a picture with its cream curve drawn in:
// in Dark Mode it shows its own copy with the curve forest green, and the
// text on it turns light (the user, 2026-11-08).
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/market_tab.dart';
import 'package:agritrade/services/firebase_refs.dart';
import 'package:agritrade/theme/app_colors.dart';
import 'package:agritrade/theme/app_theme.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({'tips_off': true});
  });
  tearDown(() {
    AppColors.isDark = false;
    FirebaseRefs.reset();
  });

  Future<void> open(WidgetTester tester, {required bool dark}) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('f1').set({
      'name': 'Daniella Claveria',
      'role': 'farmer',
      'approvalStatus': 'approved',
    });
    FirebaseRefs.useForTests(
      firestore: db,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'f1')),
    );
    AppColors.isDark = dark;
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: MarketTab()),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The marketplace cards reach past FirebaseRefs; not what is checked.
    tester.takeException();
  }

  String bannerAsset(WidgetTester tester) {
    final box = tester.widget<Container>(
      find.byKey(const Key('marketWelcomeBanner')),
    );
    final image = (box.decoration! as BoxDecoration).image!.image;
    return (image as AssetImage).assetName;
  }

  testWidgets('light: the original picture, dark text', (tester) async {
    await open(tester, dark: false);
    expect(bannerAsset(tester), 'assets/images/market_farmer.png');
    expect(
      tester.widget<Text>(find.text('Daniella')).style!.color,
      const Color(0xFF173D21),
    );
  });

  testWidgets('dark: the forest-green copy, white name', (tester) async {
    await open(tester, dark: true);
    expect(bannerAsset(tester), 'assets/images/market_farmer_dark.png');
    expect(
      tester.widget<Text>(find.text('Daniella')).style!.color,
      Colors.white,
    );
  });

  test('headings: dark green in light, soft white in dark', () {
    expect(AppColors.heading, AppTheme.dark);
    AppColors.isDark = true;
    expect(AppColors.heading, const Color(0xFFF4F6F2));
  });
}
