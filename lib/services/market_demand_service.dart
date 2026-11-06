import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/commodity_master_list.dart';

/// Marketplace-wide demand analytics for the Farmer Dashboard: Best-Selling
/// Products and Top Buyer Locations.
///
/// Everything is computed from `market_sales` — the anonymized mirror of
/// completed orders across all farmers that the recordMarketSale Cloud
/// Function maintains (a farmer can't read other farmers' orders). Only
/// completed orders are in it, so nothing pending, rejected or cancelled is
/// ever counted. It carries the commodity, order type and the buyer's
/// general area (municipality/city) — never who the buyer or seller was.
///
/// Commodities are resolved through [CommodityRegistry] (the Admin-managed
/// list), so one the Admin adds becomes eligible as soon as a completed
/// order exists for it; there is no list of products in here.

enum DemandLevel { high, moderate, low }

/// [newEntry]: nothing in the month before to compare with, so neither
/// rising nor falling can honestly be said.
enum DemandTrend { rising, stable, declining, newEntry }

class BestSeller {
  final String commodity;
  final String category;
  final String unit;

  /// How much was sold in [unit] in the month.
  final num quantity;

  /// True/false when the order type is on record for these sales; null for
  /// sales recorded before it was kept.
  final bool? mostlyWholesale;

  /// The buyer area with the most completed orders for this commodity, or
  /// '' when no buyer area is on record.
  final String topBuyerArea;
  final DemandLevel demand;
  final DemandTrend trend;

  const BestSeller({
    required this.commodity,
    required this.category,
    required this.unit,
    required this.quantity,
    required this.mostlyWholesale,
    required this.topBuyerArea,
    required this.demand,
    required this.trend,
  });
}

class BuyerLocation {
  final String area;

  /// 0–1: this area's completed orders relative to the top area's. Sets
  /// its [demand] level.
  final double relativeDemand;
  final String mostPurchased;
  final DemandLevel demand;

  /// Completed orders from buyers in this area that month.
  final int orders;

  /// This area's share, in whole percent, of every completed order with a
  /// buyer area that month. The shares of all the month's areas add up to
  /// exactly 100 (see [MarketDemandService.wholePercents]).
  final int sharePercent;

  const BuyerLocation({
    required this.area,
    required this.relativeDemand,
    required this.mostPurchased,
    required this.demand,
    required this.orders,
    required this.sharePercent,
  });
}

/// One completed order as recorded in `market_sales`, with its commodity
/// resolved against the Admin-managed list.
class MarketSale {
  final String commodity;
  final String category;
  final String unit;
  final bool? wholesale;
  final String area;
  final DateTime date;
  final num quantity;

  const MarketSale(
    this.commodity,
    this.category,
    this.unit,
    this.wholesale,
    this.area,
    this.date,
    this.quantity,
  );
}

class MarketDemandService {
  const MarketDemandService._();

  /// How many Best-Selling Products are listed.
  static const int bestSellerLimit = 5;

  /// How many commodities get the Buyer's demand badge.
  static const int demandLeaderLimit = 10;
  static const int locationLimit = 10;

  static List<MarketSale> parseSales(Iterable<Map<String, dynamic>> records) {
    final sales = <MarketSale>[];
    for (final record in records) {
      if ((record['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      final name = (record['productName'] ?? '').toString().trim();
      final date = record['completedAt'] ?? record['createdAt'];
      if (name.isEmpty || date is! Timestamp) continue;

      // "Fresh Native Tomato" and "Tomato" are the same commodity.
      final commodity = matchSupportedCommodity(name) ?? name;
      final category =
          categoryOfCommodity(commodity) ??
          normalizeCategory(record['category']);
      final unit = (record['unit'] ?? '').toString().trim();
      final pricing = (record['pricingType'] ?? '').toString().toLowerCase();
      final quantity = record['quantity'];
      sales.add(
        MarketSale(
          commodity,
          category,
          unit.isEmpty ? unitForCommodity(commodity) : unit,
          pricing.isEmpty ? null : pricing == 'wholesale',
          (record['buyerArea'] ?? '').toString().trim(),
          date.toDate(),
          quantity is num
              ? quantity
              : num.tryParse(quantity?.toString() ?? '') ?? 0,
        ),
      );
    }
    return sales;
  }

  static bool _inMonth(DateTime date, DateTime month) =>
      date.year == month.year && date.month == month.month;

  /// Demand relative to the busiest entry of the same list and period:
  /// High at two-thirds of its completed orders or more, Moderate at
  /// one-third or more, otherwise Low.
  static DemandLevel _level(int orders, int topOrders) {
    final share = topOrders == 0 ? 0 : orders / topOrders;
    if (share >= 2 / 3) return DemandLevel.high;
    if (share >= 1 / 3) return DemandLevel.moderate;
    return DemandLevel.low;
  }

  /// This period against the same stretch of the month before: more than
  /// 10% up is Rising, more than 10% down is Declining.
  static DemandTrend _trend(num current, num previous) {
    if (previous == 0) {
      return current > 0 ? DemandTrend.newEntry : DemandTrend.stable;
    }
    final change = (current - previous) / previous;
    if (change > 0.10) return DemandTrend.rising;
    if (change < -0.10) return DemandTrend.declining;
    return DemandTrend.stable;
  }

  static String _mostCommon(Iterable<String> values) {
    final counts = <String, int>{};
    for (final value in values) {
      if (value.isNotEmpty) counts[value] = (counts[value] ?? 0) + 1;
    }
    var best = '';
    var bestCount = 0;
    counts.forEach((value, n) {
      if (n > bestCount) {
        best = value;
        bestCount = n;
      }
    });
    return best;
  }

  /// The months a card can show, newest first: from the first completed
  /// sale on record to the current month, which is always included. [month]
  /// stays on the list even if it is older than every sale.
  static List<DateTime> monthsOnRecord({
    required Iterable<Map<String, dynamic>> sales,
    required DateTime month,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final current = DateTime(today.year, today.month);
    var first = DateTime(month.year, month.month);
    for (final sale in parseSales(sales)) {
      final saleMonth = DateTime(sale.date.year, sale.date.month);
      if (saleMonth.isBefore(first)) first = saleMonth;
    }
    return [
      for (
        var cursor = current;
        !cursor.isBefore(first);
        cursor = DateTime(cursor.year, cursor.month - 1)
      )
        cursor,
    ];
  }

  /// Best-Selling Products in [month], across every farmer: product and
  /// unit groups ranked by quantity sold, the same way as the Admin's
  /// Top-Selling Products. Unlike units are never added together. Demand
  /// and trend stay based on completed orders, as everywhere else.
  static List<BestSeller> bestSellers({
    required Iterable<Map<String, dynamic>> sales,
    required DateTime month,
    DateTime? now,
  }) {
    final all = parseSales(sales);
    final demand = {
      for (final item in _rankedByOrders(all, month, now ?? DateTime.now()))
        item.commodity.toLowerCase(): item,
    };

    final inPrevious = _previousStretch(month, now ?? DateTime.now());
    final groups = <String, List<MarketSale>>{};
    final soldBefore = <String, num>{};
    for (final sale in all) {
      final key = '${sale.commodity.toLowerCase()}|${sale.unit.toLowerCase()}';
      if (_inMonth(sale.date, month)) {
        groups.putIfAbsent(key, () => []).add(sale);
      } else if (inPrevious(sale.date)) {
        soldBefore[key] = (soldBefore[key] ?? 0) + sale.quantity;
      }
    }

    num sold(List<MarketSale> orders) =>
        orders.fold<num>(0, (total, sale) => total + sale.quantity);
    final ranked = groups.values.toList()
      ..sort((a, b) {
        final byQuantity = sold(b).compareTo(sold(a));
        if (byQuantity != 0) return byQuantity;
        final byOrders = b.length.compareTo(a.length);
        return byOrders != 0
            ? byOrders
            : a.first.commodity.compareTo(b.first.commodity);
      });

    return [
      for (final orders in ranked.take(bestSellerLimit))
        () {
          final first = orders.first;
          final key =
              '${first.commodity.toLowerCase()}|${first.unit.toLowerCase()}';
          return _entry(
            orders,
            unit: first.unit,
            demand: demand[first.commodity.toLowerCase()]!.demand,
            // Against what was sold before, like the ranking it sits beside.
            trend: _trend(sold(orders), soldBefore[key] ?? 0),
          );
        }(),
    ];
  }

  /// The commodities with the most completed orders in [month], across
  /// every farmer: the Buyer's demand badge. Ranked by number of completed
  /// orders, because demand is counted in orders everywhere in the app.
  static List<BestSeller> demandLeaders({
    required Iterable<Map<String, dynamic>> sales,
    required DateTime month,
    DateTime? now,
  }) => _rankedByOrders(
    parseSales(sales),
    month,
    now ?? DateTime.now(),
  ).take(demandLeaderLimit).toList();

  static BestSeller _entry(
    List<MarketSale> orders, {
    required String unit,
    required DemandLevel demand,
    required DemandTrend trend,
  }) {
    final typed = orders.where((s) => s.wholesale != null).toList();
    final wholesale = typed.where((s) => s.wholesale!).length;
    return BestSeller(
      commodity: orders.first.commodity,
      category: orders.first.category,
      unit: unit,
      quantity: orders.fold<num>(0, (total, sale) => total + sale.quantity),
      mostlyWholesale: typed.isEmpty
          ? null
          : wholesale > typed.length - wholesale,
      topBuyerArea: _mostCommon(orders.map((s) => s.area)),
      demand: demand,
      trend: trend,
    );
  }

  // The month before [month]. For the month still in progress, compare like
  // with like: the same number of days of it, not all of it.
  static bool Function(DateTime) _previousStretch(
    DateTime month,
    DateTime today,
  ) {
    final previousMonth = DateTime(month.year, month.month - 1);
    final isCurrentMonth = _inMonth(today, month);
    return (date) =>
        _inMonth(date, previousMonth) &&
        (!isCurrentMonth || date.day <= today.day);
  }

  static List<BestSeller> _rankedByOrders(
    List<MarketSale> all,
    DateTime month,
    DateTime today,
  ) {
    final inPrevious = _previousStretch(month, today);

    final byCommodity = <String, List<MarketSale>>{};
    final previousCount = <String, int>{};
    for (final sale in all) {
      final key = sale.commodity.toLowerCase();
      if (_inMonth(sale.date, month)) {
        byCommodity.putIfAbsent(key, () => []).add(sale);
      } else if (inPrevious(sale.date)) {
        previousCount[key] = (previousCount[key] ?? 0) + 1;
      }
    }

    final ranked = byCommodity.entries.toList()
      ..sort((a, b) {
        final byOrders = b.value.length.compareTo(a.value.length);
        return byOrders != 0
            ? byOrders
            : a.value.first.commodity.compareTo(b.value.first.commodity);
      });
    if (ranked.isEmpty) return const [];
    final topOrders = ranked.first.value.length;

    return [
      for (final entry in ranked)
        _entry(
          entry.value,
          unit: _mostCommon(entry.value.map((s) => s.unit)),
          demand: _level(entry.value.length, topOrders),
          trend: _trend(entry.value.length, previousCount[entry.key] ?? 0),
        ),
    ];
  }

  /// What buyers in [area] ordered in [month]: commodities by number of
  /// completed orders, most first (ties by name), at most
  /// [bestSellerLimit] — the details behind one Top Buyer Locations row.
  /// Counted in orders, as the locations themselves are ranked.
  static List<({String commodity, int orders})> productsBoughtIn({
    required Iterable<Map<String, dynamic>> sales,
    required DateTime month,
    required String area,
  }) {
    final orders = <String, int>{};
    for (final sale in parseSales(sales)) {
      if (sale.area != area || !_inMonth(sale.date, month)) continue;
      orders[sale.commodity] = (orders[sale.commodity] ?? 0) + 1;
    }
    final ranked = orders.entries.toList()
      ..sort((a, b) {
        final byOrders = b.value.compareTo(a.value);
        return byOrders != 0 ? byOrders : a.key.compareTo(b.key);
      });
    return [
      for (final entry in ranked.take(bestSellerLimit))
        (commodity: entry.key, orders: entry.value),
    ];
  }

  /// Every completed order from buyers in [area] in [month] — what each
  /// product's share in [productsBoughtIn] is out of.
  static int ordersInArea({
    required Iterable<Map<String, dynamic>> sales,
    required DateTime month,
    required String area,
  }) => parseSales(
    sales,
  ).where((sale) => sale.area == area && _inMonth(sale.date, month)).length;

  /// The buyer areas with the most completed orders in [month]. Sales with
  /// no buyer area on record are left out rather than guessed.
  static List<BuyerLocation> topBuyerLocations({
    required Iterable<Map<String, dynamic>> sales,
    required DateTime month,
  }) {
    final byArea = <String, List<MarketSale>>{};
    for (final sale in parseSales(sales)) {
      if (sale.area.isEmpty || !_inMonth(sale.date, month)) continue;
      byArea.putIfAbsent(sale.area, () => []).add(sale);
    }
    final ranked = byArea.entries.toList()
      ..sort((a, b) {
        final byOrders = b.value.length.compareTo(a.value.length);
        return byOrders != 0 ? byOrders : a.key.compareTo(b.key);
      });
    if (ranked.isEmpty) return const [];
    final topOrders = ranked.first.value.length;
    // Shared out over every area of the month, not just the ones listed.
    final shares = wholePercents([for (final e in ranked) e.value.length]);

    return [
      for (var i = 0; i < ranked.length && i < locationLimit; i++)
        BuyerLocation(
          area: ranked[i].key,
          relativeDemand: ranked[i].value.length / topOrders,
          mostPurchased: _mostCommon(ranked[i].value.map((s) => s.commodity)),
          demand: _level(ranked[i].value.length, topOrders),
          orders: ranked[i].value.length,
          sharePercent: shares[i],
        ),
    ];
  }

  /// [counts] as whole percents of their sum that add up to exactly 100
  /// (largest remainder: each gets its rounded-down share, then the ones
  /// with the biggest remainders get a point each until 100 is reached).
  /// All zeros, or an empty list, give all zeros.
  static List<int> wholePercents(List<int> counts) {
    final total = counts.fold<int>(0, (a, c) => a + c);
    if (total == 0) return List.filled(counts.length, 0);
    final exact = [for (final c in counts) c * 100 / total];
    final result = [for (final e in exact) e.floor()];
    var left = 100 - result.fold<int>(0, (a, p) => a + p);
    final byRemainder = List.generate(counts.length, (i) => i)
      ..sort((a, b) {
        final byRest = (exact[b] - result[b]).compareTo(exact[a] - result[a]);
        return byRest != 0 ? byRest : a.compareTo(b);
      });
    for (final i in byRemainder) {
      if (left == 0) break;
      result[i]++;
      left--;
    }
    return result;
  }
}
