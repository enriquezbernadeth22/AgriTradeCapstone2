import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import 'market_price_helpers.dart';
import 'monthly_demand_service.dart' show DemandOrder;

/// MARKET CHANGE ANALYSIS (the user's design, 2026-11-10): for one product,
/// the chosen period against the one just before it, of the same length.
///
/// Four separate measures, each from records that exist:
///  * demand: distinct completed orders containing the product, by
///    completion date (never searches, never pending orders);
///  * local supply: new listings of the product posted in each period
///    (their posting dates are on record; past stock is not, so stock is
///    shown for today only and never compared);
///  * market price: the AgriTrade+ Current Market Average, the same figure
///    as the mobile app's ([liveAverageOfListings]), today against the
///    previous period's last day;
///  * net change: the difference in completed orders.
///
/// Nothing here explains a change: the summary says what moved, never why.

/// The periods the analysis can compare. Up to a month, day by day; the
/// 90 days week by week (the last week six days, in both periods alike).
enum ChangeRange {
  days7('Last 7 Days', 7, 1),
  days30('Last 30 Days', 30, 1),
  days90('Last 90 Days', 90, 7);

  const ChangeRange(this.label, this.days, this.bucketDays);
  final String label;
  final int days;
  final int bucketDays;
}

/// The chosen period and the one before it, as whole local days:
/// [currentStart] to [currentEnd] (exclusive), and [previousStart] up to
/// [currentStart].
class ChangeWindow {
  final ChangeRange range;
  final DateTime previousStart;
  final DateTime currentStart;
  final DateTime currentEnd;

  const ChangeWindow._(
    this.range,
    this.previousStart,
    this.currentStart,
    this.currentEnd,
  );

  /// The last [range] days up to and including [now]'s day.
  factory ChangeWindow.of(ChangeRange range, DateTime now) {
    final end = DateTime(now.year, now.month, now.day + 1);
    return ChangeWindow._(
      range,
      DateTime(end.year, end.month, end.day - range.days * 2),
      DateTime(end.year, end.month, end.day - range.days),
      end,
    );
  }

  /// The previous period's last moment: where its market average is read.
  DateTime get previousEnd => currentStart;

  bool inCurrent(DateTime d) =>
      !d.isBefore(currentStart) && d.isBefore(currentEnd);
  bool inPrevious(DateTime d) =>
      !d.isBefore(previousStart) && d.isBefore(currentStart);

  /// "Oct 12 – Nov 10, 2026" for the current period.
  String get currentLabel => rangeLabel(currentStart, currentEnd);

  /// The same for the previous period.
  String get previousLabel => rangeLabel(previousStart, currentStart);

  /// A span of whole days in words, its end exclusive.
  static String rangeLabel(DateTime from, DateTime toExclusive) {
    final last = DateTime(
      toExclusive.year,
      toExclusive.month,
      toExclusive.day - 1,
    );
    final day = DateFormat('MMM d');
    if (!last.isAfter(from)) return DateFormat('MMM d, y').format(from);
    return from.year == last.year
        ? '${day.format(from)} – ${day.format(last)}, ${last.year}'
        : '${DateFormat('MMM d, y').format(from)} – ${DateFormat('MMM d, y').format(last)}';
  }
}

/// One point of the trend: the same position (day or week) in both
/// periods, with each period's own dates and completed orders.
class TrendPoint {
  final int position;
  final String label;
  final DateTime currentFrom;
  final DateTime currentTo;
  final DateTime previousFrom;
  final DateTime previousTo;
  final int current;
  final int previous;

  const TrendPoint({
    required this.position,
    required this.label,
    required this.currentFrom,
    required this.currentTo,
    required this.previousFrom,
    required this.previousTo,
    required this.current,
    required this.previous,
  });
}

/// What a measure did between the two periods.
enum ChangeStatus {
  increased('Increased'),
  decreased('Decreased'),
  steady('Steady'),
  insufficient('Insufficient Data');

  const ChangeStatus(this.label);
  final String label;
}

/// One measure in both periods. [percent] is null when the previous
/// period has nothing to compare with.
class MetricChange {
  final ChangeStatus status;
  final double? current;
  final double? previous;
  final double? percent;

  const MetricChange(this.status, this.current, this.previous, this.percent);

  /// Compares [current] with [previous]: within [threshold] (a share, 0.05
  /// = 5%) either way is Steady. Without both, or with both zero, there is
  /// nothing to compare.
  factory MetricChange.compare(
    double? current,
    double? previous, {
    required double threshold,
  }) {
    if (current == null || previous == null) {
      return MetricChange(ChangeStatus.insufficient, current, previous, null);
    }
    if (current == 0 && previous == 0) {
      return MetricChange(ChangeStatus.insufficient, current, previous, null);
    }
    if (previous == 0) {
      return MetricChange(ChangeStatus.increased, current, previous, null);
    }
    final ratio = current / previous - 1;
    final status = ratio > threshold
        ? ChangeStatus.increased
        : ratio < -threshold
        ? ChangeStatus.decreased
        : ChangeStatus.steady;
    return MetricChange(status, current, previous, ratio * 100);
  }

  /// "+50%", "−12%", "0%"; empty without a percentage.
  String get percentLabel => formatChangePercent(percent);
}

/// A signed whole percentage: "+50%", "−12%", "0%"; empty for null.
String formatChangePercent(double? percent) {
  if (percent == null) return '';
  final rounded = percent.round();
  if (rounded == 0) return '0%';
  return rounded > 0 ? '+$rounded%' : '−${rounded.abs()}%';
}

/// The whole analysis for one product and period.
class MarketChange {
  final String product;
  final String unit;
  final ChangeWindow window;
  final List<TrendPoint> trend;

  /// Distinct completed orders containing the product, in each period.
  final int currentOrders;
  final int previousOrders;
  final MetricChange demand;

  /// New listings posted in each period.
  final int currentListings;
  final int previousListings;
  final MetricChange supply;

  /// Today's stock on sale, in the product's own unit, across this many
  /// active listings in that unit; never compared, as past stock is not
  /// on record.
  final double availableStock;
  final int activeListings;

  /// The Current Market Average today and on the previous period's last
  /// day.
  final MetricChange price;

  const MarketChange({
    required this.product,
    required this.unit,
    required this.window,
    required this.trend,
    required this.currentOrders,
    required this.previousOrders,
    required this.demand,
    required this.currentListings,
    required this.previousListings,
    required this.supply,
    required this.availableStock,
    required this.activeListings,
    required this.price,
  });

  /// Current minus previous completed orders.
  int get netChange => currentOrders - previousOrders;

  /// True when there is nothing at all to show for the product.
  bool get isEmpty =>
      currentOrders == 0 &&
      previousOrders == 0 &&
      currentListings == 0 &&
      previousListings == 0 &&
      activeListings == 0 &&
      price.current == null &&
      price.previous == null;

  /// What changed, in plain sentences: observations only, never a cause.
  List<String> get summary {
    final current = window.range.label.toLowerCase();
    String orders(num n) =>
        '${_whole(n)} completed ${n == 1 ? 'order' : 'orders'}';
    final lines = <String>[];

    // Demand and completed-order activity.
    if (demand.status == ChangeStatus.insufficient) {
      lines.add(
        'No completed orders of $product in either period, so demand cannot be compared.',
      );
    } else if (demand.percent == null) {
      lines.add(
        '$product had ${orders(currentOrders)} in the $current and none in the period before.',
      );
    } else {
      final verb = switch (demand.status) {
        ChangeStatus.increased => 'rose ${demand.percentLabel.substring(1)}',
        ChangeStatus.decreased => 'fell ${demand.percentLabel.substring(1)}',
        _ => 'held steady',
      };
      lines.add(
        'Demand for $product $verb: ${orders(currentOrders)} in the $current '
        'against ${_whole(previousOrders)} in the period before '
        '(${netChange >= 0 ? '+' : '−'}${netChange.abs()}).',
      );
    }

    // Busiest point of the current period, when there is one.
    if (currentOrders > 0) {
      final busiest = trend.reduce((a, b) => b.current > a.current ? b : a);
      final when = window.range.bucketDays == 1
          ? DateFormat('MMM d').format(busiest.currentFrom)
          : 'the week of ${DateFormat('MMM d').format(busiest.currentFrom)}';
      lines.add('Completed orders peaked on $when with ${busiest.current}.');
    }

    // Supply.
    final stock = activeListings == 0
        ? 'No listing is on sale now.'
        : '${formatStock(availableStock, unit)} is on sale now across '
              '${_plural(activeListings, 'active listing')}.';
    if (supply.status == ChangeStatus.insufficient) {
      lines.add('No new listings were posted in either period. $stock');
    } else {
      lines.add(
        '${_plural(currentListings, 'new listing')} posted in the $current '
        'against $previousListings in the period before. $stock',
      );
    }

    // Price.
    if (price.status == ChangeStatus.insufficient) {
      lines.add(
        price.current == null
            ? 'No active listing to give a Current Market Average.'
            : 'Current Market Average ${formatPriceWithUnit(price.current!, unit)}; '
                  'no listing on record at the end of the previous period to compare with.',
      );
    } else {
      final word = switch (price.status) {
        ChangeStatus.increased => 'up ${price.percentLabel.substring(1)}',
        ChangeStatus.decreased => 'down ${price.percentLabel.substring(1)}',
        _ => 'about the same',
      };
      lines.add(
        'The Current Market Average is ${formatPriceWithUnit(price.current!, unit)}, '
        '$word from ${formatPriceWithUnit(price.previous!, unit)} at the end of '
        'the previous period.',
      );
    }
    lines.add(
      'These are observed changes in AgriTrade+ records; they do not by '
      'themselves show what caused them.',
    );
    return lines;
  }

  static String _whole(num n) => NumberFormat.decimalPattern().format(n);
  static String _plural(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';
}

class MarketChangeService {
  const MarketChangeService._();

  /// A change in completed orders or new listings beyond this, either way.
  static const double countThreshold = 0.10;

  /// A change in the market average beyond this, either way.
  static const double priceThreshold = 0.05;

  /// The analysis of [product] over [range] up to [now], from the
  /// dashboard's completed [orders] (each once) and the listings
  /// ([products], plain maps).
  static MarketChange analyze({
    required String product,
    required ChangeRange range,
    required Iterable<DemandOrder> orders,
    required Iterable<Map<String, dynamic>> products,
    required DateTime now,
  }) {
    final window = ChangeWindow.of(range, now);
    final key = product.trim().toLowerCase();
    final unit = unitForCommodity(product);

    // ---- Completed orders, by position in each period. ----
    final buckets = (range.days / range.bucketDays).ceil();
    final current = List.filled(buckets, 0);
    final previous = List.filled(buckets, 0);
    final seen = <String>{};
    for (final order in orders) {
      if (order.product.trim().toLowerCase() != key) continue;
      if (!seen.add(order.id)) continue;
      final d = order.completed;
      if (window.inCurrent(d)) {
        current[_bucket(window.currentStart, d, range)]++;
      } else if (window.inPrevious(d)) {
        previous[_bucket(window.previousStart, d, range)]++;
      }
    }
    DateTime day(DateTime start, int offset) =>
        DateTime(start.year, start.month, start.day + offset);
    final trend = [
      for (var i = 0; i < buckets; i++)
        TrendPoint(
          position: i + 1,
          label: '${range.bucketDays == 1 ? 'Day' : 'Week'} ${i + 1}',
          currentFrom: day(window.currentStart, i * range.bucketDays),
          currentTo: day(
            window.currentStart,
            math.min((i + 1) * range.bucketDays, range.days),
          ),
          previousFrom: day(window.previousStart, i * range.bucketDays),
          previousTo: day(
            window.previousStart,
            math.min((i + 1) * range.bucketDays, range.days),
          ),
          current: current[i],
          previous: previous[i],
        ),
    ];
    final currentOrders = current.fold(0, (a, b) => a + b);
    final previousOrders = previous.fold(0, (a, b) => a + b);

    // ---- Listings: posted in each period, and today's stock. ----
    var posted = 0, postedBefore = 0, active = 0;
    var stock = 0.0;
    for (final listing in products) {
      if (listingProduct(listing)?.toLowerCase() != key) continue;
      if (listing['isSuspended'] == true) continue;
      final created = _date(listing['createdAt']);
      if (created != null) {
        if (window.inCurrent(created)) {
          posted++;
        } else if (window.inPrevious(created)) {
          postedBefore++;
        }
      }
      if (listing['isArchived'] == true) continue;
      final quantity = _number(listing['quantity']);
      if (quantity <= 0) continue;
      final listingUnit = (listing['unit'] ?? '').toString().trim();
      // Only stock in the product's own unit is added up.
      if (unit.isNotEmpty && listingUnit.isNotEmpty && listingUnit != unit) {
        continue;
      }
      active++;
      stock += quantity;
    }

    // ---- The Current Market Average, today and then. ----
    final averageNow = liveAverageOfListings(products, product);
    final averageThen = liveAverageOfListings(
      listingsOnSaleAt(products, window.previousEnd),
      product,
    );

    return MarketChange(
      product: product,
      unit: unit,
      window: window,
      trend: trend,
      currentOrders: currentOrders,
      previousOrders: previousOrders,
      demand: MetricChange.compare(
        currentOrders.toDouble(),
        previousOrders.toDouble(),
        threshold: countThreshold,
      ),
      currentListings: posted,
      previousListings: postedBefore,
      supply: MetricChange.compare(
        posted.toDouble(),
        postedBefore.toDouble(),
        threshold: countThreshold,
      ),
      availableStock: stock,
      activeListings: active,
      price: MetricChange.compare(
        averageNow,
        averageThen,
        threshold: priceThreshold,
      ),
    );
  }

  /// [selected] when it is one of [names]; otherwise the product with the
  /// most completed orders in the last 30 days (the first name on a tie or
  /// with none), so the analysis opens on one with something to show.
  static String? productOrDefault(
    List<String> names,
    String? selected,
    Iterable<DemandOrder> orders,
    DateTime now,
  ) {
    if (names.isEmpty) return null;
    if (selected != null && names.contains(selected)) return selected;
    final window = ChangeWindow.of(ChangeRange.days30, now);
    final counts = <String, Set<String>>{};
    for (final order in orders) {
      if (!window.inCurrent(order.completed)) continue;
      counts.putIfAbsent(order.product.toLowerCase(), () => {}).add(order.id);
    }
    var best = names.first;
    var most = 0;
    for (final name in names) {
      final n = counts[name.toLowerCase()]?.length ?? 0;
      if (n > most) {
        most = n;
        best = name;
      }
    }
    return best;
  }

  /// The product a listing is of: its frozen commodity, else the supported
  /// commodity its name matches, else its name.
  static String? listingProduct(Map<String, dynamic> listing) {
    final frozen = (listing['commodity'] ?? '').toString().trim();
    if (frozen.isNotEmpty) {
      return CommodityRegistry.instance.find(frozen)?.name ?? frozen;
    }
    final name = (listing['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    return matchSupportedCommodity(name) ?? name;
  }

  /// The listings as they stood on the marketplace at [at], for the Current
  /// Market Average of that day: posted by then, not yet archived (an
  /// archived listing with no archive date is left out, as its date is not
  /// known), never a suspended one. Stock then is not on record, so a
  /// listing sold out since still counts; its price is the one saved now,
  /// as earlier prices are not kept.
  static List<Map<String, dynamic>> listingsOnSaleAt(
    Iterable<Map<String, dynamic>> products,
    DateTime at,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final listing in products) {
      if (listing['isSuspended'] == true) continue;
      final created = _date(listing['createdAt']);
      if (created == null || !created.isBefore(at)) continue;
      if (listing['isArchived'] == true) {
        final archived = _date(listing['archivedAt']);
        if (archived == null || !archived.isAfter(at)) continue;
      }
      // As it stood then: on sale, with stock.
      out.add({...listing, 'isArchived': false, 'quantity': 1});
    }
    return out;
  }

  static int _bucket(DateTime start, DateTime d, ChangeRange range) {
    final day = DateTime(d.year, d.month, d.day).difference(start).inDays;
    return math.min(
      day ~/ range.bucketDays,
      (range.days / range.bucketDays).ceil() - 1,
    );
  }

  static DateTime? _date(dynamic value) =>
      value is Timestamp ? value.toDate() : (value is DateTime ? value : null);

  static double _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
}
