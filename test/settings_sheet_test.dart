// The Settings sheet behind the header's gear: the same rows for everyone,
// in four groups, with Log Out in red, and Share AgriTrade+ sending a message
// and a link through the phone's share sheet.
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/services/product_share_service.dart';
import 'package:agritrade/theme/app_colors.dart';
import 'package:agritrade/theme/app_theme.dart';
import 'package:agritrade/theme/theme_controller.dart';
import 'package:agritrade/widgets/agri_dialog.dart';
import 'package:agritrade/widgets/settings_sheet.dart';
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

  Future<void> open(
    WidgetTester tester, {
    VoidCallback? help,
    VoidCallback? logout,
    Size size = const Size(400, 800),
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
                onPressed: () => showSettingsSheet(
                  context,
                  onHelp: help ?? () {},
                  onLogout: logout ?? () {},
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  double topOf(WidgetTester tester, String label) =>
      tester.getTopLeft(find.text(label)).dy;

  testWidgets('every row is there, in order', (tester) async {
    await open(tester);
    final order = [
      'Share AgriTrade+',
      'Notification Settings',
      'Dark Mode',
      'Manage Account',
      'Send Feedback',
      'Help & Support',
      'Log Out',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        topOf(tester, order[i - 1]),
        lessThan(topOf(tester, order[i])),
        reason: '${order[i - 1]} comes before ${order[i]}',
      );
    }
  });

  testWidgets('Share My Store is not offered for now', (tester) async {
    await open(tester);
    expect(find.text('Share My Store'), findsNothing);
  });

  testWidgets('Share AgriTrade+ sends a message and the link, never a file', (
    tester,
  ) async {
    final shared = listenForShares(tester);
    await open(tester);

    await tester.tap(find.text('Share AgriTrade+'));
    await tester.pumpAndSettle();

    expect(find.text('Manage Account'), findsNothing);
    final message = shared.single;
    expect(message['text'], contains(kAppPageUrl));
    expect(message['text'], contains('AgriTrade+'));
    expect(message['subject'], 'AgriTrade+');
    expect(message.containsKey('paths'), isFalse);
  });

  testWidgets('it says so when the share sheet cannot open', (tester) async {
    listenForShares(tester, fails: true);
    await open(tester);

    await tester.tap(find.text('Share AgriTrade+'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open sharing. Try again.'), findsOneWidget);
  });

  testWidgets('every row is 50 tall, with lines only between the groups', (
    tester,
  ) async {
    await open(tester);
    for (final label in ['Share AgriTrade+', 'Dark Mode']) {
      final row = find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(row).height, 50, reason: label);
    }
    expect(find.byType(Divider), findsNWidgets(3));
  });

  testWidgets('the sheet has rounded top corners over a dimmed page', (
    tester,
  ) async {
    await open(tester);
    final surface = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(surface.color, AppColors.surface);
    final corners =
        (surface.shape! as RoundedRectangleBorder).borderRadius as BorderRadius;
    expect(corners.topLeft, const Radius.circular(20));
    expect(corners.bottomLeft, Radius.zero);
    final barrier = tester.widget<ModalBarrier>(find.byType(ModalBarrier).last);
    expect(barrier.color, agriBarrierColor);
  });

  testWidgets('Dark Mode flips from the row, with the sheet still open', (
    tester,
  ) async {
    addTearDown(() async {
      ThemeController.instance.value = AppearanceMode.light;
      AppColors.isDark = false;
    });
    await open(tester);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.text('Dark Mode'));
    await tester.pumpAndSettle();

    expect(AppColors.isDark, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('Log Out'), findsOneWidget);
  });

  testWidgets('the app is English only: Settings has no Language row', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Language'), findsNothing);
  });

  testWidgets('Log Out is a soft red button that closes the sheet first', (
    tester,
  ) async {
    var loggedOut = false;
    await open(tester, logout: () => loggedOut = true);
    final red = AppColors.tone(Colors.red, 700);
    final label = tester.widget<Text>(find.text('Log Out'));
    expect(label.style?.color, red);

    final button = tester.widget<Material>(
      find
          .ancestor(of: find.text('Log Out'), matching: find.byType(Material))
          .first,
    );
    expect(button.color, AppColors.tone(Colors.red, 50));
    final shape = button.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(14));
    expect(shape.side.color, red.withValues(alpha: 0.55));

    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();

    expect(loggedOut, isTrue);
    expect(find.text('Manage Account'), findsNothing);
  });

  testWidgets('Help & Support is the role\'s own', (tester) async {
    var helped = false;
    await open(tester, help: () => helped = true);
    await tester.tap(find.text('Help & Support'));
    await tester.pumpAndSettle();
    expect(helped, isTrue);
  });

  testWidgets('tapping the dimmed page closes it without doing anything', (
    tester,
  ) async {
    var loggedOut = false;
    await open(tester, logout: () => loggedOut = true);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.text('Manage Account'), findsNothing);
    expect(loggedOut, isFalse);
  });

  testWidgets('a short phone scrolls to Log Out', (tester) async {
    var loggedOut = false;
    await open(
      tester,
      logout: () => loggedOut = true,
      size: const Size(320, 400),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Log Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();
    expect(loggedOut, isTrue);
  });
}
