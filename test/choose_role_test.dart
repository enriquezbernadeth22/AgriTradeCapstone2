// Creating an account starts by choosing Buyer or Farmer, each card with its
// own person from one picture. The chosen card is marked and opens the form
// for that role, and the form has no role toggle of its own. A new Google
// account comes here too, and its cards open the short Google profile form.
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/choose_role_screen.dart';
import 'package:agritrade/screen/google_complete_profile_screen.dart';
import 'package:agritrade/screen/register_screen.dart';
import 'package:agritrade/services/auth_service.dart';
import 'package:agritrade/theme/app_colors.dart';
import 'package:agritrade/widgets/agri_app_bar.dart';
import 'package:agritrade/widgets/agritrade_text.dart';
import 'package:agritrade/widgets/role_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  // From a stand-in for the log-in page, as the app gets here.
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(600, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChooseRoleScreen()),
              ),
              child: const Text('Log-in page'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Log-in page'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String card) async {
    await tester.tap(find.text(card));
    await tester.pumpAndSettle();
  }

  testWidgets('asks how the app will be used, with two cards side by side', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('How will you use AgriTrade+?'), findsOneWidget);
    expect(find.text('Choose the option that best fits you.'), findsOneWidget);
    expect(find.text('I want to buy agricultural products.'), findsOneWidget);
    expect(
      find.text('I want to sell my agricultural products.'),
      findsOneWidget,
    );

    final buyer = tester.getCenter(find.text('I\'m a Buyer'));
    final farmer = tester.getCenter(find.text('I\'m a Farmer'));
    expect(buyer.dx, lessThan(farmer.dx));
    expect(buyer.dy, farmer.dy);
  });

  testWidgets('the logo and name are at the left, beside Back', (tester) async {
    await open(tester);
    final bar = find.byType(AgriAppBar);
    final back = find.descendant(of: bar, matching: find.byType(IconButton));
    final logo = find.descendant(
      of: bar,
      matching: find.byType(AgriTradeLogoMark),
    );
    final name = find.descendant(of: bar, matching: find.byType(AgriTradeText));
    expect(tester.getTopLeft(back).dx, lessThan(tester.getTopLeft(logo).dx));
    expect(tester.getTopLeft(logo).dx, lessThan(tester.getTopLeft(name).dx));
    expect(tester.getTopRight(name).dx, lessThan(600 / 2));
  });

  BoxDecoration lookOf(WidgetTester tester, String title) =>
      tester
              .widget<AnimatedContainer>(
                find
                    .ancestor(
                      of: find.text(title),
                      matching: find.byType(AnimatedContainer),
                    )
                    .first,
              )
              .decoration!
          as BoxDecoration;

  testWidgets('neither card is chosen to begin with', (tester) async {
    await open(tester);
    for (final title in ['I\'m a Buyer', 'I\'m a Farmer']) {
      expect(lookOf(tester, title).color, AppColors.surface);
    }
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('the chosen card is pale green, with a dark border and a check', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('I\'m a Farmer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final chosen = lookOf(tester, 'I\'m a Farmer');
    expect(chosen.color, AppColors.softTint);
    expect((chosen.border! as Border).top.color, AppColors.brandFill);
    expect(lookOf(tester, 'I\'m a Buyer').color, AppColors.surface);
    expect(find.byIcon(Icons.check), findsOneWidget);

    // It shows for a moment, and then the form opens.
    expect(find.byType(RegisterScreen), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  testWidgets('tapping twice opens one form', (tester) async {
    await open(tester);
    await tester.tap(find.text('I\'m a Buyer'));
    await tester.pump();
    await tester.tap(find.text('I\'m a Farmer'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.text('RSBSA No.'), findsNothing);
  });

  testWidgets('the card stays marked on coming back', (tester) async {
    await open(tester);
    await choose(tester, 'I\'m a Farmer');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(lookOf(tester, 'I\'m a Farmer').color, AppColors.softTint);
  });

  testWidgets('each card shows its own person from the buyer and farmer '
      'picture', (tester) async {
    await open(tester);
    final pictures = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((image) => image.assetName)
        .where((name) => !name.endsWith('logo.png'));
    expect(pictures, List.filled(2, ChooseRoleScreen.picture));
    expect(ChooseRoleScreen.picture, 'assets/images/farmer&buyer.png');

    // The buyer stands on the picture's left and the farmer on its right,
    // and neither card's part reaches into the other's.
    const buyer = ChooseRoleScreen.buyerCrop;
    const farmer = ChooseRoleScreen.farmerCrop;
    expect(buyer.right, lessThanOrEqualTo(farmer.left));
    final whole = Offset.zero & ChooseRoleScreen.pictureSize;
    expect(whole.intersect(buyer), buyer);
    expect(whole.intersect(farmer), farmer);
    // Each card's frame has its part's shape, so the person fills it.
    final people = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName == ChooseRoleScreen.picture,
    );
    for (final person in people.evaluate()) {
      final frame = tester.getSize(
        find
            .ancestor(
              of: find.byWidget(person.widget),
              matching: find.byType(ClipRect),
            )
            .first,
      );
      expect(frame.width, greaterThan(100));
      expect(frame.width, closeTo(frame.height, 0.5));
    }
  });

  testWidgets('it asks only for the role: nothing about gender', (
    tester,
  ) async {
    await open(tester);
    expect(
      find.textContaining(RegExp('gender', caseSensitive: false)),
      findsNothing,
    );
  });

  testWidgets('with animations off the form opens at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await open(tester);
    await tester.tap(find.text('I\'m a Buyer'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  testWidgets('the buyer card opens the buyer form', (tester) async {
    await open(tester);
    await choose(tester, 'I\'m a Buyer');

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.text('First Name'), findsOneWidget);
    expect(find.text('RSBSA No.'), findsNothing);
  });

  testWidgets('the farmer card opens the farmer form', (tester) async {
    await open(tester);
    await choose(tester, 'I\'m a Farmer');

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.text('RSBSA No.'), findsOneWidget);
  });

  testWidgets('the form has no Buyer/Farmer toggle', (tester) async {
    await open(tester);
    await choose(tester, 'I\'m a Farmer');

    expect(find.byType(RoleToggle), findsNothing);
    expect(find.text('Choose your role'), findsNothing);
  });

  testWidgets('Back from the form returns here, to choose again', (
    tester,
  ) async {
    await open(tester);
    await choose(tester, 'I\'m a Farmer');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('How will you use AgriTrade+?'), findsOneWidget);

    await choose(tester, 'I\'m a Buyer');
    expect(find.text('RSBSA No.'), findsNothing);
  });

  testWidgets(
    '"Log in" on the form goes past this screen, to the log-in page',
    (tester) async {
      await open(tester);
      await choose(tester, 'I\'m a Buyer');

      final link = find.textContaining('Log in', findRichText: true);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -5000),
      );
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.byType(ChooseRoleScreen), findsNothing);
      expect(find.text('Log-in page'), findsOneWidget);
    },
  );

  group('after Continue with Google, for a new Google account', () {
    const google = GoogleSignInResult.needsProfile(
      uid: 'new-google-user',
      email: 'juan.santos@gmail.com',
      displayName: 'Juan Santos',
    );
    late int signOuts;

    Future<void> openForGoogle(WidgetTester tester) async {
      signOuts = 0;
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChooseRoleScreen(
                      google: google,
                      signOut: () async => signOuts++,
                    ),
                  ),
                ),
                child: const Text('Log-in page'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Log-in page'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks for the role first, naming the Google account', (
      tester,
    ) async {
      await openForGoogle(tester);
      expect(find.text('How will you use AgriTrade+?'), findsOneWidget);
      expect(find.text('Logged in as juan.santos@gmail.com'), findsOneWidget);
      expect(find.byType(GoogleCompleteProfileScreen), findsNothing);
    });

    testWidgets('the farmer card opens the short farmer profile form', (
      tester,
    ) async {
      await openForGoogle(tester);
      await choose(tester, 'I\'m a Farmer');

      expect(find.byType(GoogleCompleteProfileScreen), findsOneWidget);
      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.text('Complete Your Profile'), findsOneWidget);
      expect(find.text('RSBSA No.'), findsOneWidget);
      expect(find.text('Mobile Number'), findsOneWidget);
      // The role was chosen already, and Google needs no password.
      expect(find.byType(RoleToggle), findsNothing);
      expect(find.text('Choose your role'), findsNothing);
      expect(find.text('Password'), findsNothing);
    });

    testWidgets('the buyer card opens the buyer form: no RSBSA No.', (
      tester,
    ) async {
      await openForGoogle(tester);
      await choose(tester, 'I\'m a Buyer');

      expect(find.byType(GoogleCompleteProfileScreen), findsOneWidget);
      expect(find.text('RSBSA No.'), findsNothing);
      expect(find.text('Mobile Number'), findsOneWidget);
    });

    testWidgets('the name comes from Google; the email cannot be changed', (
      tester,
    ) async {
      await openForGoogle(tester);
      await choose(tester, 'I\'m a Buyer');

      TextField fieldWith(String text) => tester
          .widgetList<TextField>(find.byType(TextField))
          .singleWhere((field) => field.controller?.text == text);
      expect(fieldWith('Juan').readOnly, isFalse);
      expect(fieldWith('Santos').readOnly, isFalse);
      expect(fieldWith('juan.santos@gmail.com').readOnly, isTrue);
      expect(find.text('From your Google account.'), findsOneWidget);
    });

    testWidgets('Back from the form returns here, still signed in', (
      tester,
    ) async {
      await openForGoogle(tester);
      await choose(tester, 'I\'m a Farmer');

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('How will you use AgriTrade+?'), findsOneWidget);
      expect(signOuts, 0);

      await choose(tester, 'I\'m a Buyer');
      expect(find.text('RSBSA No.'), findsNothing);
    });

    testWidgets('leaving the role choice signs the Google account out', (
      tester,
    ) async {
      await openForGoogle(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Log-in page'), findsOneWidget);
      expect(signOuts, 1);
    });

    testWidgets('Cancel on the form goes back to the role choice, still signed in', (
      tester,
    ) async {
      await openForGoogle(tester);
      await choose(tester, 'I\'m a Buyer');

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -5000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(GoogleCompleteProfileScreen), findsNothing);
      expect(find.text('How will you use AgriTrade+?'), findsOneWidget);
      expect(find.text('Log-in page'), findsNothing);
      expect(signOuts, 0);
    });
  });

  testWidgets('a password sign-up leaving here signs no one out', (
    tester,
  ) async {
    var signOuts = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ChooseRoleScreen(signOut: () async => signOuts++),
              ),
            ),
            child: const Text('Log-in page'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Log-in page'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(signOuts, 0);
  });

  testWidgets('fits a small phone', (tester) async {
    await open(tester, size: const Size(360, 560));
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('I want to sell my agricultural products.'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
  });
}
