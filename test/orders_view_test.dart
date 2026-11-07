// The Orders screen itself, on stand-in Firebase (FirebaseRefs): the
// period button sits on the right under the tabs, its short list of
// periods, and the orders it shows.
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/orders_view.dart';
import 'package:agritrade/services/firebase_refs.dart';
import 'package:agritrade/services/order_format.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({'tips_off': true});
    db = FakeFirebaseFirestore();
    FirebaseRefs.useForTests(
      firestore: db,
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'buyer1', email: 'maria@gmail.com'),
      ),
    );
  });
  tearDown(FirebaseRefs.reset);

  Future<void> addOrder(String name, DateTime placed) =>
      db.collection('orders').add({
        'buyerId': 'buyer1',
        'sellerId': 'farmer1',
        'productId': 'p1',
        'productName': name,
        'quantity': 2,
        'unit': 'kg',
        'pricePerUnit': 60,
        'total': 120,
        'status': 'pending',
        'createdAt': Timestamp.fromDate(placed),
        'updatedAt': Timestamp.fromDate(placed),
      });

  Future<void> open(
    WidgetTester tester, {
    OrderRole role = OrderRole.buyer,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: OrdersView(role: role)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("a buyer's period is on the right, opposite the Orders title", (
    tester,
  ) async {
    await open(tester);
    final period = tester.getRect(find.byKey(const Key('ordersPeriod')));
    final title = tester.getRect(find.text('Orders'));
    final tabs = tester.getRect(find.text('Pending'));
    expect(period.right, greaterThan(400 - 40));
    expect(period.left, greaterThan(400 / 2));
    // On the title's row, above the status tabs.
    expect(period.center.dy, closeTo(title.center.dy, 12));
    expect(period.bottom, lessThan(tabs.top));
  });

  testWidgets(
    "a farmer's period stays under the tabs (Inventory is opposite the "
    'title)',
    (tester) async {
      await open(tester, role: OrderRole.farmer);
      final period = tester.getRect(find.byKey(const Key('ordersPeriod')));
      final tabs = tester.getRect(find.text('Pending'));
      expect(period.top, greaterThan(tabs.bottom));
      expect(period.right, greaterThan(400 - 40));
      expect(find.textContaining('Inventory'), findsOneWidget);
    },
  );

  testWidgets('it offers only All time, Today, Last 7 days, Last 30 days', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('ordersPeriod')));
    await tester.pumpAndSettle();
    for (final label in ['Today', 'Last 7 days', 'Last 30 days']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('All time'), findsWidgets);
    for (final gone in [
      'Last 3 months',
      'Last 6 months',
      'This year',
      'Custom range',
    ]) {
      expect(find.text(gone), findsNothing);
    }
  });

  testWidgets('the buyer\'s own orders show; a period hides older ones', (
    tester,
  ) async {
    final now = DateTime.now();
    await addOrder('Eggplant', now);
    await addOrder('Squash', now.subtract(const Duration(days: 20)));
    await open(tester);
    expect(find.textContaining('Eggplant'), findsWidgets);
    expect(find.textContaining('Squash'), findsWidgets);

    await tester.tap(find.byKey(const Key('ordersPeriod')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 7 days'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Eggplant'), findsWidgets);
    expect(find.textContaining('Squash'), findsNothing);

    // No × beside it: All time, from the same menu, puts every order back.
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    await tester.tap(find.byKey(const Key('ordersPeriod')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All time').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Squash'), findsWidgets);
  });
}
