// Search suggests as the buyer types; with no internet the app waits on
// its splash, and a pull to refresh says so instead of pretending; and a
// video upload shows its size.
import 'package:agritrade/screen/chat_attachments.dart';
import 'package:agritrade/services/search_suggestions.dart';
import 'package:agritrade/widgets/agri_refresh_indicator.dart';
import 'package:agritrade/widgets/branded_loading_screen.dart';
import 'package:agritrade/widgets/sprout_loading_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('suggested searches while typing', () {
    final listings = [
      {'name': 'Native Chicken', 'farmerName': 'Juan dela Cruz'},
      {'name': 'Chicken Eggs', 'farmerName': 'Ana Reyes'},
      {'name': 'Tilapia', 'farmerName': 'Juan dela Cruz'},
    ];

    test(
      'commodities, listings and farmers that match, starting ones first',
      () {
        final terms = suggestedSearchTerms(
          'chick',
          commodities: const ['Chicken', 'Corn'],
          listings: listings,
        );
        expect(terms, ['Chicken', 'Chicken Eggs', 'Native Chicken']);
      },
    );

    test('a farmer\'s name, once, whatever its capitals', () {
      expect(suggestedSearchTerms('juan', listings: listings), [
        'Juan dela Cruz',
      ]);
    });

    test('nothing for an empty field, and at most the limit', () {
      expect(suggestedSearchTerms('  ', listings: listings), isEmpty);
      expect(
        suggestedSearchTerms('a', listings: listings, limit: 2),
        hasLength(2),
      );
    });
  });

  testWidgets('opened without internet: the splash says it is waiting', (
    tester,
  ) async {
    SproutLoadingBar.resetFill();
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(home: BrandedLoadingScreen(onRetryOffline: () => retried++)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('splashOffline')), findsOneWidget);
    expect(find.textContaining('No internet connection'), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    expect(retried, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('the normal splash has no offline note', (tester) async {
    SproutLoadingBar.resetFill();
    await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('splashOffline')), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('pulling to refresh with no internet says so and loads nothing', (
    tester,
  ) async {
    final online = AgriRefreshIndicator.online;
    addTearDown(() => AgriRefreshIndicator.online = online);
    AgriRefreshIndicator.online = () async => false;
    var refreshed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgriRefreshIndicator(
            onRefresh: () async => refreshed++,
            child: ListView(children: const [SizedBox(height: 900)]),
          ),
        ),
      ),
    );
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(refreshed, 0);
    expect(find.textContaining('No internet connection'), findsOneWidget);
  });

  testWidgets('online, the refresh runs as before', (tester) async {
    final online = AgriRefreshIndicator.online;
    addTearDown(() => AgriRefreshIndicator.online = online);
    AgriRefreshIndicator.online = () async => true;
    var refreshed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgriRefreshIndicator(
            onRefresh: () async => refreshed++,
            child: ListView(children: const [SizedBox(height: 900)]),
          ),
        ),
      ),
    );
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });

  testWidgets('a video upload shows how much of its size has gone up', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatUploadProgress(
            video: true,
            progress: 0.5,
            totalBytes: 60 * 1024 * 1024,
          ),
        ),
      ),
    );
    expect(find.text('Sending video… 50%'), findsOneWidget);
    expect(find.text('30 of 60 MB'), findsOneWidget);
  });
}
