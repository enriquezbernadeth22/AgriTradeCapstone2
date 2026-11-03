import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/services/dashboard_analytics_service.dart';
import 'package:agritrade/services/market_diagnostics_service.dart';
import 'package:agritrade/services/market_price_helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: subtype_of_sealed_class

// The Admin's figures are counted the same way as the rest of the system:
// demand is completed orders, and there is one Current Market Average.
class _Doc extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic> _data;
  _Doc(this.id, this._data);

  @override
  Map<String, dynamic> data() => _data;
}

void main() {
  final now = DateTime(2026, 10, 20);

  _Doc completed(
    String id,
    String commodity,
    num total, {
    num quantity = 1,
    String? unit,
  }) => _Doc(id, {
    'status': 'completed',
    'productName': commodity,
    'commodity': commodity,
    'total': total,
    'quantity': quantity,
    'unit': ?unit,
    'completedAt': Timestamp.fromDate(now.subtract(const Duration(days: 3))),
  });

  test('Top-Selling Products ranks by quantity sold, not orders or pesos', () {
    final orders = [
      completed('o1', 'Cattle', 50000),
      completed('c1', 'Corn', 900, quantity: 60),
      for (var i = 0; i < 3; i++)
        completed('e$i', 'Eggplant', 120, quantity: 5),
    ];

    final top = DashboardAnalyticsService.topSellingProducts(orders);

    expect(
      [for (final p in top) p.name],
      ['Corn (kg)', 'Eggplant (kg)', 'Cattle (head)'],
    );
    expect(top[1].orders, 3);
    expect(top[1].quantity, 15);
    expect(top[1].revenue, 360);
    expect(top.last.revenue, 50000);
  });

  test('Top-Selling Products never adds unlike units together', () {
    final orders = [
      completed('h1', 'Cattle', 50000, quantity: 2, unit: 'head'),
      completed('k1', 'Cattle', 3800, quantity: 10, unit: 'kg'),
      completed('k2', 'Cattle', 1900, quantity: 5, unit: 'kg'),
    ];

    final top = DashboardAnalyticsService.topSellingProducts(orders);

    expect([for (final p in top) p.name], ['Cattle (kg)', 'Cattle (head)']);
    expect([for (final p in top) p.quantity], [15, 2]);
  });

  test('Top-Selling Products and Sales by Category count the same orders, '
      'a product not on the commodity list included', () {
    _Doc sale(String id, String name, String category, num total) => _Doc(id, {
      'status': 'completed',
      'productName': name,
      'category': category,
      'total': total,
      'quantity': 1,
      'completedAt': Timestamp.fromDate(now.subtract(const Duration(days: 3))),
    });
    final orders = [
      sale('c1', 'Corn', 'Grains', 300),
      sale('c2', 'Corn', 'Grains', 365),
      sale('k1', 'Native Chicken', 'Livestock', 1900),
      // Not on the commodity list: counted under its own name.
      sale('t1', 'tomato', 'Vegetables', 560),
    ];

    final top = DashboardAnalyticsService.topSellingProducts(orders);
    final byCategory = DashboardAnalyticsService.categoryRevenue(
      orders,
      const [],
    );

    expect(
      [for (final p in top) p.name],
      ['Corn (kg)', 'Chicken (kg liveweight)', 'Tomato (kg)'],
    );
    num sum(Iterable<num> values) => values.fold<num>(0, (a, b) => a + b);
    expect(sum(top.map((p) => p.revenue)), 3125);
    expect(sum(byCategory.values), 3125);
    expect(
      DashboardAnalyticsService.monthlyCompletedOrders(
        [for (final o in orders) o.data()],
        'Tomato',
        now.year,
      ).fold<int>(0, (a, b) => a + b),
      1,
    );
  });

  test('a tie in quantity goes to the higher sales value', () {
    final orders = [
      completed('e', 'Eggplant', 120),
      completed('c', 'Cattle', 50000),
    ];

    final top = DashboardAnalyticsService.topSellingProducts(orders);

    expect(top.first.name, 'Cattle (head)');
  });

  test('Market Change Analysis shows the same Current Market Average as '
      'Price Management', () {
    final unit = unitForCommodity('Cattle');
    Map<String, dynamic> listing(num price, {bool slaughtered = false}) => {
      'name': 'Cattle',
      'commodity': 'Cattle',
      'category': 'Livestock',
      'unit': slaughtered ? 'kg' : unit,
      'sellingOption': slaughtered ? 'slaughtered' : 'live',
      'quantity': 2,
      'retailPrice': price,
    };
    final listings = [
      listing(40000),
      listing(42000),
      listing(41000),
      listing(40000),
      listing(400000), // far off the market
      listing(380, slaughtered: true), // per kg, not per head
    ];
    final docs = [
      for (var i = 0; i < listings.length; i++) _Doc('p$i', listings[i]),
    ];

    final diagnosis = MarketDiagnosticsService.diagnose(
      commodity: 'Cattle',
      historical: const [],
      completedOrders: const [],
      products: listings,
      now: now,
    );

    expect(computeLiveAverage(docs, 'Cattle'), 40750);
    expect(diagnosis.currentMarketAverage, 40750);
  });
}
