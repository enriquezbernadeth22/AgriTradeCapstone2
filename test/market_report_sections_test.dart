// The Export Report's Market Demand and Market Change Analysis sections:
// real completed orders only, the same figures as the dashboard.
import 'package:agritrade/services/market_report_sections.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _order(
  String product,
  DateTime date, {
  String status = 'completed',
}) => {
  'status': status,
  'productName': product,
  'commodity': product,
  'quantity': 2,
  'unit': 'kg',
  'total': 100,
  'completedAt': Timestamp.fromDate(date),
};

void main() {
  final range = DateTimeRange(
    start: DateTime(2026, 10, 1),
    end: DateTime(2026, 11, 30),
  );

  test('Market Demand lists each month, last year and the top product', () {
    final section = MarketReportSections.marketDemand(
      orders: [
        _order('Corn', DateTime(2025, 10, 5)),
        _order('Corn', DateTime(2026, 10, 5)),
        _order('Corn', DateTime(2026, 10, 6)),
        _order('Eggplant', DateTime(2026, 10, 7)),
        _order('Eggplant', DateTime(2026, 11, 1)),
        _order('Okra', DateTime(2026, 11, 2), status: 'cancelled'),
      ],
      range: range,
    );

    expect(section.title, 'Market Demand');
    expect(section.rows, [
      ['Oct 2026', 3, 1, 'Corn (2)'],
      ['Nov 2026', 1, 0, 'Eggplant (1)'],
      ['Total', 4, '—', '—'],
    ]);
  });

  test('a month before anything was on record shows no comparison', () {
    final section = MarketReportSections.marketDemand(
      orders: [_order('Corn', DateTime(2026, 10, 5))],
      range: range,
    );
    expect(section.rows.first[2], '—');
  });

  test('a period with no completed orders has no rows at all', () {
    expect(
      MarketReportSections.marketDemand(orders: const [], range: range).rows,
      isEmpty,
    );
  });

  test('only the chosen commodity is counted', () {
    final section = MarketReportSections.marketDemand(
      orders: [
        _order('Corn', DateTime(2026, 10, 5)),
        _order('Eggplant', DateTime(2026, 10, 7)),
      ],
      range: range,
      commodities: const {'Eggplant'},
    );
    expect(section.rows.first, ['Oct 2026', 1, '—', 'Eggplant (1)']);
  });

  test('Market Change Analysis lists what changed, the busiest first', () {
    final now = DateTime(2026, 11, 2);
    final section = MarketReportSections.marketChange(
      orders: [
        _order('Eggplant', now.subtract(const Duration(days: 3))),
        _order('Corn', now.subtract(const Duration(days: 3))),
        _order('Corn', now.subtract(const Duration(days: 4))),
      ],
      products: const [],
      historical: const [],
      now: now,
    );

    expect(section.title, 'Market Change Analysis');
    expect(section.rows.map((row) => row.first), ['Corn', 'Eggplant']);
    expect(section.headers, hasLength(section.rows.first.length));
  });

  test('with nothing on record there are no rows', () {
    expect(
      MarketReportSections.marketChange(
        orders: const [],
        products: const [],
        historical: const [],
      ).rows,
      isEmpty,
    );
  });
}
