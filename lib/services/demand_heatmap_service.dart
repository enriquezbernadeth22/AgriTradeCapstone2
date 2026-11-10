import 'dart:math' as math;

import '../data/commodity_master_list.dart';
import 'dashboard_analytics_service.dart';

// The Admin Demand Heatmap's numbers (the final revision of 2026-11-09):
// completed orders only, never buyer searches. One set of functions feeds
// the map, the panels beside it and the exported report, so the three can
// never disagree for the same data and filters.

/// What the heat counts.
enum DemandMode {
  /// Unique buyers with a completed order, by their location.
  buyer('Buyer Demand'),

  /// Demand for product categories, counted as [DemandCounting] says.
  product('Product Demand');

  final String label;
  const DemandMode(this.label);
}

/// How Product Demand counts.
enum DemandCounting {
  /// Each buyer once per category (and once per area).
  uniqueBuyers('Unique Buyers per Category', 'buyer', 'buyers'),

  /// Each completed order once in its category (and its area).
  completedOrders('Completed Orders per Category', 'order', 'orders');

  final String label;
  final String unit;
  final String unitPlural;
  const DemandCounting(this.label, this.unit, this.unitPlural);

  /// "1 buyer", "3 orders".
  String count(int n) => '$n ${n == 1 ? unit : unitPlural}';
}

/// The category of a completed order that is on no category of the
/// commodity list.
const String kOtherCategory = 'Others';

/// One completed order, as the heatmap counts it.
class DemandRecord {
  final String orderId;
  final String buyerId;
  final String category;

  /// The buyer's area ("Barangay, Town"), or null when it is not known: then
  /// the order counts in the totals and the categories, never by location.
  final String? area;
  final double? lat;
  final double? lng;
  final DateTime completedAt;

  const DemandRecord({
    required this.orderId,
    required this.buyerId,
    required this.category,
    required this.area,
    required this.completedAt,
    this.lat,
    this.lng,
  });
}

/// The completed orders of [orders] (id → data) completed in
/// [start] (inclusive) to [end] (exclusive), one record per order however
/// often it is listed. Only an order whose buyer is a registered account
/// ([usersByUid]) counts, as everywhere in the analytics: test records with
/// a made-up buyer are not demand. [productsById] supplies a category the
/// order itself lacks.
List<DemandRecord> demandRecords({
  required Iterable<({String id, Map<String, dynamic> data})> orders,
  required Map<String, Map<String, dynamic>> usersByUid,
  Map<String, Map<String, dynamic>> productsById = const {},
  required DateTime start,
  required DateTime end,
}) {
  final seen = <String>{};
  final records = <DemandRecord>[];
  for (final order in orders) {
    final data = order.data;
    if ((data['status'] ?? '').toString().toLowerCase() != 'completed') {
      continue;
    }
    if (!seen.add(order.id)) continue;
    final completedAt = DashboardAnalyticsService.completionDate(data);
    if (completedAt == null ||
        completedAt.isBefore(start) ||
        !completedAt.isBefore(end)) {
      continue;
    }
    final buyerId = (data['buyerId'] ?? '').toString();
    final user = usersByUid[buyerId];
    if (buyerId.isEmpty || user == null) continue;
    final product = productsById[(data['productId'] ?? '').toString()];
    final area = DashboardAnalyticsService.buyerAreaOf(user, data);
    records.add(
      DemandRecord(
        orderId: order.id,
        buyerId: buyerId,
        category:
            DashboardAnalyticsService.orderCategory(data, product) ??
            kOtherCategory,
        area: area?.area,
        lat: area?.lat,
        lng: area?.lng,
        completedAt: completedAt,
      ),
    );
  }
  return records;
}

/// One area's demand: [count] unique buyers or completed orders.
class AreaDemand {
  final String area;
  final int count;
  final double? lat;
  final double? lng;
  const AreaDemand(this.area, this.count, {this.lat, this.lng});
}

/// Demand by location, most first (then A to Z): unique buyers or
/// completed orders ([counting]), in one [category] or all (null). With all
/// categories a buyer, or an order, still counts once in an area. Only
/// records with an area; an area is placed at the middle of its buyers'
/// pins, or at [areaCoordinates] (looked up by name) without any.
List<AreaDemand> areaDemand(
  List<DemandRecord> records, {
  DemandCounting counting = DemandCounting.uniqueBuyers,
  String? category,
  Map<String, ({double lat, double lng})> areaCoordinates = const {},
}) {
  final members = <String, Set<String>>{};
  final latSum = <String, double>{};
  final lngSum = <String, double>{};
  final located = <String, int>{};
  for (final r in records) {
    final area = r.area;
    if (area == null || (category != null && r.category != category)) continue;
    final key = counting == DemandCounting.uniqueBuyers ? r.buyerId : r.orderId;
    final added = members.putIfAbsent(area, () => {}).add(key);
    final lat = r.lat, lng = r.lng;
    if (added && lat != null && lng != null) {
      latSum[area] = (latSum[area] ?? 0) + lat;
      lngSum[area] = (lngSum[area] ?? 0) + lng;
      located[area] = (located[area] ?? 0) + 1;
    }
  }
  final result = [
    for (final e in members.entries)
      AreaDemand(
        e.key,
        e.value.length,
        lat: located[e.key] != null
            ? latSum[e.key]! / located[e.key]!
            : areaCoordinates[e.key]?.lat,
        lng: located[e.key] != null
            ? lngSum[e.key]! / located[e.key]!
            : areaCoordinates[e.key]?.lng,
      ),
  ];
  result.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.area.compareTo(b.area);
  });
  return result;
}

/// How many unique buyers ([DemandCounting.uniqueBuyers]) or completed
/// orders there are in [records], in one [category] or all. A buyer in
/// several areas or categories counts once.
int demandTotal(
  List<DemandRecord> records, {
  DemandCounting counting = DemandCounting.uniqueBuyers,
  String? category,
}) => {
  for (final r in records)
    if (category == null || r.category == category)
      counting == DemandCounting.uniqueBuyers ? r.buyerId : r.orderId,
}.length;

/// One category's demand and its share of [DemandSummary.denominator].
class CategoryDemand {
  final String category;
  final int count;

  /// count / every unique buyer (or every completed order) of the period,
  /// 0–100; null when there is none at all.
  final double? percent;
  const CategoryDemand(this.category, this.count, this.percent);
}

/// The Product Demand Summary: every category, most demand first (those
/// with none after, in the commodity list's order), and the denominator
/// its percentages are of.
({List<CategoryDemand> rows, int denominator}) categoryDemand(
  List<DemandRecord> records, {
  required DemandCounting counting,
  List<String> categories = kBuiltInCategories,
}) {
  final members = <String, Set<String>>{};
  for (final r in records) {
    members
        .putIfAbsent(r.category, () => {})
        .add(counting == DemandCounting.uniqueBuyers ? r.buyerId : r.orderId);
  }
  final denominator = demandTotal(records, counting: counting);
  final names = <String>[
    ...categories,
    for (final c in members.keys)
      if (!categories.contains(c) && c != kOtherCategory) c,
    if (members.containsKey(kOtherCategory)) kOtherCategory,
  ];
  final order = {for (var i = 0; i < names.length; i++) names[i]: i};
  final rows = [
    for (final name in names)
      CategoryDemand(
        name,
        members[name]?.length ?? 0,
        denominator == 0
            ? null
            : (members[name]?.length ?? 0) * 100 / denominator,
      ),
  ];
  rows.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0
        ? byCount
        : order[a.category]!.compareTo(order[b.category]!);
  });
  return (rows: rows, denominator: denominator);
}

/// The scale never tops out below this: with very little data an area with
/// one or two is low demand, not the highest merely because nothing else
/// has more. The same floor as the map's colours (kHeatScaleFloor).
const int kDemandScaleFloor = 5;

/// The legend's numbers for areas whose busiest has [busiest]: Low up to
/// [lowMax], Medium up to [mediumMax], High above it. Matches
/// [demandLevel] and the map's colours, a third of the scale each.
({int lowMax, int mediumMax}) demandThresholds(int busiest) {
  final scale = math.max(busiest, kDemandScaleFloor);
  return (lowMax: scale ~/ 3, mediumMax: (scale * 2) ~/ 3);
}

/// "Low", "Medium" or "High" for an area with [count], the busiest having
/// [busiest] (see [demandThresholds]).
String demandLevel(int count, int busiest) {
  final t = demandThresholds(busiest);
  return count <= t.lowMax
      ? 'Low'
      : count <= t.mediumMax
      ? 'Medium'
      : 'High';
}

/// Everything an exported Demand Heatmap report shows, worked out by the
/// same functions as the page ([demandReportData]).
class DemandReportData {
  final DemandMode mode;
  final String periodLabel;

  /// Product Demand only: the category chosen (null = All Categories) and
  /// how it counts. Buyer Demand always counts unique buyers.
  final String? category;
  final DemandCounting counting;

  /// Unique buyers with a completed order in the period, each once however
  /// many areas they ordered from.
  final int uniqueBuyers;

  /// Of those, the ones with a known location.
  final int locatedBuyers;

  /// Product Demand: unique buyers or completed orders in [category] (or
  /// all), each once.
  final int total;

  /// Product Demand: the summary rows and the denominator of their
  /// percentages (every unique buyer, or every completed order).
  final List<CategoryDemand> categories;
  final int denominator;

  /// Highest Demand Areas, as on the page.
  final List<AreaDemand> areas;

  const DemandReportData({
    required this.mode,
    required this.periodLabel,
    required this.category,
    required this.counting,
    required this.uniqueBuyers,
    required this.locatedBuyers,
    required this.total,
    required this.categories,
    required this.denominator,
    required this.areas,
  });

  bool get isEmpty => uniqueBuyers == 0;
}

/// The report for the page's current [mode], filters and [records].
DemandReportData demandReportData(
  List<DemandRecord> records, {
  required DemandMode mode,
  required String periodLabel,
  DemandCounting counting = DemandCounting.uniqueBuyers,
  String? category,
}) {
  final product = mode == DemandMode.product;
  final method = product ? counting : DemandCounting.uniqueBuyers;
  final chosen = product ? category : null;
  final summary = product
      ? categoryDemand(records, counting: method)
      : (rows: const <CategoryDemand>[], denominator: 0);
  return DemandReportData(
    mode: mode,
    periodLabel: periodLabel,
    category: chosen,
    counting: method,
    uniqueBuyers: demandTotal(records),
    locatedBuyers: demandTotal([
      for (final r in records)
        if (r.area != null) r,
    ]),
    total: demandTotal(records, counting: method, category: chosen),
    categories: summary.rows,
    denominator: summary.denominator,
    areas: areaDemand(records, counting: method, category: chosen),
  );
}
