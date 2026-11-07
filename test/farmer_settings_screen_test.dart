// The Farmer's Settings: a page of its own (from the gear beside the
// Profile title), its rows in three groups, a chevron only on rows that
// open a screen, and a soft red Log Out at the bottom. About AgriTrade+
// shows only the app's own facts.
import 'package:agritrade/data/legal_policies.dart';
import 'package:agritrade/data/mobile_faqs.dart';
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/about_screen.dart';
import 'package:agritrade/screen/farmer_settings_screen.dart';
import 'package:agritrade/services/product_share_service.dart';
import 'package:agritrade/theme/app_colors.dart';
import 'package:agritrade/theme/app_theme.dart';
import 'package:agritrade/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // What reached the phone's share sheet.
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  List<Map<dynamic, dynamic>> listenForShares(
    WidgetTester tester, {
    bool fails = false,
  }) {
    final shared = <Map<dynamic, dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      (call) async {
        if (fails) throw PlatformException(code: 'no_share_sheet');
        shared.add(call.arguments as Map<dynamic, dynamic>);
        return 'dev.fluttercommunity.plus/share/success';
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        null,
      ),
    );
    return shared;
  }

  // A stand-in Profile page, whose button opens Settings like the gear.
  Future<void> open(
    WidgetTester tester, {
    VoidCallback? logout,
    Size size = const Size(400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        FarmerSettingsScreen(onLogout: logout ?? () {}),
                  ),
                ),
                child: const Text('Profile'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
  }

  double topOf(WidgetTester tester, String label) =>
      tester.getTopLeft(find.text(label)).dy;

  testWidgets('a full page titled Settings, its rows in three groups', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Settings'), findsOneWidget);
    final order = [
      'ACCOUNT & SECURITY',
      'Manage Account',
      'Privacy & Security',
      'PREFERENCES',
      'Notification Settings',
      'Dark Mode',
      'SUPPORT & INFORMATION',
      'Send Feedback',
      'Help & Support',
      'About AgriTrade+',
      'Share AgriTrade+',
      'Log Out',
    ];
    final tops = [for (final label in order) topOf(tester, label)];
    expect(tops, orderedEquals([...tops]..sort()));
    // English only: no Language row.
    expect(find.text('Language'), findsNothing);
  });

  testWidgets('a chevron only on rows that open another screen', (
    tester,
  ) async {
    await open(tester);
    Finder chevronOn(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
      matching: find.byIcon(Icons.chevron_right_rounded),
    );
    for (final label in [
      'Manage Account',
      'Privacy & Security',
      'Notification Settings',
      'Help & Support',
      'About AgriTrade+',
    ]) {
      expect(chevronOn(label), findsOneWidget, reason: label);
    }
    for (final label in ['Send Feedback', 'Share AgriTrade+', 'Dark Mode']) {
      expect(chevronOn(label), findsNothing, reason: label);
    }
  });

  testWidgets('Dark Mode flips from its row, the switch on the right', (
    tester,
  ) async {
    await ThemeController.instance.setDark(false);
    await open(tester);
    final sw = find.byType(Switch);
    expect(
      tester.getCenter(sw).dx,
      greaterThan(tester.getCenter(find.text('Dark Mode')).dx),
    );
    await tester.tap(find.text('Dark Mode'));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue);
    expect(tester.widget<Switch>(sw).value, isTrue);
    await ThemeController.instance.setDark(false);
    await tester.pumpAndSettle();
  });

  testWidgets('Share AgriTrade+ sends the download page link, never a file', (
    tester,
  ) async {
    final shared = listenForShares(tester);
    await open(tester);
    await tester.tap(find.text('Share AgriTrade+'));
    await tester.pumpAndSettle();
    final message = shared.single;
    expect(message['text'], contains(kAppPageUrl));
    expect(message.containsKey('paths'), isFalse);
  });

  testWidgets('it says so when the share sheet cannot open', (tester) async {
    listenForShares(tester, fails: true);
    await open(tester);
    await tester.tap(find.text('Share AgriTrade+'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open sharing. Try again.'), findsOneWidget);
  });

  testWidgets('Log Out is a full-width soft red button at the bottom', (
    tester,
  ) async {
    var loggedOut = 0;
    await open(tester, logout: () => loggedOut++);
    final button = find
        .ancestor(of: find.text('Log Out'), matching: find.byType(Material))
        .first;
    final shape =
        tester.widget<Material>(button).shape! as RoundedRectangleBorder;
    expect(shape.side.color.a, greaterThan(0));
    expect(shape.borderRadius, BorderRadius.circular(AppTheme.buttonRadius));
    expect(tester.getSize(button).width, greaterThan(300));
    expect(
      topOf(tester, 'Log Out'),
      greaterThan(topOf(tester, 'Share AgriTrade+')),
    );
    await tester.tap(find.text('Log Out'));
    expect(loggedOut, 1);
  });

  testWidgets('Back returns to Profile', (tester) async {
    await open(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(FarmerSettingsScreen), findsNothing);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('a short phone scrolls to Log Out', (tester) async {
    await open(tester, size: const Size(360, 520));
    await tester.scrollUntilVisible(find.text('Log Out'), 200);
    expect(find.text('Log Out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('About AgriTrade+ shows the real version, team and policies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: AboutScreen(version: Future.value('1.0.0'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Version 1.0.0'), findsOneWidget);
    expect(find.text('The AgriTrade+ team'), findsOneWidget);
    expect(find.text(kSupportEmail), findsOneWidget);
    expect(find.text(kAppPageUrl), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms & Conditions'), findsOneWidget);
    expect(find.text('Effective $kPolicyEffectiveDate'), findsOneWidget);
  });

  testWidgets('About shows no version when it cannot be read', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AboutScreen(version: Future.value(null))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Version '), findsNothing);
  });
}
