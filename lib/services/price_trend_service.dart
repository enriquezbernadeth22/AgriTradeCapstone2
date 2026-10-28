import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/commodity_master_list.dart';
import 'dashboard_analytics_service.dart';
import 'historical_demand_service.dart';

/// Where a price on the Price Trend chart came from.
enum PriceTrendSource {
  /// A farmer's listing: its retail asking price when posted or last edited.
  farmerListing,

  /// A completed order: the retail unit price the buyer paid.
  farmerSale,

  /// A reference price the Admin set in Price Management, on its date.
  adminReference,

  /// A monthly average price in the Admin's imported historical data.
  adminImport,
}

/// One price of a commodity on a date, in [unit].
class PriceTrendPoint {
  final DateTime date;
  final double price;
  final PriceTrendSource source;
  final String unit;

  const PriceTrendPoint(this.date, this.price, this.source, {this.unit = ''});
}

/// Helpers shared by the Market Trend charts: matching a record to a
/// commodity, and keeping to the one unit its records mostly use.
class _Records {
  const _Records._();

  static String key(String text) => text.trim().toLowerCase();

  static bool isCommodity(
    Map<String, dynamic> data,
    String nameField,
    String commodity,
  ) {
    final stored = (data['commodity'] ?? '').toString().trim();
    final name = stored.isNotEmpty
        ? stored
        : (data[nameField] ?? '').toString();
    final matched = matchSupportedCommodity(name) ?? name;
    return key(matched) == key(commodity);
  }

  // A blank unit is taken as the commodity's own (older records).
  static String unitOf(Object? unit, String commodity) {
    final text = (unit ?? '').toString().trim();
    return text.isEmpty ? unitForCommodity(commodity) : text;
  }

  static DateTime? date(Object? value) =>
      value is Timestamp ? value.toDate() : (value is DateTime ? value : null);

  static double? positive(Object? value) {
    final number = value is num ? value.toDouble() : null;
    return number != null && number > 0 ? number : null;
  }

  /// The unit most of [units] are in (the commodity's own on a tie), so
  /// figures in different units never mix — a per-head price with per-kg
  /// ones, say. The commodity list's unit may be worded differently from
  /// the one its listings and orders use ("kg liveweight" against "kg"),
  /// so the records themselves decide.
  static String mainUnit(Iterable<String> units, String commodity) {
    final counts = <String, int>{};
    final spelling = <String, String>{};
    for (final unit in units) {
      counts[key(unit)] = (counts[key(unit)] ?? 0) + 1;
      spelling.putIfAbsent(key(unit), () => unit);
    }
    if (counts.isEmpty) return unitForCommodity(commodity);
    final own = key(unitForCommodity(commodity));
    var best = counts.keys.first;
    counts.forEach((unit, n) {
      final bestCount = counts[best]!;
      if (n > bestCount || (n == bestCount && unit == own)) best = unit;
    });
    return spelling[best]!;
  }
}

/// Admin → Market Change Analysis → Price Trend: a commodity's average
/// price month by month, one year against another (e.g. 2026 against
/// 2027) once there are two, from every price on record for it — the prices farmers used
/// (their listings and completed sales) and the prices the Admin entered
/// (Price Management's dated reference prices and imported historical
/// data). Each counts in the month of its own date. Nothing is estimated:
/// a month with no price on record has no point.
///
/// Only retail prices count (wholesale is a bulk discount, not the market
/// price), and only those in the unit most of the commodity's prices use.
class PriceTrendService {
  const PriceTrendService._();

  /// The years the chart offers, oldest first: from the year of the first
  /// completed order — when AgriTrade+'s own records begin, never a year
  /// before the app — to the current one; the current year alone until
  /// there is a completed order.
  static List<int> yearsOnRecord(
    Iterable<Map<String, dynamic>> completedOrders,
    DateTime now,
  ) {
    final first = DashboardAnalyticsService.completedOrderYears(
      completedOrders,
    ).where((y) => y <= now.year).fold<int>(now.year, math.min);
    return [for (var year = first; year <= now.year; year++) year];
  }

  /// Every price on record for [commodity], in the unit most of them use
  /// (also returned). [referenceHistory] is the commodity's
  /// `market_prices/{id}/history` entries.
  static ({String unit, List<PriceTrendPoint> points}) collect({
    required String commodity,
    required Iterable<Map<String, dynamic>> products,
    required Iterable<Map<String, dynamic>> completedOrders,
    required Iterable<Map<String, dynamic>> referenceHistory,
    required Iterable<HistoricalDemandRecord> historical,
  }) {
    final all = <PriceTrendPoint>[];
    void add(
      DateTime? date,
      Object? price,
      PriceTrendSource source,
      Object? unit,
    ) {
      final value = _Records.positive(price);
      if (date == null || value == null) return;
      all.add(
        PriceTrendPoint(
          date,
          value,
          source,
          unit: _Records.unitOf(unit, commodity),
        ),
      );
    }

    for (final listing in products) {
      if (!_Records.isCommodity(listing, 'name', commodity)) continue;
      add(
        _Records.date(listing['updatedAt']) ??
            _Records.date(listing['createdAt']),
        listing['retailPrice'] ?? listing['price'],
        PriceTrendSource.farmerListing,
        listing['unit'],
      );
    }
    for (final order in completedOrders) {
      if (!_Records.isCommodity(order, 'productName', commodity)) continue;
      if (_Records.key((order['pricingType'] ?? '').toString()) ==
          'wholesale') {
        continue;
      }
      add(
        _Records.date(order['completedAt']) ??
            _Records.date(order['createdAt']),
        order['pricePerUnit'] ?? order['unitPrice'],
        PriceTrendSource.farmerSale,
        order['unit'],
      );
    }
    for (final entry in referenceHistory) {
      add(
        _Records.date(entry['effectiveDate']),
        entry['price'],
        PriceTrendSource.adminReference,
        entry['unit'],
      );
    }
    for (final record in historical) {
      if (_Records.key(record.commodity) != _Records.key(commodity)) continue;
      add(
        DateTime(record.year, record.month),
        record.averagePrice,
        PriceTrendSource.adminImport,
        record.unit,
      );
    }

    final unit = _Records.mainUnit(all.map((p) => p.unit), commodity);
    return (
      unit: unit,
      points: [
        for (final p in all)
          if (_Records.key(p.unit) == _Records.key(unit)) p,
      ],
    );
  }

  /// The average price in each month of [year], January first; null for a
  /// month with no price on record.
  static List<double?> monthlyAverages(
    Iterable<PriceTrendPoint> points,
    int year,
  ) {
    final sums = List<double>.filled(12, 0);
    final counts = List<int>.filled(12, 0);
    for (final point in points) {
      if (point.date.year != year) continue;
      sums[point.date.month - 1] += point.price;
      counts[point.date.month - 1]++;
    }
    return [
      for (var m = 0; m < 12; m++) counts[m] == 0 ? null : sums[m] / counts[m],
    ];
  }

  /// The average of a year's monthly averages, or null with none.
  static double? yearAverage(List<double?> monthly) {
    final known = monthly.whereType<double>().toList();
    if (known.isEmpty) return null;
    return known.reduce((a, b) => a + b) / known.length;
  }
}

/// One product that usually sells well in a month: how many times its usual
/// month's amount it sells then.
typedef SeasonalBestSeller = ({String product, double ratio});

/// One product's twelve monthly figures as multiples of its usual month
/// (see [SeasonalSalesService.seasonalIndex]).
typedef SeasonalIndex = ({String product, List<double?> index});

/// Admin → Market Trend: for each calendar month, the products that usually
/// sell best in it — the seasonal pattern in what was sold — from the
/// Admin's imported historical data (past years) and AgriTrade+ completed
/// orders (since the marketplace opened).
///
/// Products are sold in different units (a piece of coconut, a kilo of
/// corn, a head of cattle), so amounts are never compared across products.
/// Each product is compared with itself instead: its average amount in a
/// month, over every year on record, against its usual month (the average
/// of its twelve). A product that sells twice its usual in November
/// "usually sells best" in November. Only months above the usual count.
/// Nothing is forecast.
class SeasonalSalesService {
  const SeasonalSalesService._();

  /// The products listed per month.
  static const int perMonth = 3;

  /// For each month, January first, its best sellers (highest ratio
  /// first), and the years the figures rest on.
  static ({List<List<SeasonalBestSeller>> months, List<int> years})
  bestSellers({
    required Iterable<String> commodities,
    required Iterable<Map<String, dynamic>> completedOrders,
    required Iterable<HistoricalDemandRecord> historical,
    required DateTime now,
  }) {
    final index = seasonalIndex(
      commodities: commodities,
      completedOrders: completedOrders,
      historical: historical,
      now: now,
    );
    final months = List.generate(12, (_) => <SeasonalBestSeller>[]);
    for (final product in index.products) {
      for (var m = 0; m < 12; m++) {
        final ratio = product.index[m];
        // Only months above its usual.
        if (ratio == null || ratio <= 1) continue;
        months[m].add((product: product.product, ratio: ratio));
      }
    }
    for (final month in months) {
      month.sort((a, b) {
        final byRatio = b.ratio.compareTo(a.ratio);
        return byRatio != 0 ? byRatio : a.product.compareTo(b.product);
      });
      if (month.length > perMonth) month.removeRange(perMonth, month.length);
    }
    return (months: months, years: index.years);
  }

  /// Each product's twelve monthly figures, January first: its average
  /// amount in that month over the years on record, as a multiple of its
  /// usual month (1.0 = usual, 2.0 = twice its usual). Null for a month the
  /// data does not cover. The Market Trend line chart draws these.
  static ({List<SeasonalIndex> products, List<int> years}) seasonalIndex({
    required Iterable<String> commodities,
    required Iterable<Map<String, dynamic>> completedOrders,
    required Iterable<HistoricalDemandRecord> historical,
    required DateTime now,
  }) {
    final thisMonth = DateTime(now.year, now.month);

    // The months the data covers: every month of a year the imported data
    // has records for, and every month since the first completed order —
    // never a month still to come. Elsewhere "nothing sold" is unknown,
    // not zero.
    DateTime? ordersStart;
    final completed = <Map<String, dynamic>>[];
    for (final order in completedOrders) {
      if ((order['status'] ?? 'completed').toString().toLowerCase() !=
          'completed') {
        continue;
      }
      final date =
          _Records.date(order['completedAt']) ??
          _Records.date(order['createdAt']);
      if (date == null) continue;
      completed.add(order);
      if (ordersStart == null || date.isBefore(ordersStart)) {
        ordersStart = date;
      }
    }
    final historicalYears = {for (final r in historical) r.year};
    bool covered(int year, int month) {
      final at = DateTime(year, month);
      if (at.isAfter(thisMonth)) return false;
      if (historicalYears.contains(year)) return true;
      final start = ordersStart;
      return start != null && !at.isBefore(DateTime(start.year, start.month));
    }

    final years = <int>{
      ...historicalYears.where((y) => y <= now.year),
      if (ordersStart != null)
        for (var y = ordersStart.year; y <= now.year; y++) y,
    }.toList()..sort();

    final products = <SeasonalIndex>[];
    for (final commodity in commodities) {
      // Every amount sold, with its unit; then only the main unit's.
      final sales = <({int year, int month, double quantity, String unit})>[];
      for (final order in completed) {
        if (!_Records.isCommodity(order, 'productName', commodity)) continue;
        final quantity = _Records.positive(order['quantity']);
        final date =
            _Records.date(order['completedAt']) ??
            _Records.date(order['createdAt']);
        if (quantity == null || date == null) continue;
        sales.add((
          year: date.year,
          month: date.month,
          quantity: quantity,
          unit: _Records.unitOf(order['unit'], commodity),
        ));
      }
      for (final record in historical) {
        if (_Records.key(record.commodity) != _Records.key(commodity)) {
          continue;
        }
        sales.add((
          year: record.year,
          month: record.month,
          quantity: record.quantity,
          unit: _Records.unitOf(record.unit, commodity),
        ));
      }
      if (sales.isEmpty) continue;
      final unit = _Records.key(
        _Records.mainUnit(sales.map((s) => s.unit), commodity),
      );

      // Its average amount in each calendar month over the covered years.
      final average = List<double?>.filled(12, null);
      for (var m = 1; m <= 12; m++) {
        var total = 0.0;
        var yearsCovered = 0;
        for (final year in years) {
          if (!covered(year, m)) continue;
          yearsCovered++;
          for (final s in sales) {
            if (s.year == year &&
                s.month == m &&
                _Records.key(s.unit) == unit) {
              total += s.quantity;
            }
          }
        }
        if (yearsCovered > 0) average[m - 1] = total / yearsCovered;
      }
      final known = average.whereType<double>().toList();
      if (known.isEmpty) continue;
      final usual = known.reduce((a, b) => a + b) / known.length;
      if (usual <= 0) continue;

      products.add((
        product: commodity,
        index: [
          for (final value in average) value == null ? null : value / usual,
        ],
      ));
    }
    return (products: products, years: years);
  }
}
