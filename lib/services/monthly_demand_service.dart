import 'dart:ui' show Color;

import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import 'dashboard_analytics_service.dart';

/// The numbers behind the Admin Dashboard's Market Demand section and its
/// Full Product Demand view (the user's design, 2026-11-10).
///
/// Demand is completed orders: each order counted once (by its id), in
/// the month it was completed. A product's demand is the number of
/// completed orders containing it. In AgriTrade+ an order holds one
/// product, but nothing here assumes so: a product counts an order once
/// however much of it was bought, and the per-product counts may add up to
/// more than the month's orders. Never buyer searches, never quantities.

/// "All Products": the product filter that counts every completed order.
const String kAllProducts = 'All Products';

/// One completed order, as demand counts it.
class DemandOrder {
  final String id;
  final DateTime completed;
  final String product;
  final String category;

  /// How much was bought, in [unit] (for quantity sold, never for demand).
  final num quantity;
  final String unit;

  /// What the order came to.
  final num total;

  const DemandOrder({
    required this.id,
    required this.completed,
    required this.product,
    required this.category,
    this.quantity = 0,
    this.unit = '',
    this.total = 0,
  });

  DateTime get month => DateTime(completed.year, completed.month);
}

/// The completed orders among [orders], once each: those with a
/// completion date and a product. [productsById] gives an order's listing,
/// for its category when the order has none of its own.
List<DemandOrder> demandOrdersOf(
  Iterable<({String id, Map<String, dynamic> data})> orders, {
  Map<String, Map<String, dynamic>> productsById = const {},
}) {
  final seen = <String>{};
  final out = <DemandOrder>[];
  for (final order in orders) {
    final data = order.data;
    if ((data['status'] ?? '').toString().toLowerCase() != 'completed') {
      continue;
    }
    if (!seen.add(order.id)) continue;
    final date = DashboardAnalyticsService.completionDate(data);
    // The commodity frozen on the order first, as it was sold: matching
    // the name instead can put an order under another product ("Palay"
    // is inside "Ampalaya") when the commodity list lacks its own.
    final frozen = (data['commodity'] ?? '').toString().trim();
    final product = frozen.isNotEmpty
        ? (CommodityRegistry.instance.find(frozen)?.name ?? frozen)
        : DashboardAnalyticsService.demandProduct(data);
    if (date == null || product == null) continue;
    final listing = productsById[(data['productId'] ?? '').toString()];
    out.add(
      DemandOrder(
        id: order.id,
        completed: date,
        product: product,
        category:
            DashboardAnalyticsService.orderCategory(data, listing) ?? 'Others',
        quantity: data['quantity'] is num ? data['quantity'] as num : 0,
        unit: (data['unit'] ?? listing?['unit'] ?? '').toString().trim(),
        total: _totalOf(data),
      ),
    );
  }
  return out;
}

// What an order came to: its total, else its unit price times quantity.
num _totalOf(Map<String, dynamic> data) {
  final total = data['total'];
  if (total is num) return total;
  final price = data['pricePerUnit'] ?? data['unitPrice'];
  final quantity = data['quantity'];
  return price is num && quantity is num ? price * quantity : 0;
}

/// The years with completed orders, oldest first.
List<int> demandYears(Iterable<DemandOrder> orders) =>
    {for (final o in orders) o.completed.year}.toList()..sort();

/// The months [year] reports on: from its first month with a completed
/// order to its last one, or to [now]'s month in the current year, so a
/// month with none so far still shows as zero. Months before the records
/// begin are left out. Empty when the year has no completed order.
List<DateTime> reportingMonths(
  Iterable<DemandOrder> orders,
  int year, {
  required DateTime now,
}) {
  final months = [
    for (final o in orders)
      if (o.completed.year == year) o.completed.month,
  ];
  if (months.isEmpty) return const [];
  final first = months.reduce((a, b) => a < b ? a : b);
  var last = months.reduce((a, b) => a > b ? a : b);
  if (year == now.year && now.month > last) last = now.month;
  return [for (var m = first; m <= last; m++) DateTime(year, m)];
}

bool _isProduct(DemandOrder o, String? product) =>
    product == null ||
    product == kAllProducts ||
    o.product.toLowerCase() == product.toLowerCase();

/// Completed orders in each of [months] for [product] (all of them for
/// null or [kAllProducts]), each order once.
Map<DateTime, int> monthlyOrders(
  Iterable<DemandOrder> orders,
  List<DateTime> months, {
  String? product,
}) {
  final ids = {for (final m in months) m: <String>{}};
  for (final o in orders) {
    if (!_isProduct(o, product)) continue;
    ids[o.month]?.add(o.id);
  }
  return {for (final m in months) m: ids[m]!.length};
}

/// The products bought, with the categories they were sold under.
List<String> demandProducts(Iterable<DemandOrder> orders) {
  final names = {for (final o in orders) o.product}.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return names;
}

/// One product's demand in a period.
class ProductDemandRow {
  final String product;
  final String category;

  /// Completed orders containing the product.
  final int orders;

  /// [orders] as a share of the period's completed orders, in percent:
  /// order penetration, not a split of 100%.
  final double share;

  const ProductDemandRow({
    required this.product,
    required this.category,
    required this.orders,
    required this.share,
  });
}

/// The products ordered in [months] (one month, or a whole period), most
/// completed orders first (then by name), and the period's own distinct
/// completed orders, which the shares are of.
({List<ProductDemandRow> rows, int totalOrders}) productDemand(
  Iterable<DemandOrder> orders,
  Iterable<DateTime> months,
) {
  final wanted = months.toSet();
  final all = <String>{};
  final byProduct = <String, Set<String>>{};
  final categoryOf = <String, String>{};
  for (final o in orders) {
    if (!wanted.contains(o.month)) continue;
    all.add(o.id);
    byProduct.putIfAbsent(o.product, () => <String>{}).add(o.id);
    categoryOf.putIfAbsent(o.product, () => o.category);
  }
  final total = all.length;
  final rows =
      [
        for (final entry in byProduct.entries)
          ProductDemandRow(
            product: entry.key,
            category: categoryOf[entry.key]!,
            orders: entry.value.length,
            share: total == 0 ? 0 : entry.value.length / total * 100,
          ),
      ]..sort((a, b) {
        final byOrders = b.orders.compareTo(a.orders);
        return byOrders != 0
            ? byOrders
            : a.product.toLowerCase().compareTo(b.product.toLowerCase());
      });
  return (rows: rows, totalOrders: total);
}

/// The four demand levels, lightest to darkest green (the user's palette,
/// 2026-11-10), and none for zero orders.
enum DemandTier {
  none('No Orders', Color(0xFFE6E8E3)),
  veryLow('Very Low Demand', Color(0xFFDCEFE2)),
  low('Low Demand', Color(0xFF7FBF92)),
  moderate('Moderate Demand', Color(0xFF2E7951)),
  high('High Demand', Color(0xFF0B4225));

  const DemandTier(this.label, this.color);
  final String label;
  final Color color;
}

/// Where the demand levels start, from the counts being compared (the
/// months of one product and year, or the products of one month): set
/// around their average of the non-zero ones, so the busiest is High only
/// when it is well above the rest. Below half the average is Very Low,
/// below the average Low, below one and a half times it Moderate, and from
/// there High. Equal counts always share a level; zero is its own.
class DemandScale {
  final int lowFrom;
  final int moderateFrom;
  final int highFrom;

  const DemandScale._(this.lowFrom, this.moderateFrom, this.highFrom);

  factory DemandScale.of(Iterable<int> counts) {
    final positive = [
      for (final n in counts)
        if (n > 0) n,
    ];
    if (positive.isEmpty) return const DemandScale._(1, 1, 1);
    final mean = positive.reduce((a, b) => a + b) / positive.length;
    final low = (mean * 0.5).ceil().clamp(1, 1 << 30);
    final moderate = mean.ceil().clamp(low, 1 << 30);
    final high = (mean * 1.5).ceil().clamp(moderate, 1 << 30);
    return DemandScale._(low, moderate, high);
  }

  DemandTier tierOf(int count) {
    if (count <= 0) return DemandTier.none;
    if (count < lowFrom) return DemandTier.veryLow;
    if (count < moderateFrom) return DemandTier.low;
    if (count < highFrom) return DemandTier.moderate;
    return DemandTier.high;
  }

  /// The counts a level covers, for the legend ("1–40", "128+"); null for
  /// a level no count can reach on this scale.
  String? rangeOf(DemandTier tier) {
    String span(int from, int to) =>
        from > to ? '' : (from == to ? '$from' : '$from–$to');
    final text = switch (tier) {
      DemandTier.none => '0',
      DemandTier.veryLow => span(1, lowFrom - 1),
      DemandTier.low => span(lowFrom, moderateFrom - 1),
      DemandTier.moderate => span(moderateFrom, highFrom - 1),
      DemandTier.high => '$highFrom+',
    };
    return text.isEmpty ? null : text;
  }
}

/// "October 2026".
String demandMonthLabel(DateTime month) => DateFormat('MMMM y').format(month);

/// "Aug – Nov 2026" for a period of [months].
String demandPeriodLabel(List<DateTime> months) {
  if (months.isEmpty) return '—';
  final first = months.first;
  final last = months.last;
  if (first == last) return demandMonthLabel(first);
  return first.year == last.year
      ? '${DateFormat('MMM').format(first)} – ${DateFormat('MMM y').format(last)}'
      : '${DateFormat('MMM y').format(first)} – ${DateFormat('MMM y').format(last)}';
}

/// One row of Full Product Demand: its rank among all of the month's
/// products (by completed orders; equal counts share a rank), and its
/// demand level among them.
class RankedProductDemand {
  final int rank;
  final ProductDemandRow row;
  final DemandTier tier;
  const RankedProductDemand(this.rank, this.row, this.tier);
}

/// Full Product Demand for [month]: every product ordered, ranked, with
/// its level on the month's own scale, and the month's distinct completed
/// orders. The same figures the view and its report show.
class FullProductDemand {
  final DateTime month;
  final int totalOrders;
  final List<RankedProductDemand> ranked;
  final DemandScale scale;

  const FullProductDemand._(
    this.month,
    this.totalOrders,
    this.ranked,
    this.scale,
  );

  factory FullProductDemand.of(Iterable<DemandOrder> orders, DateTime month) {
    final demand = productDemand(orders, [month]);
    final scale = DemandScale.of([for (final r in demand.rows) r.orders]);
    final ranked = <RankedProductDemand>[];
    for (var i = 0; i < demand.rows.length; i++) {
      final row = demand.rows[i];
      // Competition ranking: 1, 2, 2, 4.
      final rank = i > 0 && demand.rows[i - 1].orders == row.orders
          ? ranked[i - 1].rank
          : i + 1;
      ranked.add(RankedProductDemand(rank, row, scale.tierOf(row.orders)));
    }
    return FullProductDemand._(month, demand.totalOrders, ranked, scale);
  }

  /// The rows a search and a category leave.
  List<RankedProductDemand> filtered({String query = '', String? category}) {
    final q = query.trim().toLowerCase();
    return [
      for (final r in ranked)
        if ((category == null || r.row.category == category) &&
            (q.isEmpty || r.row.product.toLowerCase().contains(q)))
          r,
    ];
  }

  /// The categories ordered this month, by name.
  List<String> get categories =>
      {for (final r in ranked) r.row.category}.toList()..sort();

  /// How many products are at each level.
  Map<DemandTier, int> get levels => {
    for (final tier in DemandTier.values)
      tier: ranked.where((r) => r.tier == tier).length,
  };
}

/// One product sold in one unit over a period: how much, in how many
/// completed orders, for how much. A product sold in two units (kg and
/// head) has a row for each: quantities in different units are never
/// added together.
class ProductQuantityRow {
  final String product;
  final String category;
  final String unit;
  final num quantity;
  final int orders;
  final num sales;

  const ProductQuantityRow({
    required this.product,
    required this.category,
    required this.unit,
    required this.quantity,
    required this.orders,
    required this.sales,
  });
}

/// A quantity row and its rank among the rows of its own unit.
class RankedQuantity {
  final int rank;
  final ProductQuantityRow row;
  const RankedQuantity(this.rank, this.row);
}

/// What was sold in [months], by product and unit, the most first.
List<ProductQuantityRow> productQuantities(
  Iterable<DemandOrder> orders,
  Iterable<DateTime> months,
) {
  final wanted = months.toSet();
  final quantity = <(String, String), num>{};
  final ids = <(String, String), Set<String>>{};
  final sales = <(String, String), num>{};
  final category = <(String, String), String>{};
  for (final o in orders) {
    if (!wanted.contains(o.month)) continue;
    final key = (o.product, o.unit.isEmpty ? 'unit' : o.unit);
    quantity[key] = (quantity[key] ?? 0) + o.quantity;
    sales[key] = (sales[key] ?? 0) + o.total;
    ids.putIfAbsent(key, () => <String>{}).add(o.id);
    category.putIfAbsent(key, () => o.category);
  }
  return [
    for (final key in quantity.keys)
      ProductQuantityRow(
        product: key.$1,
        category: category[key]!,
        unit: key.$2,
        quantity: quantity[key]!,
        orders: ids[key]!.length,
        sales: sales[key]!,
      ),
  ]..sort((a, b) {
    final byQuantity = b.quantity.compareTo(a.quantity);
    return byQuantity != 0
        ? byQuantity
        : a.product.toLowerCase().compareTo(b.product.toLowerCase());
  });
}

/// The units sold in [rows], the one with the most products first.
List<String> quantityUnits(List<ProductQuantityRow> rows) {
  final count = <String, int>{};
  for (final r in rows) {
    count[r.unit] = (count[r.unit] ?? 0) + 1;
  }
  return count.keys.toList()..sort((a, b) {
    final byCount = count[b]!.compareTo(count[a]!);
    return byCount != 0 ? byCount : a.compareTo(b);
  });
}

/// [rows] of one [unit], ranked by quantity (equal ones share a rank).
List<RankedQuantity> rankQuantities(
  List<ProductQuantityRow> rows,
  String unit,
) {
  final mine = [
    for (final r in rows)
      if (r.unit == unit) r,
  ];
  final out = <RankedQuantity>[];
  for (var i = 0; i < mine.length; i++) {
    final rank = i > 0 && mine[i - 1].quantity == mine[i].quantity
        ? out[i - 1].rank
        : i + 1;
    out.add(RankedQuantity(rank, mine[i]));
  }
  return out;
}

/// What Full Product Demand exports: exactly the table on screen (its
/// tab, filters and sort, every page), its summary and notes.
class FullDemandExport {
  final DateTime month;

  /// "By Orders" or "By Quantity Sold".
  final String analysis;
  final List<(String, String)> filters;
  final List<List<String>> summary;
  final List<String> headers;
  final List<List<String>> rows;
  final List<double> weights;
  final List<String> notes;

  const FullDemandExport({
    required this.month,
    required this.analysis,
    required this.filters,
    required this.summary,
    required this.headers,
    required this.rows,
    required this.weights,
    required this.notes,
  });
}
