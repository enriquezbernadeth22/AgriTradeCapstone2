// The first-run intro: four pages in order, as designed, with Skip and Next
// until the last page, which has Get Started alone. Each page's parts come in
// once, and with animations off they are simply there.
import 'package:agritrade/l10n/app_language.dart';
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/l10n/tagalog_strings.dart';
import 'package:agritrade/screen/onboarding_screen.dart';
import 'package:agritrade/theme/app_theme.dart';
import 'package:agritrade/widgets/agritrade_text.dart';
import 'package:agritrade/widgets/onboarding_reveal.dart';
import 'package:agritrade/widgets/shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// Each page's title, as its black line and its green line.
const _titles = [
  ('Welcome to', 'AgriTrade+'),
  ('Explore', 'Local Products'),
  ('Chat &', 'Order'),
  ('Track Your', 'Orders'),
];

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(412, 915),
    double textScale = 1,
    Future<void> Function()? onGetStarted,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OnboardingScreen(onGetStarted: onGetStarted ?? () async {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  Future<void> toPage(WidgetTester tester, int page) async {
    for (var i = 1; i < page; i++) {
      await next(tester);
    }
  }

  Color? colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text).first).style?.color;

  testWidgets('Next walks through the four pages, in order', (tester) async {
    await pump(tester);
    for (final (i, (black, green)) in _titles.indexed) {
      expect(find.text(black), findsWidgets, reason: black);
      expect(find.text(green), findsWidgets, reason: green);
      if (i < _titles.length - 1) await next(tester);
    }
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('a title is two lines: black, then green', (tester) async {
    await pump(tester);
    await next(tester);
    expect(colorOf(tester, 'Explore'), const Color(0xFF232624));
    expect(colorOf(tester, 'Local Products'), AppTheme.dark);
  });

  testWidgets('Chat & Order is on one line, black then green', (tester) async {
    await pump(tester);
    await toPage(tester, 3);

    final first = find.text('Chat &');
    final last = find.text('Order');
    expect(tester.getCenter(first).dy, tester.getCenter(last).dy);
    expect(tester.getTopRight(first).dx, lessThan(tester.getTopLeft(last).dx));
    expect(colorOf(tester, 'Chat &'), const Color(0xFF232624));
    expect(colorOf(tester, 'Order'), AppTheme.dark);
  });

  testWidgets('a swipe moves between the pages too', (tester) async {
    await pump(tester);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Local Products'), findsOneWidget);
  });

  testWidgets('the dots are above the buttons, with Skip left and Next right', (
    tester,
  ) async {
    await pump(tester);
    final skip = tester.getCenter(find.text('Skip'));
    final nextButton = tester.getCenter(find.text('Next'));
    final dots = find.byType(AnimatedContainer);
    final firstDot = tester.getCenter(dots.first);
    final lastDot = tester.getCenter(dots.at(3));
    expect(skip.dx, lessThan(nextButton.dx));
    expect((skip.dy - nextButton.dy).abs(), lessThan(4));
    expect(firstDot.dy, lessThan(nextButton.dy - 20));
    expect((firstDot.dx + lastDot.dx) / 2, closeTo(412 / 2, 1));
  });

  testWidgets('Skip leaves onboarding from any page', (tester) async {
    var finished = 0;
    await pump(tester, onGetStarted: () async => finished++);
    await next(tester);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('the last page has no Skip, only a wide Get Started', (
    tester,
  ) async {
    var finished = 0;
    await pump(tester, onGetStarted: () async => finished++);
    await toPage(tester, 4);

    expect(find.text('Skip'), findsNothing);
    final button = find.widgetWithText(ElevatedButton, 'Get Started');
    final dot = tester.getCenter(find.byType(AnimatedContainer).first);
    expect(dot.dy, lessThan(tester.getCenter(button).dy - 20));
    expect(tester.getSize(button).width, greaterThan(370));

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('Get Started shows loading on the button, and cannot be pressed '
      'twice', (tester) async {
    var finished = 0;
    await pump(tester, onGetStarted: () async => finished++);
    await toPage(tester, 4);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final button = find.byType(ElevatedButton);
    await tester.tap(button);
    await tester.pump();

    expect(
      find.descendant(
        of: button,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.text('Get Started'), findsNothing);
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);

    // Long enough to be seen.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(finished, 0);

    await tester.tap(button, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('Skip leaves at once, with no loading', (tester) async {
    var finished = 0;
    await pump(tester, onGetStarted: () async => finished++);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(finished, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  final logoBox = find.byType(AgriTradeLogoMark);

  bool isLogo(Widget widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName == 'assets/images/logo.png';

  testWidgets('the welcome page says the name once, in its title', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byWidgetPredicate(isLogo), findsOneWidget);
    expect(find.text('AgriTrade+'), findsOneWidget);
    expect(colorOf(tester, 'AgriTrade+'), AppTheme.dark);
    expect(tester.getCenter(logoBox).dx, 412 / 2);
  });

  for (final size in const [Size(360, 640), Size(412, 915)]) {
    testWidgets('the welcome title is right under the logo on '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await pump(tester, size: size);
      final gap =
          tester.getTopLeft(find.text('Welcome to')).dy -
          tester.getBottomLeft(logoBox).dy;
      expect(gap, lessThan(16));
    });
  }

  testWidgets('the logo is larger alone on the welcome page', (tester) async {
    await pump(tester);
    expect(tester.getSize(logoBox).width, 52);
    // And lower, nearer the title.
    final welcomeTop = tester.getTopLeft(logoBox).dy;
    await next(tester);
    expect(tester.getSize(logoBox).width, 30);
    expect(tester.getTopLeft(logoBox).dy, lessThan(welcomeTop));
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(tester.getSize(logoBox).width, 52);
  });

  testWidgets(
    'from the second page on the logo is at the left, with the name',
    (tester) async {
      await pump(tester);
      for (var page = 2; page <= _titles.length; page++) {
        await next(tester);
        expect(find.byWidgetPredicate(isLogo), findsOneWidget);
        expect(find.text('AgriTrade+'), findsOneWidget, reason: 'page $page');
        expect(tester.getTopLeft(find.text('AgriTrade+')).dy, lessThan(80));
        expect(tester.getTopLeft(logoBox).dx, 20, reason: 'page $page');
        expect(
          tester.getTopLeft(find.byType(AgriTradeText)).dx,
          greaterThan(tester.getTopRight(logoBox).dx),
        );
      }
    },
  );

  testWidgets('going back to the welcome page takes the name off again', (
    tester,
  ) async {
    await pump(tester);
    await next(tester);
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Welcome to'), findsOneWidget);
    expect(find.text('AgriTrade+'), findsOneWidget);
  });

  testWidgets('the welcome page shows the farmer and the buyer', (
    tester,
  ) async {
    await pump(tester);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/images/onboard.png',
      ),
      findsWidgets,
    );
  });

  for (final size in const [Size(360, 640), Size(360, 780), Size(412, 915)]) {
    testWidgets(
      'the farmer and the buyer show half body on ${size.width.toInt()}'
      'x${size.height.toInt()}',
      (tester) async {
        await pump(tester, size: size);
        final picture = tester.getRect(
          find
              .byWidgetPredicate(
                (w) =>
                    w is Image &&
                    (w.image as AssetImage?)?.assetName ==
                        'assets/images/onboard.png',
              )
              .first,
        );
        // The bar under the dots is 106 tall; above it, the hill.
        final barTop = size.height - 106;
        final shown = (barTop - picture.top) / picture.height;
        // The crate's bottom is at 0.49 of the picture, the shoes at 0.94.
        expect(shown, inInclusiveRange(0.55, 0.68));
      },
    );
  }

  testWidgets('every picture on the pages is decoded ahead of time', (
    tester,
  ) async {
    // A picture not ready when its page opens appears after the page's
    // entrance, so on a first open the entrance seemed not to play.
    await pump(tester);
    final shown = <String>{};
    for (var page = 1; page <= _titles.length; page++) {
      shown.addAll(
        tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => image.image)
            .whereType<AssetImage>()
            .map((image) => image.assetName)
            .where((name) => !name.endsWith('logo.png')),
      );
      if (page < _titles.length) await next(tester);
    }
    expect(shown, isNotEmpty);
    expect(OnboardingScreen.artAssets, containsAll(shown));
  });

  testWidgets('decoding the pictures can be waited on with a time limit', (
    tester,
  ) async {
    // The splash waits on this with a time limit (AppRouter). A future of the
    // wrong kind turned the limit down at run time, and the splash stopped
    // at 100% on a first open.
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    final art = OnboardingScreen.precacheArt(context);
    await tester.runAsync(
      () => art.timeout(const Duration(seconds: 5), onTimeout: () {}),
    );
  });

  // A produce picture.
  Finder picture(String file) => find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName ==
            'assets/images/onboarding/$file.png',
  );

  testWidgets('Explore shows the search bar and four pictures', (tester) async {
    await pump(tester);
    await toPage(tester, 2);

    expect(find.text('Search products...'), findsOneWidget);
    for (final product in ['corn', 'coconut', 'tomato', 'vegetables']) {
      expect(picture(product), findsOneWidget, reason: product);
    }
  });

  testWidgets('products show grey bars, never a name or a price', (
    tester,
  ) async {
    await pump(tester);
    for (var page = 2; page <= _titles.length; page++) {
      await next(tester);
      expect(find.byType(SkeletonBox), findsWidgets, reason: 'page $page');
      expect(find.textContaining('₱'), findsNothing, reason: 'page $page');
      for (final name in ['Corn', 'Coconut', 'Tomato', 'Vegetables']) {
        expect(find.text(name), findsNothing, reason: name);
      }
      expect(find.textContaining('Farm'), findsNothing, reason: 'page $page');
    }
  });

  testWidgets('Chat is the buyer asking and the farmer answering', (
    tester,
  ) async {
    await pump(tester);
    await toPage(tester, 3);

    final question = find.text('Is the corn still available?');
    final answer = find.text(
      'Yes, it\'s available! We can deliver tomorrow. 😋',
    );
    expect(question, findsOneWidget);
    expect(answer, findsOneWidget);
    expect(find.text('10:24 AM'), findsOneWidget);
    expect(find.text('10:28 AM'), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsNWidgets(2));
    expect(find.text('Send Options'), findsOneWidget);
    expect(find.text('Transaction Receipt'), findsOneWidget);

    Offset avatar(String file) => tester.getCenter(picture(file));
    // The buyer's picture is by the question, the farmer's by the answer.
    expect(
      (avatar('avatar_buyer').dy - tester.getCenter(question).dy).abs(),
      lessThan(40),
    );
    expect(
      (avatar('avatar_farmer').dy - tester.getCenter(answer).dy).abs(),
      lessThan(40),
    );
  });

  testWidgets('Current Market Average is not one of the pages', (tester) async {
    await pump(tester);
    for (var i = 0; i < _titles.length; i++) {
      expect(find.textContaining('Market Average'), findsNothing);
      if (i < _titles.length - 1) await next(tester);
    }
  });

  testWidgets('Orders shows the four status tabs and a pending order', (
    tester,
  ) async {
    await pump(tester);
    await toPage(tester, 4);

    for (final tab in ['Pending', 'Confirmed', 'Shipped', 'Completed']) {
      expect(find.text(tab), findsOneWidget, reason: tab);
    }
    expect(picture('corn'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
  });

  testWidgets('a preview is a picture: tapping it does nothing', (
    tester,
  ) async {
    var finished = 0;
    await pump(tester, onGetStarted: () async => finished++);
    await toPage(tester, 4);
    await tester.tap(find.text('Details'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Track Your'), findsOneWidget);
    expect(finished, 0);
  });

  for (final (name, size, textScale) in const [
    ('a small phone', Size(320, 568), 1.0),
    ('a common phone', Size(360, 640), 1.0),
    ('a small phone with large text', Size(320, 568), 1.3),
    ('a tall phone', Size(412, 915), 1.0),
  ]) {
    testWidgets('every page fits $name', (tester) async {
      await pump(tester, size: size, textScale: textScale);
      for (var i = 0; i < _titles.length; i++) {
        expect(tester.takeException(), isNull, reason: 'page ${i + 1}');
        if (i < _titles.length - 1) await next(tester);
      }
    });
  }

  // Next, then the page's own motion, [into] it. The motion starts as the page
  // arrives, part way through the slide.
  Future<void> tapNextAndWatch(WidgetTester tester, Duration into) async {
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(into);
  }

  double opacityAround(WidgetTester tester, Finder what) => tester
      .widget<Opacity>(
        find.ancestor(of: what, matching: find.byType(Opacity)).first,
      )
      .opacity;

  double opacityOf(WidgetTester tester, String text) =>
      opacityAround(tester, find.text(text));

  testWidgets('the search bar comes first, then the products one by one', (
    tester,
  ) async {
    await pump(tester);
    await tapNextAndWatch(tester, const Duration(milliseconds: 450));

    final search = opacityOf(tester, 'Search products...');
    final first = opacityAround(tester, picture('corn'));
    final last = opacityAround(tester, picture('vegetables'));
    expect(search, greaterThan(first));
    expect(first, greaterThan(last));

    await tester.pumpAndSettle();
    expect(opacityAround(tester, picture('vegetables')), 1);
  });

  testWidgets('the chat bubbles come one after the other, the receipt last', (
    tester,
  ) async {
    await pump(tester);
    await next(tester);
    await tapNextAndWatch(tester, const Duration(milliseconds: 450));

    expect(
      opacityOf(tester, 'Is the corn still available?'),
      greaterThan(opacityOf(tester, 'Transaction Receipt')),
    );
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'Transaction Receipt'), 1);
  });

  testWidgets('once in, nothing on a page keeps moving', (tester) async {
    await pump(tester);
    expect(tester.hasRunningAnimations, isFalse);
  });

  group('with animations turned off on the phone', () {
    Future<void> calmPump(WidgetTester tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pump(tester);
    }

    testWidgets('a page is simply there, with nothing to wait for', (
      tester,
    ) async {
      await calmPump(tester);
      await tester.tap(find.text('Next'));
      await tester.pump();
      // It jumped: no slide to wait for.
      expect(find.text('Local Products'), findsOneWidget);
      for (final widget in tester.widgetList<Opacity>(
        find.descendant(
          of: find.byType(OnboardingReveal),
          matching: find.byType(Opacity),
        ),
      )) {
        expect(widget.opacity, 1);
      }
    });
  });

  testWidgets('every page fits in Tagalog', (tester) async {
    LanguageController.instance.value = AppLanguage.tagalog;
    addTearDown(() => LanguageController.instance.value = AppLanguage.english);
    await pump(tester, size: const Size(320, 568));
    expect(find.text('Maligayang Pagdating sa'), findsOneWidget);
    for (var i = 0; i < _titles.length - 1; i++) {
      expect(tester.takeException(), isNull, reason: 'page ${i + 1}');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
    }
  });

  test('every title has its Tagalog, on two lines', () {
    for (final (black, green) in _titles) {
      final title = '$black\n$green';
      expect(kTagalogStrings, contains(title));
      expect('\n'.allMatches(kTagalogStrings[title]!), hasLength(1));
    }
  });
}
