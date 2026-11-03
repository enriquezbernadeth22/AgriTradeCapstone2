// Where the app's parts must agree: the price recommendation reads anonymous
// data a farmer can actually read, a buyer can cancel until the farmer
// answers, an unanswered order says so, and a card never offers a wholesale
// price the stock cannot meet.
import 'package:agritrade/screen/order_actions.dart';
import 'package:agritrade/screen/verification_queue_view.dart';
import 'package:agritrade/services/buyer_type_watcher.dart';
import 'package:agritrade/services/market_demand_service.dart';
import 'package:agritrade/services/order_format.dart';
import 'package:agritrade/services/price_recommendation_service.dart';
import 'package:agritrade/widgets/explore_product_card.dart';
import 'package:agritrade/widgets/order_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sale(
  String product,
  DateTime date, {
  num quantity = 1,
  String unit = 'kg',
}) => {
  'productName': product,
  'status': 'completed',
  'unit': unit,
  'quantity': quantity,
  'completedAt': Timestamp.fromDate(date),
};

void main() {
  group('searches behind the price recommendation', () {
    final now = DateTime(2026, 11, 20);

    test('counts the anonymous totals of the last 30 days', () {
      final count = PriceRecommendationService.searchCountFromTrends('Corn', [
        {
          'term': 'corn',
          'days': {'2026-11-19': 3, '2026-11-02': 2, '2026-09-01': 50},
        },
        {
          'term': 'eggplant',
          'days': {'2026-11-19': 9},
        },
      ], now: now);

      expect(count, 5);
    });

    test('an empty or malformed record counts for nothing', () {
      expect(
        PriceRecommendationService.searchCountFromTrends('Corn', [
          {'term': '', 'days': <String, dynamic>{}},
          {'term': 'corn'},
        ], now: now),
        0,
      );
    });
  });

  group('the Best-Selling trend', () {
    final october = DateTime(2026, 10);
    final today = DateTime(2026, 10, 20);

    DemandTrend trendOf(List<Map<String, dynamic>> sales) =>
        MarketDemandService.bestSellers(
          sales: sales,
          month: october,
          now: today,
        ).single.trend;

    test('follows the quantity sold, like the ranking beside it', () {
      expect(
        trendOf([
          _sale('Corn', DateTime(2026, 10, 2), quantity: 50),
          _sale('Corn', DateTime(2026, 9, 2), quantity: 10),
          _sale('Corn', DateTime(2026, 9, 3), quantity: 10),
          _sale('Corn', DateTime(2026, 9, 4), quantity: 10),
        ]),
        DemandTrend.rising,
      );
    });

    test('with nothing the month before it says new, not rising', () {
      expect(
        trendOf([_sale('Corn', DateTime(2026, 10, 2), quantity: 50)]),
        DemandTrend.newEntry,
      );
    });
  });

  group('Cancel Order', () {
    Widget app(void Function(BuildContext) use) => MaterialApp(
      home: Builder(
        builder: (context) {
          use(context);
          return const SizedBox();
        },
      ),
    );
    Future<List<String>> buyerActions(
      WidgetTester tester,
      String status,
    ) async {
      late List<OrderCardAction> actions;
      await tester.pumpWidget(
        app((context) {
          actions = OrderActions.actionsFor(
            context,
            OrderInfo('o1', {'status': status}),
            OrderRole.buyer,
          );
        }),
      );
      return [for (final action in actions) action.label];
    }

    testWidgets('is offered while the order is pending', (tester) async {
      expect(await buyerActions(tester, 'pending'), ['Cancel Order']);
    });

    testWidgets('is gone once the farmer has answered', (tester) async {
      expect(await buyerActions(tester, 'confirmed'), isEmpty);
    });
  });

  group('a shipped order', () {
    final shipped = DateTime(2026, 11, 10, 9);
    OrderInfo order() => OrderInfo('o1', {
      'status': 'shipped',
      'shippedAt': Timestamp.fromDate(shipped),
    });

    test('waits 3 days for the buyer before the farmer may complete it', () {
      expect(order().farmerCanComplete(DateTime(2026, 11, 12, 9)), isFalse);
      expect(order().farmerCanComplete(DateTime(2026, 11, 13, 9)), isTrue);
    });

    Future<List<String>> farmerActions(
      WidgetTester tester,
      OrderInfo info,
    ) async {
      late List<OrderCardAction> actions;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              actions = OrderActions.actionsFor(
                context,
                info,
                OrderRole.farmer,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      return [for (final action in actions) action.label];
    }

    testWidgets('shows the farmer the wait, then Mark as Completed', (
      tester,
    ) async {
      final now = DateTime.now();
      OrderInfo sent(int daysAgo) => OrderInfo('o1', {
        'status': 'shipped',
        'shippedAt': Timestamp.fromDate(now.subtract(Duration(days: daysAgo))),
      });

      expect(await farmerActions(tester, sent(1)), ['Waiting for Buyer']);
      expect(await farmerActions(tester, sent(4)), ['Mark as Completed']);
    });

    testWidgets('a confirmed order can be cancelled by the farmer', (
      tester,
    ) async {
      expect(
        await farmerActions(
          tester,
          const OrderInfo('o1', {'status': 'confirmed'}),
        ),
        contains('Cancel Order'),
      );
    });
  });

  test('the farmer\'s reason is kept with the cancelled order', () {
    const order = OrderInfo('a', {
      'status': 'cancelled',
      'cancelReason': 'farmer',
      'cancelNote': ' The harvest failed. ',
    });
    expect(order.cancelledByFarmer, isTrue);
    expect(order.cancelNote, 'The harvest failed.');
  });

  test('an application with nothing to check cannot be approved', () {
    expect(hasSomethingToCheck(const {}, null), isFalse);
    expect(
      hasSomethingToCheck(const {'rsbaNumber': '041012034000123'}, null),
      isTrue,
    );
    expect(hasSomethingToCheck(const {}, const {'document': 'x.png'}), isTrue);
  });

  test('an order nobody answered is told apart from a buyer cancelling', () {
    const expired = OrderInfo('a', {
      'status': 'cancelled',
      'cancelReason': 'expired',
    });
    const cancelled = OrderInfo('b', {
      'status': 'cancelled',
      'cancelReason': 'buyer',
    });
    expect(expired.expiredUnanswered, isTrue);
    expect(cancelled.expiredUnanswered, isFalse);
  });

  group('the wholesale price on a card', () {
    tearDown(() => BuyerTypeWatcher.instance.debugSet(false));

    Future<void> pumpCard(WidgetTester tester, num stock) {
      BuyerTypeWatcher.instance.debugSet(true);
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 320,
              child: ExploreProductCard(
                data: {
                  'name': 'Corn',
                  'category': 'Vegetables',
                  'farmerName': 'Juan',
                  'retailPrice': 50,
                  'wholesalePrice': 40,
                  'wholesaleEnabled': true,
                  'wholesaleMinimumQuantity': 10,
                  'quantity': stock,
                  'unit': 'kg',
                },
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows to a bulk buyer when the stock can meet it', (
      tester,
    ) async {
      await pumpCard(tester, 10);
      expect(find.textContaining('40.00'), findsOneWidget);
    });

    testWidgets('gives way to retail when the stock is below the minimum', (
      tester,
    ) async {
      await pumpCard(tester, 9);
      expect(find.textContaining('50.00'), findsOneWidget);
      expect(find.textContaining('40.00'), findsNothing);
    });
  });
}
