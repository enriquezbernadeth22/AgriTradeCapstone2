// The Buyer Profile (the user's design, 2026-11-08): the title over the
// farmer-profile cover, the photo in a full gold ring with a pencil, the
// name and area, every option in three white groups, and Log Out outlined
// in dark green.
import 'dart:io';

import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/buyer_profile_screen.dart';
import 'package:agritrade/screen/farmer_storefront_screen.dart';
import 'package:agritrade/services/firebase_refs.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({'tips_off': true});
    // The photo is cached on the phone's disk.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
  });
  tearDown(FirebaseRefs.reset);

  Future<void> open(WidgetTester tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('b1').set({
      'name': 'Junior Pesigan',
      'role': 'buyer',
      'barangay': 'Poblacion',
      'municipality': 'Malvar',
    });
    FirebaseRefs.useForTests(
      firestore: db,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'b1')),
    );
    tester.view.physicalSize = const Size(390, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BuyerProfileScreen(
            onLogout: () {},
            onOpenCompletedOrders: () {},
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the top: the title on the farmer-profile cover, '
      'the photo in a full gold ring with a pencil', (tester) async {
    await open(tester);

    final title = tester.widget<Text>(find.text('Profile'));
    expect(title.style!.fontSize, 21);
    // The title alone: no gold line under it.
    expect(find.byKey(const Key('buyerProfileTitleLine')), findsNothing);

    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ProfileLandscapePainter,
      ),
      findsOneWidget,
    );

    final ring = tester.widget<Container>(
      find.byKey(const Key('profileGoldRing')),
    );
    final border = (ring.decoration! as BoxDecoration).border! as Border;
    expect(border.isUniform, isTrue, reason: 'a full circle, not an arc');
    expect(border.top.color, const Color(0xFFF5BB24));
    expect(
      tester.getSize(find.byKey(const Key('profilePhoto'))),
      const Size.square(84),
    );
    final edit = tester.widget<Container>(find.byKey(const Key('profileEdit')));
    expect((edit.decoration! as BoxDecoration).color, const Color(0xFF0B4225));

    expect(
      tester.widget<Text>(find.text('Junior Pesigan')).style!.fontSize,
      19,
    );
    expect(
      tester.widget<Text>(find.text('Poblacion, Malvar')).style!.fontSize,
      12.5,
    );
  });

  testWidgets('every option stays, and Log Out is outlined in dark green', (
    tester,
  ) async {
    await open(tester);
    for (final label in [
      'My Activity',
      'My Reviews',
      'Liked Products',
      'Purchase History',
      'Preferences & Account',
      'Manage Account',
      'Notification Settings',
      'Appearance',
      'Support & More',
      'Share AgriTrade+',
      'Help & Support',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(tester.widget<Text>(find.text('My Activity')).style!.fontSize, 15);

    final logOut = find.ancestor(
      of: find.text('Log Out'),
      matching: find.byType(Material),
    );
    final shape =
        tester.widget<Material>(logOut.first).shape! as RoundedRectangleBorder;
    expect(shape.side.color, const Color(0xFF0B4225));
    final icon = tester.widget<Icon>(find.byIcon(Icons.logout));
    expect(icon.color, const Color(0xFF0B4225));
  });
}
