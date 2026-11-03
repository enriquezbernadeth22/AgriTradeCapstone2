import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/account_types.dart';
import 'dashboard_analytics_service.dart';
import 'historical_demand_service.dart';
import 'market_diagnostics_service.dart';
import 'report_section.dart';

/// The Export Report's two market sections, worked out exactly as the
/// dashboard's Market Demand and Market Change Analysis cards, so the report
/// and the screen always agree. Only completed orders are counted.
class MarketReportSections {
  const MarketReportSections._();

  /// The most commodities Market Change Analysis lists, the busiest first,
  /// to keep the report compact.
  static const int changeLimit = 15;

  /// BUYERS BY TYPE: how many buyers chose each answer to "What best
  /// describes you", most first. Older accounts, never asked, are counted as
  /// not specified, so the total is every buyer.
  static ReportSection buyersByType(Iterable<Map<String, dynamic>> users) {
    final counts = <String, int>{};
    var total = 0;
    for (final user in users) {
      if (user['role'] != 'buyer') continue;
      final type = accountTypeOf(user) ?? kAccountTypeNotSpecified;
      counts[type] = (counts[type] ?? 0) + 1;
      total++;
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    String share(int count) => '${(count / total * 100).toStringAsFixed(1)}%';
    return ReportSection(
      title: 'Buyers by Type',
      headers: const ['Buyer Type', 'Buyers', 'Share of Buyers'],
      rows: [
        for (final entry in ranked)
          [entry.key, entry.value, share(entry.value)],
        if (total > 0) ['Total', total, '100%'],
      ],
    );
  }

  /// MARKET DEMAND: the completed orders of each month in [range] (every
  /// month on record when null), the same month a year before, and the
  /// month's top product. Orders, not kilos, as units differ. Only
  /// [commodities] are counted, when given.
  static ReportSection marketDemand({
    required Iterable<Map<String, dynamic>> orders,
    required DateTimeRange? range,
    Set<String> commodities = const {},
  }) {
    final wanted = {for (final name in commodities) name.toLowerCase()};
    final dated = <({DateTime date, String product})>[];
    for (final order in orders) {
      if ((order['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      final date = DashboardAnalyticsService.completionDateOf(order);
      final product = DashboardAnalyticsService.demandProduct(order);
      if (date == null || product == null) continue;
      if (wanted.isNotEmpty && !wanted.contains(product.toLowerCase())) {
        continue;
      }
      dated.add((date: date, product: product));
    }

    final months = _months(dated.map((sale) => sale.date), range);
    int ordersIn(DateTime month) => dated
        .where(
          (sale) =>
              sale.date.year == month.year && sale.date.month == month.month,
        )
        .length;
    final firstYear = dated.isEmpty
        ? null
        : dated.map((sale) => sale.date.year).reduce((a, b) => a < b ? a : b);

    final rows = <List<Object?>>[];
    var total = 0;
    for (final month in months) {
      final count = ordersIn(month);
      total += count;
      final lastYear = DateTime(month.year - 1, month.month);
      rows.add([
        DateFormat('MMM y').format(month),
        count,
        // "—" before anything was on record, not a misleading 0.
        firstYear == null || lastYear.year < firstYear
            ? '—'
            : ordersIn(lastYear),
        _topProduct(dated, month),
      ]);
    }
    if (rows.isNotEmpty && total > 0) {
      rows.add(['Total', total, '—', '—']);
    }
    return ReportSection(
      title: 'Market Demand',
      headers: const [
        'Month',
        'Completed Orders',
        'Same Month Last Year',
        'Top Product',
      ],
      // A month with no sales still has a row, so an all-empty report period
      // says "No data" instead of a table of zeros.
      rows: total == 0 ? const [] : rows,
      columnWeights: const [1, 1, 1.2, 1.8],
    );
  }

  /// The months from [range], or from the first of [dates] to the last.
  static List<DateTime> _months(
    Iterable<DateTime> dates,
    DateTimeRange? range,
  ) {
    DateTime? start = range?.start;
    DateTime? end = range?.end;
    for (final date in dates) {
      if (range != null) break;
      if (start == null || date.isBefore(start)) start = date;
      if (end == null || date.isAfter(end)) end = date;
    }
    if (start == null || end == null) return const [];
    final last = DateTime(end.year, end.month);
    return [
      for (
        var month = DateTime(start.year, start.month);
        !month.isAfter(last);
        month = DateTime(month.year, month.month + 1)
      )
        month,
    ];
  }

  static String _topProduct(
    Iterable<({DateTime date, String product})> sales,
    DateTime month,
  ) {
    final counts = <String, int>{};
    for (final sale in sales) {
      if (sale.date.year == month.year && sale.date.month == month.month) {
        counts[sale.product] = (counts[sale.product] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return '—';
    final top = counts.entries.reduce(
      (a, b) =>
          b.value > a.value ||
              (b.value == a.value && b.key.compareTo(a.key) < 0)
          ? b
          : a,
    );
    return '${top.key} (${top.value})';
  }

  /// MARKET CHANGE ANALYSIS: for each commodity, what changed in the last 30
  /// days against the 30 days before, and the factors the data points to
  /// (see [MarketDiagnosticsService]). Always the last 30 days, as on the
  /// dashboard, whatever period the report covers.
  static ReportSection marketChange({
    required Iterable<Map<String, dynamic>> orders,
    required Iterable<Map<String, dynamic>> products,
    required Iterable<HistoricalDemandRecord> historical,
    Set<String> commodities = const {},
    DateTime? now,
  }) {
    final names = commodities.isNotEmpty
        ? commodities
        : {
            for (final order in orders)
              ?DashboardAnalyticsService.demandProduct(order),
          };
    final diagnoses = [
      for (final name in names)
        MarketDiagnosticsService.diagnose(
          commodity: name,
          historical: historical,
          completedOrders: orders,
          products: products,
          now: now,
        ),
    ].where((diagnosis) => diagnosis.hasData).toList();
    diagnoses.sort((a, b) {
      final byOrders = b.ordersLast30.compareTo(a.ordersLast30);
      return byOrders != 0 ? byOrders : a.commodity.compareTo(b.commodity);
    });

    return ReportSection(
      title: 'Market Change Analysis',
      headers: const [
        'Commodity',
        'Demand (Last 30 Days)',
        'Local Supply',
        'Market Price',
        'Possible Factors',
      ],
      rows: [
        for (final item in diagnoses.take(changeLimit))
          [
            item.commodity,
            item.demandSummary,
            item.supplySummary,
            item.priceSummary,
            item.factors.isEmpty ? '—' : item.factors.join(' '),
          ],
      ],
      columnWeights: const [1, 1.7, 1.7, 1.7, 2],
    );
  }
}
