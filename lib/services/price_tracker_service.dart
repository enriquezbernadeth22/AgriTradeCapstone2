import 'package:flutter/material.dart' show DateTimeRange, DateUtils;

import 'dashboard_analytics_service.dart';

/// The numbers behind the Admin Dashboard's price tracker (Average Price
/// vs. Admin Baseline): one commodity's quantity-weighted retail price in
/// completed orders, day by day, against the Admin's reference (baseline)
/// price from Price Management as it stood on each day.
///
/// Only real records: a day with no completed sale has no AgriTrade+
/// price, and a day before the first baseline has no baseline. Prices in
/// another unit than the commodity's are never mixed in.

/// One day's completed retail sales of a commodity.
class PriceDay {
  final DateTime day;

  /// Quantity-weighted: everything paid that day over everything bought.
  final double average;
  final double quantity;
  final int sales;

  const PriceDay({
    required this.day,
    required this.average,
    required this.quantity,
    required this.sales,
  });
}

/// A baseline price taking effect on [day] (until the next one).
class BaselineStep {
  final DateTime day;
  final double price;
  const BaselineStep(this.day, this.price);
}

/// The date ranges the tracker offers.
enum TrackerRange {
  week('7D', 7),
  month('30D', 30),
  quarter('90D', 90),
  all('All Data', null);

  const TrackerRange(this.label, this.days);
  final String label;
  final int? days;
}

String _norm(Object? s) => (s ?? '').toString().trim().toLowerCase();

/// The price paid per unit on [order]: its frozen unit price, or its total
/// over its quantity for an order without one.
double? _unitPrice(Map<String, dynamic> order) {
  final price = order['pricePerUnit'] ?? order['unitPrice'];
  if (price is num && price > 0) return price.toDouble();
  final total = order['total'];
  final quantity = order['quantity'];
  if (total is num && quantity is num && quantity > 0) {
    return total / quantity;
  }
  return null;
}

/// [commodity]'s completed retail sales sold in [unit], one entry per day
/// (oldest first), and how many of its completed retail sales were in
/// another unit (left out, never converted).
({List<PriceDay> days, int otherUnitSales}) dailyAveragePrices(
  Iterable<Map<String, dynamic>> orders, {
  required String commodity,
  required String unit,
}) {
  final paid = <DateTime, double>{};
  final bought = <DateTime, double>{};
  final count = <DateTime, int>{};
  var otherUnit = 0;
  for (final order in orders) {
    if (_norm(order['status']) != 'completed') continue;
    // Wholesale prices are lower by design; the baseline is a retail one.
    if (_norm(order['pricingType']) == 'wholesale') continue;
    if (_norm(DashboardAnalyticsService.orderCommodity(order)) !=
        _norm(commodity)) {
      continue;
    }
    final quantity = order['quantity'];
    final price = _unitPrice(order);
    final date = DashboardAnalyticsService.completionDate(order);
    if (quantity is! num || quantity <= 0 || price == null || date == null) {
      continue;
    }
    if (_norm(order['unit']) != _norm(unit)) {
      otherUnit++;
      continue;
    }
    final day = DateUtils.dateOnly(date);
    paid[day] = (paid[day] ?? 0) + price * quantity;
    bought[day] = (bought[day] ?? 0) + quantity;
    count[day] = (count[day] ?? 0) + 1;
  }
  final days = [
    for (final day in paid.keys.toList()..sort())
      PriceDay(
        day: day,
        average: paid[day]! / bought[day]!,
        quantity: bought[day]!,
        sales: count[day]!,
      ),
  ];
  return (days: days, otherUnitSales: otherUnit);
}

DateTime? _date(Object? v) {
  if (v is DateTime) return v;
  try {
    return (v as dynamic)?.toDate() as DateTime?;
  } catch (_) {
    return null;
  }
}

/// The baseline's changes in [unit], oldest first: the dated history of
/// Price Management ([history]: `price`, `unit`, `effectiveDate`) and the
/// commodity's current record ([current]: `baselinePrice`, `unit`,
/// `effectiveDate`). One price per day; on a day with two, the later
/// record wins.
List<BaselineStep> baselineSteps(
  Iterable<Map<String, dynamic>> history, {
  Map<String, dynamic>? current,
  required String unit,
}) {
  final byDay = <DateTime, ({double price, DateTime recorded})>{};
  void add(Object? price, Object? entryUnit, Object? effective, Object? at) {
    final date = _date(effective);
    if (price is! num || price <= 0 || date == null) return;
    // A record without a unit is in the commodity's own.
    if (_norm(entryUnit).isNotEmpty && _norm(entryUnit) != _norm(unit)) {
      return;
    }
    final day = DateUtils.dateOnly(date);
    final recorded = _date(at) ?? date;
    final before = byDay[day];
    if (before == null || !recorded.isBefore(before.recorded)) {
      byDay[day] = (price: price.toDouble(), recorded: recorded);
    }
  }

  for (final entry in history) {
    add(
      entry['price'],
      entry['unit'],
      entry['effectiveDate'],
      entry['recordedAt'],
    );
  }
  if (current != null) {
    add(
      current['baselinePrice'],
      current['unit'],
      current['effectiveDate'],
      current['updatedAt'],
    );
  }
  return [
    for (final day in byDay.keys.toList()..sort())
      BaselineStep(day, byDay[day]!.price),
  ];
}

/// The baseline in effect on [day]: the latest change on or before it.
double? baselineOn(List<BaselineStep> steps, DateTime day) {
  double? price;
  for (final step in steps) {
    if (step.day.isAfter(day)) break;
    price = step.price;
  }
  return price;
}

/// The days [range] covers up to [now] (both ends included). All Data
/// starts at the first sale or baseline on record.
DateTimeRange trackerWindow(
  TrackerRange range, {
  required DateTime now,
  required List<PriceDay> days,
  required List<BaselineStep> steps,
}) {
  final end = DateUtils.dateOnly(now);
  final length = range.days;
  if (length != null) {
    return DateTimeRange(
      start: end.subtract(Duration(days: length - 1)),
      end: end,
    );
  }
  final firsts = [
    if (days.isNotEmpty) days.first.day,
    if (steps.isNotEmpty) steps.first.day,
  ];
  final start = firsts.isEmpty
      ? end
      : firsts.reduce((a, b) => a.isBefore(b) ? a : b);
  return DateTimeRange(start: start.isAfter(end) ? end : start, end: end);
}

bool _inside(DateTime day, DateTimeRange window) =>
    !day.isBefore(window.start) && !day.isAfter(window.end);

/// What the tracker's cards say for [window]: the quantity-weighted
/// average of every sale in it, the baseline in effect at its end, and the
/// difference between the two; the change from its first sale day to its
/// last.
class PriceTrackerSummary {
  final List<PriceDay> days;
  final double? average;
  final int sales;
  final double? baseline;
  final DateTime? baselineSince;

  const PriceTrackerSummary._({
    required this.days,
    required this.average,
    required this.sales,
    required this.baseline,
    required this.baselineSince,
  });

  factory PriceTrackerSummary.of(
    List<PriceDay> allDays,
    List<BaselineStep> steps,
    DateTimeRange window,
  ) {
    final days = [
      for (final d in allDays)
        if (_inside(d.day, window)) d,
    ];
    final quantity = days.fold<double>(0, (s, d) => s + d.quantity);
    final paid = days.fold<double>(0, (s, d) => s + d.average * d.quantity);
    BaselineStep? since;
    for (final step in steps) {
      if (step.day.isAfter(window.end)) break;
      since = step;
    }
    return PriceTrackerSummary._(
      days: days,
      average: quantity > 0 ? paid / quantity : null,
      sales: days.fold<int>(0, (s, d) => s + d.sales),
      baseline: since?.price,
      baselineSince: since?.day,
    );
  }

  /// The average minus the baseline (negative: below it).
  double? get difference =>
      average == null || baseline == null ? null : average! - baseline!;

  /// [difference] as a share of the baseline, in percent.
  double? get differencePercent => difference == null || baseline == 0
      ? null
      : difference! / baseline! * 100;

  /// From the first sale day's price to the last one's, in percent; null
  /// with fewer than two sale days.
  double? get changePercent {
    if (days.length < 2 || days.first.average == 0) return null;
    return (days.last.average - days.first.average) / days.first.average * 100;
  }
}
