import 'package:flutter/material.dart' show DateTimeRange;

/// The periods the Orders screen can show, by the day an order was placed:
/// for buyers and farmers looking back over their transactions.
enum OrderDateFilter {
  all('All time'),
  today('Today'),
  last7Days('Last 7 days'),
  last30Days('Last 30 days'),
  last3Months('Last 3 months'),
  last6Months('Last 6 months'),
  thisYear('This year'),
  custom('Custom range');

  final String label;
  const OrderDateFilter(this.label);

  /// The days this period covers on [now], from the start of its first day
  /// to the end of today; null for [all]. [custom] is [customRange].
  DateTimeRange? rangeOn(DateTime now, {DateTimeRange? customRange}) {
    final today = DateTime(now.year, now.month, now.day);
    DateTimeRange from(DateTime start) =>
        DateTimeRange(start: start, end: today);
    return switch (this) {
      OrderDateFilter.all => null,
      OrderDateFilter.today => from(today),
      OrderDateFilter.last7Days => from(today.subtract(const Duration(days: 6))),
      OrderDateFilter.last30Days => from(
        today.subtract(const Duration(days: 29)),
      ),
      OrderDateFilter.last3Months => from(
        DateTime(today.year, today.month - 3, today.day),
      ),
      OrderDateFilter.last6Months => from(
        DateTime(today.year, today.month - 6, today.day),
      ),
      OrderDateFilter.thisYear => from(DateTime(today.year, 1, 1)),
      OrderDateFilter.custom => customRange,
    };
  }
}

/// Whether an order placed at [placed] falls in [range] (whole days, the
/// last one included). No range: every order. An order with no date yet
/// (just placed, not stamped by the server) counts as today.
bool placedIn(DateTime? placed, DateTimeRange? range, {required DateTime now}) {
  if (range == null) return true;
  final at = placed ?? now;
  final day = DateTime(at.year, at.month, at.day);
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  return !day.isBefore(start) && !day.isAfter(end);
}
