// The Profile tab's gear menu: Share My Store for farmers only;
// Notification Settings, Manage Account, Send Feedback, Help & Support and
// Log Out for everyone.
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/widgets/profile_settings_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> open(
    WidgetTester tester, {
    VoidCallback? share,
    VoidCallback? logout,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: ProfileSettingsMenu(
              onShareStore: share,
              onHelp: () {},
              onLogout: logout ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
  }

  testWidgets('a farmer can share their store', (tester) async {
    await open(tester, share: () {});
    expect(find.text('Share My Store'), findsOneWidget);
    expect(find.text('Manage Account'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
  });

  testWidgets('without a store to share, that item is left out', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Share My Store'), findsNothing);
    expect(find.text('Notification Settings'), findsOneWidget);
    expect(find.text('Manage Account'), findsOneWidget);
    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
  });

  testWidgets('Send Feedback is on the menu', (tester) async {
    await open(tester, share: () {});
    expect(find.text('Send Feedback'), findsOneWidget);
  });

  testWidgets('choosing Log Out closes the panel and logs out', (tester) async {
    var loggedOut = false;
    await open(tester, logout: () => loggedOut = true);
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();
    expect(loggedOut, isTrue);
    expect(find.text('Manage Account'), findsNothing);
  });
}
