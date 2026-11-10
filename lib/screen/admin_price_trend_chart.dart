import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/historical_demand_service.dart';
import '../services/market_price_helpers.dart';
import '../services/price_trend_service.dart';
import 'admin_dashboard_screen.dart'
    show AdminPalette, AdminRadii, AdminThemeScope;
import 'admin_filter_controls.dart'
    show AdminYearPill, kAdminControlHeight, kAdminFontFamily;
import 'admin_overview_widgets.dart'
    show adminAxisTop, adminCompactPeso, adminGreenAt, adminLegendDot;

/// A pair of years the Market Trend charts compare.
typedef YearPair = ({int previous, int current});

/// The years a chart compares, on year calendars (Market Demand, Price
/// Trend): the earlier "vs" the later, or the one year alone while
/// [earlier] is null (one year on record). Either calendar may pick any
/// year from [firstYear] to [lastYear]. The two are kept in order — the
/// earlier first, whichever was picked first — and never the same:
/// picking the other one's year swaps them.
class AdminYearCompare extends StatelessWidget {
  final int firstYear;
  final int lastYear;
  final int? earlier;
  final int later;
  final ValueChanged<YearPair> onChanged;
  final double height;

  const AdminYearCompare({
    super.key,
    required this.firstYear,
    required this.lastYear,
    required this.earlier,
    required this.later,
    required this.onChanged,
    this.height = kAdminControlHeight,
  });

  /// Each year calendar's width: room for the calendar icon, a whole year
  /// and the arrow.
  static const double yearWidth = 134;

  YearPair _ordered(int chosen, {required bool first}) {
    final previous = earlier ?? later;
    var a = first ? chosen : previous;
    var b = first ? later : chosen;
    if (a == b) {
      if (first) {
        b = previous;
      } else {
        a = later;
      }
    }
    return (previous: math.min(a, b), current: math.max(a, b));
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    // Room for the calendar icon, a whole year and the arrow.
    Widget year(int value, {required bool first}) => AdminYearPill(
      year: value,
      firstYear: firstYear,
      lastYear: lastYear,
      width: yearWidth,
      height: height,
      semanticLabel: first ? 'Earlier year' : 'Later year',
      onChanged: (y) => onChanged(_ordered(y, first: first)),
    );
    final first = earlier;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        if (first != null) ...[
          year(first, first: true),
          Text(
            'vs',
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        year(later, first: false),
      ],
    );
  }
}

/// Two lines, January to December: [years]' previous year in blue and the
/// current one in green — or the current one alone while [previous] is
/// null (one year on record). A null month is a gap in its line.
class AdminYearComparisonChart extends StatelessWidget {
  final YearPair years;
  final List<double?>? previous;
  final List<double?> current;

  /// Left-axis labels.
  final String Function(double value) axisLabel;

  /// A month's figure in the tooltip.
  final String Function(double value) valueLabel;

  const AdminYearComparisonChart({
    super.key,
    required this.years,
    required this.previous,
    required this.current,
    required this.axisLabel,
    required this.valueLabel,
  });

  static Color previousColor(AdminPalette c) => c.blue;
  static Color currentColor(AdminPalette c) => adminGreenAt(c, 1);

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    // The axis fits the prices instead of starting at zero, so a move from
    // ₱175 to ₱205 shows as the rise it is, not a flat line.
    final known = [...?previous, ...current].whereType<double>();
    final axis = adminFittedAxis(
      known.fold<double>(double.infinity, math.min),
      known.fold<double>(0, math.max),
    );
    final axisStyle = TextStyle(color: c.textSecondary, fontSize: 11);
    // The lines in order, and each one's colour and year.
    final series = [?previous, current];
    final colors = [if (previous != null) previousColor(c), currentColor(c)];
    final yearOf = [if (previous != null) years.previous, years.current];
    String monthName(double x) =>
        DateFormat('MMM').format(DateTime(2000, x.toInt() + 1));

    LineChartBarData line(List<double?> monthly, Color color) =>
        LineChartBarData(
          spots: [
            for (var m = 0; m < 12; m++)
              monthly[m] == null
                  ? FlSpot.nullSpot
                  : FlSpot(m.toDouble(), monthly[m]!),
          ],
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 2.5,
          isStrokeCapRound: true,
          dotData: FlDotData(
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
              radius: 3.5,
              color: color,
              strokeWidth: 2,
              strokeColor: c.surface,
            ),
          ),
        );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 11,
        minY: axis.min,
        maxY: axis.max,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          verticalInterval: 1,
          horizontalInterval: axis.step,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: c.border, strokeWidth: 1),
          getDrawingVerticalLine: (_) =>
              FlLine(color: c.border, strokeWidth: 1, dashArray: const [3, 4]),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: axis.step,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  axisLabel(value),
                  textAlign: TextAlign.right,
                  style: axisStyle,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final m = value.toInt();
                if (value != m || m < 0 || m > 11) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(monthName(value), style: axisStyle),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => c.textPrimary,
            fitInsideHorizontally: true,
            getTooltipItems: (touched) => [
              for (final spot in touched)
                LineTooltipItem(
                  '${monthName(spot.x)} ${yearOf[spot.barIndex]}: '
                  '${valueLabel(spot.y)}',
                  TextStyle(
                    fontFamily: kAdminFontFamily,
                    color: Color.lerp(colors[spot.barIndex], Colors.white, 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (final (i, monthly) in series.indexed) line(monthly, colors[i]),
        ],
      ),
    );
  }
}

// One entry per year under a chart: its colour and what it adds up to —
// the previous year's then the current one's, or the current one's alone.
Widget _yearLegend(AdminPalette c, List<String> lines, {Widget? trailing}) {
  final style = TextStyle(color: c.textSecondary, fontSize: 11.5);
  Widget entry(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      adminLegendDot(color),
      const SizedBox(width: 6),
      Text(text, style: style),
    ],
  );
  return Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 16,
    runSpacing: 4,
    children: [
      if (lines.length > 1)
        entry(AdminYearComparisonChart.previousColor(c), lines.first),
      entry(AdminYearComparisonChart.currentColor(c), lines.last),
      ?trailing,
    ],
  );
}

/// The heading of a part of a card (Market Change Analysis → Price Trend,
/// Last 30 Days): a title over a subtitle, and any control on the right,
/// level with the title.
class AdminSubsectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  /// The space between the heading and what it heads.
  static const double gapBelow = 16;

  const AdminSubsectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 14.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.35),
        ),
      ],
    );
    final control = trailing;
    if (control == null) return heading;
    return LayoutBuilder(
      // The control beside the title; under it when narrow.
      builder: (context, box) => box.maxWidth < 480
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [heading, const SizedBox(height: 10), control],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                const SizedBox(width: 16),
                control,
              ],
            ),
    );
  }
}

/// Market Change Analysis → Price Trend: [commodity]'s average price per
/// month, one year against another, from the prices farmers used and the
/// prices the Admin entered (see [PriceTrendService]). Its years run from
/// the first completed order to this year
/// ([PriceTrendService.yearsOnRecord]): one year's line alone while there
/// is one, then each year against the one before.
class AdminPriceTrendSection extends StatefulWidget {
  final String commodity;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> completedOrders;
  final List<HistoricalDemandRecord> historical;

  /// Lays out its heading and what is under it, for a card that sets them
  /// level with another part's; the heading over it otherwise.
  final Widget Function(Widget heading, Widget content)? arrange;

  /// For tests: the moment "now".
  final DateTime? now;

  const AdminPriceTrendSection({
    super.key,
    required this.commodity,
    required this.products,
    required this.completedOrders,
    required this.historical,
    this.arrange,
    this.now,
  });

  @override
  State<AdminPriceTrendSection> createState() => _AdminPriceTrendSectionState();
}

class _AdminPriceTrendSectionState extends State<AdminPriceTrendSection> {
  // The years the Admin picked; this year against the one before until
  // then.
  YearPair? _picked;
  late Stream<List<Map<String, dynamic>>> _reference = _referenceHistory();

  @override
  void didUpdateWidget(AdminPriceTrendSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commodity != widget.commodity) {
      _reference = _referenceHistory();
    }
  }

  // The commodity's dated reference prices from Price Management. Its
  // `market_prices` document is found by the name stored in it, since an
  // older document's id need not follow the name.
  Stream<List<Map<String, dynamic>>> _referenceHistory() async* {
    final name = widget.commodity.trim().toLowerCase();
    final prices = await FirebaseFirestore.instance
        .collection('market_prices')
        .get();
    final matches = prices.docs.where(
      (doc) =>
          (doc.data()['name'] ?? '').toString().trim().toLowerCase() == name,
    );
    if (matches.isEmpty) {
      yield const [];
      return;
    }
    yield* matches.first.reference
        .collection('history')
        .snapshots()
        .map((snap) => [for (final doc in snap.docs) doc.data()]);
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _reference,
      builder: (context, reference) {
        final prices = PriceTrendService.collect(
          commodity: widget.commodity,
          products: widget.products,
          completedOrders: widget.completedOrders,
          referenceHistory: reference.data ?? const [],
          historical: widget.historical,
        );
        final unit = prices.unit;
        final now = widget.now ?? DateTime.now();
        final years = PriceTrendService.yearsOnRecord(
          widget.completedOrders,
          now,
        );
        final picked = _picked;
        bool offered(int y) => years.contains(y);
        // Null while there is one year on record: that year alone.
        final YearPair? pair =
            picked != null &&
                offered(picked.previous) &&
                offered(picked.current) &&
                picked.previous < picked.current
            ? picked
            : (years.length < 2
                  ? null
                  : (previous: years.last - 1, current: years.last));
        final year = pair?.current ?? years.last;
        final previous = pair == null
            ? null
            : PriceTrendService.monthlyAverages(prices.points, pair.previous);
        final current = PriceTrendService.monthlyAverages(prices.points, year);
        final hasData = [...?previous, ...current].any((v) => v != null);
        final loading = !reference.hasData && !reference.hasError;

        final previousAverage = previous == null
            ? null
            : PriceTrendService.yearAverage(previous);
        final currentAverage = PriceTrendService.yearAverage(current);
        String average(int year, double? value) => value == null
            ? '$year · no prices'
            : '$year · avg ${formatPeso(value)}/$unit';
        Widget? change;
        if (previousAverage != null && currentAverage != null) {
          final percent =
              (currentAverage - previousAverage) / previousAverage * 100;
          change = Text(
            percent.abs() < 0.5
                ? 'about the same'
                : '${percent > 0 ? 'up' : 'down'} '
                      '${percent.abs().toStringAsFixed(1)}%',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          );
        }
        final inYears = prices.points.where(
          (p) => p.date.year == year || p.date.year == pair?.previous,
        );
        // "1 completed sale", "2 completed sales".
        String part(PriceTrendSource source, String thing) {
          final n = inYears.where((p) => p.source == source).length;
          return '$n $thing${n == 1 ? '' : 's'}';
        }

        final heading = AdminSubsectionHeader(
          title: 'Price Trend',
          subtitle:
              'Average ${widget.commodity} price per $unit each '
              'month — from farmer listings and sales, and Admin '
              'reference and imported prices',
          // Year calendars, as the portal's other year pickers.
          trailing: AdminYearCompare(
            firstYear: years.first,
            lastYear: years.last,
            earlier: pair?.previous,
            later: year,
            height: kAdminControlHeight,
            onChanged: (picked) => setState(() => _picked = picked),
          ),
        );
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reference.hasError)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Reference prices from Price Management could not be '
                  'loaded, so they are not included here.',
                  style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                ),
              ),
            if (!hasData)
              loading
                  ? const SizedBox(height: 40)
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 28,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: c.surfaceAlt,
                        borderRadius: BorderRadius.circular(AdminRadii.card),
                      ),
                      child: Text(
                        'No ${widget.commodity} prices on record for '
                        '${pair == null ? '$year' : '${pair.previous} or $year'} '
                        'yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                    )
            else ...[
              SizedBox(
                height: 240,
                child: AdminYearComparisonChart(
                  years: pair ?? (previous: year, current: year),
                  previous: previous,
                  current: current,
                  axisLabel: adminCompactPeso,
                  valueLabel: (v) => '${formatPeso(v)}/$unit',
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: _yearLegend(c, [
                  if (pair != null) average(pair.previous, previousAverage),
                  average(year, currentAverage),
                ], trailing: change),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Based on '
                  '${part(PriceTrendSource.farmerListing, 'farmer listing')}, '
                  '${part(PriceTrendSource.farmerSale, 'completed sale')}, '
                  '${part(PriceTrendSource.adminReference, 'Admin reference price')} '
                  'and ${part(PriceTrendSource.adminImport, 'imported record')}; '
                  'retail prices per $unit only.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                ),
              ),
            ],
          ],
        );
        return widget.arrange?.call(heading, content) ??
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: AdminSubsectionHeader.gapBelow),
                content,
              ],
            );
      },
    );
  }
}

/// A value axis that fits [lowest]..[highest] in about four even, round
/// steps, with a little room above and below — never below zero. For a
/// chart where the change matters more than the distance from zero (a
/// price that moves between ₱175 and ₱205).
({double min, double max, double step}) adminFittedAxis(
  double lowest,
  double highest,
) {
  if (!lowest.isFinite || highest <= 0) return (min: 0, max: 4, step: 1);
  final span = highest - lowest;
  // A flat line still gets a band around it.
  final pad = math.max(span * 0.25, highest * 0.04);
  var step = adminAxisTop((span + pad * 2) / 4);
  // adminAxisTop gives 1, 2, 4, 5, 8 or 10 × a power of ten; steps of 4
  // and 8 read oddly on a price axis, so use 5 and 10 instead.
  final magnitude = math
      .pow(10, (math.log(step) / math.ln10).floor())
      .toDouble();
  final fraction = step / magnitude;
  if (fraction == 4) step = 5 * magnitude;
  if (fraction == 8) step = 10 * magnitude;
  final min = math.max(0.0, ((lowest - pad) / step).floor() * step);
  final max = ((highest + pad) / step).ceil() * step;
  return (min: min, max: max == min ? min + step : max, step: step);
}
