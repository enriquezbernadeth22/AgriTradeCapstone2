// Manage Account: one plain list without duplicates (Notification
// Settings and Help & Support live in the Settings sheet), no dark mode and
// no language switch — the app is English only.
import 'package:agritrade/screen/manage_account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('no duplicates, no dark mode, no language switch', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'AgriTrade+',
      packageName: 'agritrade',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: ManageAccountScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Manage Account'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    // The recovery email is in Edit Profile, under Personal Information.
    expect(find.text('Recovery Email'), findsNothing);
    expect(find.textContaining('Notification'), findsNothing);
    expect(find.text('Help & Support'), findsNothing);
    expect(find.textContaining('Dark mode'), findsNothing);
    expect(find.textContaining('Language'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  // The Farmer's Settings has Manage Account and Privacy & Security as
  // rows of their own: each opens its own part, so nothing is shown twice.
  testWidgets('the Farmer\x27s Manage Account is the account part only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ManageAccountScreen(part: ManageAccountPart.account)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Manage Account'), findsOneWidget);
    expect(find.text('Personal Information'), findsOneWidget);
    // One row for the profile: no separate Recovery Email.
    expect(find.text('Recovery Email'), findsNothing);
    expect(
      find.text('Name, photo, contact details and recovery email'),
      findsOneWidget,
    );
    expect(find.text('Change Password'), findsNothing);
    expect(find.text('Devices & Login Activity'), findsNothing);
    expect(find.text('Privacy Policy'), findsNothing);
  });

  testWidgets('Privacy & Security is the security part only', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ManageAccountScreen(part: ManageAccountPart.security),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Privacy & Security'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Devices & Login Activity'), findsOneWidget);
    expect(find.text('Personal Information'), findsNothing);
    expect(find.text('Recovery Email'), findsNothing);
    expect(find.text('Privacy Policy'), findsNothing);
  });
}
