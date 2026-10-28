import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import '../services/dashboard_analytics_service.dart';
import '../services/historical_demand_service.dart';
import '../services/market_price_helpers.dart';
import '../services/price_trend_service.dart';
import 'admin_analytics_widgets.dart'
    show AdminCommoditySearchField, matchCommodities;
import 'admin_dashboard_screen.dart'
    show AdminPalette, AdminRadii, AdminThemeScope;
import 'admin_info_dialogs.dart' show showAdminInfoPopup;
import 'admin_filter_controls.dart'
    show
        AdminPillDropdown,
        AdminYearPill,
        kAdminControlHeight,
        kAdminFontFamily;
import 'admin_overview_widgets.dart'
    show
        AdminChartCard,
        AdminChartEmpty,
        adminAxisTop,
        adminCompactPeso,
        adminGreenAt,
        adminLegendDot;

/// A pair of years the Market Trend charts compare.
typedef YearPair = ({int previous, int current});

/// "2026 vs 2027", one pair for each year after the first on record
/// ([pairs], newest first in the list).
class AdminYearPairPicker extends StatelessWidget {
  final List<YearPair> pairs;
  final YearPair value;
  final ValueChanged<YearPair> onChanged;

  const AdminYearPairPicker({
    super.key,
    required this.pairs,
    required this.value,
    required this.onChanged,
  });

  static String label(YearPair pair) => '${pair.previous} vs ${pair.current}';

  // The portal's dropdown: the same size and look as every other.
  @override
  Widget build(BuildContext context) => AdminPillDropdown<YearPair>(
    value: value,
    icon: Icons.date_range_outlined,
    items: [
      for (final pair in pairs.reversed)
        DropdownMenuItem(value: pair, child: Text(label(pair))),
    ],
    onChanged: onChanged,
  );
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

/// Analytics Dashboard → Market Demand: one product's demand month by
/// month, one year against another, as side-by-side bars — the earlier
/// year light green, the later dark green — so a change, or a season that
/// comes back every year, shows at a glance.
///
/// Demand is the number of completed orders of the product in each month
/// (see [DashboardAnalyticsService.monthlyCompletedOrders]), from AgriTrade+
/// completed orders only — never sample or typed-in figures. An order is
/// for one product, so it counts once. The Admin searches for the product
/// and picks the two years on year calendars; until a product is picked
/// the card asks for one rather than choosing it. Years run from the first
/// completed order — when AgriTrade+'s own records begin, never a year
/// before the app — to this year: while there is one year, its months are
/// shown alone, and the comparison appears once there are two. A month of
/// this year that has not come yet has no bar.
class AdminMarketDemandCard extends StatefulWidget {
  /// The completed orders the dashboard keeps live (DashboardDataService).
  final List<Map<String, dynamic>> completedOrders;

  /// The card's body height (the card beside it uses the same).
  final double bodyHeight;

  /// Why the orders could not be loaded, while they cannot: the card says
  /// so, with [onRetry], in place of the chart.
  final Object? error;
  final VoidCallback? onRetry;

  /// For tests: the moment "now".
  final DateTime? now;

  const AdminMarketDemandCard({
    super.key,
    required this.completedOrders,
    this.bodyHeight = 264,
    this.error,
    this.onRetry,
    this.now,
  });

  /// The earlier year's bars: light green.
  static const Color earlierColor = Color(0xFFA5D6A7);

  /// The later year's bars: dark green.
  static const Color laterColor = Color(0xFF2E7D32);

  /// The year calendars', search's and ⓘ's height.
  static const double controlHeight = 44;

  @override
  State<AdminMarketDemandCard> createState() => _AdminMarketDemandCardState();
}

class _AdminMarketDemandCardState extends State<AdminMarketDemandCard> {
  String? _product;
  int? _earlier;
  int? _later;

  /// What is typed in the search, once typing pauses: for saying when no
  /// product matches it.
  String _query = '';
  Timer? _queryTimer;

  /// Whether the summary under the chart is open: closed until the Admin
  /// opens it, so the chart has the room.
  bool _showSummary = false;

  /// Retry was pressed and the orders have not come back (or failed) yet.
  bool _retrying = false;

  // Worked out again only when the orders or the commodity list change,
  // not on every rebuild (typing, opening the summary).
  List<Map<String, dynamic>>? _namesOrders;
  List<Commodity>? _namesCommodities;
  List<String> _names = const [];
  int? _firstOrderYear;
  // …and the monthly counts, only when the product or years change too.
  Object? _seriesKey;
  ({List<int>? earlier, List<int> later})? _series;

  // Below this header width the controls (about 500 wide) go under the
  // title.
  static const double _stackBelow = 740;

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String _ordersText(int n) => '$n ${n == 1 ? 'order' : 'orders'}';

  static bool _isCompleted(Map<String, dynamic> order) =>
      (order['status'] ?? '').toString().toLowerCase() == 'completed';

  @override
  void didUpdateWidget(AdminMarketDemandCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.error, widget.error)) _retrying = false;
  }

  @override
  void dispose() {
    _queryTimer?.cancel();
    super.dispose();
  }

  // The commodity list, and any product with completed orders that is not
  // on it — every completed order can be looked up; and the first year
  // with a completed order.
  List<String> _productNames() {
    final commodities = CommodityRegistry.instance.all;
    if (!identical(_namesOrders, widget.completedOrders) ||
        !identical(_namesCommodities, commodities)) {
      _namesOrders = widget.completedOrders;
      _namesCommodities = commodities;
      _names = matchCommodities({
        for (final commodity in commodities) commodity.name,
        for (final order in widget.completedOrders)
          if (_isCompleted(order))
            ?DashboardAnalyticsService.demandProduct(order),
      }, '');
      final years = DashboardAnalyticsService.completedOrderYears(
        widget.completedOrders,
      );
      _firstOrderYear = years.isEmpty ? null : years.reduce(math.min);
    }
    return _names;
  }

  // Both years counted the same way: [DashboardAnalyticsService
  // .monthlyCompletedOrders]. Null for the earlier year while there is none.
  ({List<int>? earlier, List<int> later}) _seriesFor(
    String product,
    int? earlier,
    int later,
  ) {
    final key = (
      widget.completedOrders,
      CommodityRegistry.instance.all,
      product,
      earlier,
      later,
    );
    if (key != _seriesKey) {
      _seriesKey = key;
      _series = (
        earlier: earlier == null
            ? null
            : DashboardAnalyticsService.monthlyCompletedOrders(
                widget.completedOrders,
                product,
                earlier,
              ),
        later: DashboardAnalyticsService.monthlyCompletedOrders(
          widget.completedOrders,
          product,
          later,
        ),
      );
    }
    return _series!;
  }

  void _typed(String text) {
    _queryTimer?.cancel();
    _queryTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = text);
    });
  }

  // Either calendar may pick any year offered. The two are kept in order —
  // the earlier year is always the light green one, whichever was picked
  // first — and never the same: picking the other's year swaps them.
  void _pickYear(int chosen, {required bool first, required YearPair pair}) {
    var a = first ? chosen : pair.previous;
    var b = first ? pair.current : chosen;
    if (a == b) {
      if (first) {
        b = pair.previous;
      } else {
        a = pair.current;
      }
    }
    setState(() {
      _earlier = math.min(a, b);
      _later = math.max(a, b);
    });
  }

  void _retry() {
    setState(() => _retrying = true);
    widget.onRetry?.call();
  }

  // How tall AdminCardHeader's title and subtitle are here: a 17px bold
  // line, 3px, then a 12px line.
  static double _headingHeight(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    double line(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Market Demand', style: base.merge(style)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return line(const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)) +
        3 +
        line(const TextStyle(fontSize: 12));
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return ListenableBuilder(
      listenable: CommodityRegistry.instance,
      builder: (context, _) {
        final now = widget.now ?? DateTime.now();
        final names = _productNames();
        final lastYear = now.year;
        // From the first year with a completed order; this year alone
        // until there is one.
        final firstYear = math.min(_firstOrderYear ?? lastYear, lastYear);
        bool offered(int? y) => y != null && y >= firstYear && y <= lastYear;
        // This year against the one before, until the Admin picks others.
        final pickedOk =
            offered(_earlier) && offered(_later) && _earlier! < _later!;
        final later = pickedOk ? _later! : lastYear;
        final int? earlier = pickedOk
            ? _earlier
            : (lastYear > firstYear ? lastYear - 1 : null);
        final product = names.contains(_product) ? _product : null;
        final query = _query.trim();
        final noMatch =
            query.isNotEmpty &&
            query.toLowerCase() != product?.toLowerCase() &&
            matchCommodities(names, query).isEmpty;

        return LayoutBuilder(
          builder: (context, box) {
            // Beside the title, the controls can make the header taller
            // than the card next to it (whose controls are
            // kAdminControlHeight): the body gives that back so the two
            // stay level.
            final beside = box.maxWidth - 40 >= _stackBelow;
            final heading = _headingHeight(context);
            final extra = beside
                ? math.max(
                    0.0,
                    AdminMarketDemandCard.controlHeight -
                        math.max(heading, kAdminControlHeight),
                  )
                : 0.0;
            return AdminChartCard(
              title: 'Market Demand',
              subtitle: 'Compare monthly product demand across selected years.',
              bodyHeight: widget.bodyHeight - extra,
              trailing: _controls(c, names, firstYear, lastYear, product, (
                previous: earlier ?? later,
                current: later,
              ), earlier != null),
              trailingStackBelow: _stackBelow,
              child: _body(
                c,
                now,
                names,
                product,
                noMatch,
                query,
                earlier,
                later,
              ),
            );
          },
        );
      },
    );
  }

  Widget _body(
    AdminPalette c,
    DateTime now,
    List<String> names,
    String? product,
    bool noMatch,
    String query,
    int? earlier,
    int later,
  ) {
    if (widget.error != null) return _errorState(c);
    if (noMatch) {
      return AdminChartEmpty(
        icon: Icons.search_off_rounded,
        message:
            'No product matches “$query”. Check the spelling or search for '
            'another product.',
      );
    }
    if (product == null) {
      return AdminChartEmpty(
        icon: Icons.manage_search_rounded,
        message: names.isEmpty
            ? 'No supported products to show yet.'
            : 'Search for a product to compare its completed orders month '
                  'by month across the selected years.',
      );
    }

    final series = _seriesFor(product, earlier, later);
    final a = series.earlier;
    final b = series.later;
    // The months of [later] that have begun: all twelve for a past year.
    final reached = later < now.year ? 12 : (later == now.year ? now.month : 0);
    final totalA = a?.fold<int>(0, (s, n) => s + n) ?? 0;
    final totalB = b.fold<int>(0, (s, n) => s + n);
    // Like for like: the same months of both years.
    final sameA = a?.take(reached).fold<int>(0, (s, n) => s + n) ?? 0;
    final sameB = b.take(reached).fold<int>(0, (s, n) => s + n);
    final change = a == null || sameA == 0 ? null : (sameB - sameA) / sameA;
    final changeLabel = reached == 12
        ? 'Change, full year'
        : 'Change, Jan–${_monthNames[reached - 1].substring(0, 3)}';
    // A year's month with the most completed orders; -1 with none.
    int busiest(List<int> monthly, int months) {
      var best = -1;
      for (var m = 0; m < months; m++) {
        if (monthly[m] > 0 && (best < 0 || monthly[m] > monthly[best])) {
          best = m;
        }
      }
      return best;
    }

    String busiestText(List<int> monthly, int months) {
      final m = busiest(monthly, months);
      return m < 0
          ? '—'
          : '${_monthNames[m].substring(0, 3)} · ${_ordersText(monthly[m])}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Room above the chart's top figure.
        const SizedBox(height: 8),
        Expanded(
          child: totalA == 0 && totalB == 0
              ? AdminChartEmpty(
                  icon: Icons.bar_chart_rounded,
                  message: earlier == null
                      ? 'No completed orders of $product in $later yet, so '
                            'there is no demand to show.'
                      : 'No completed orders of $product in $earlier or '
                            '$later, so there is no demand to compare.',
                )
              : _chart(c, product, a, b, reached, earlier, later),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 14,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (earlier != null)
                    _legend(c, AdminMarketDemandCard.earlierColor, '$earlier'),
                  _legend(c, AdminMarketDemandCard.laterColor, '$later'),
                  Text(
                    'Based on AgriTrade+ completed orders only.',
                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            _summaryToggle(c),
          ],
        ),
        // The figures behind the chart, under it; collapsible.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: _showSummary
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _summary(c, [
                    if (earlier != null)
                      ('$earlier', _ordersText(totalA), null, false),
                    (
                      '$later',
                      '${_ordersText(totalB)}${later == now.year ? ' so far' : ''}',
                      null,
                      false,
                    ),
                    if (earlier != null)
                      (
                        changeLabel,
                        change == null
                            ? '—'
                            : '${change >= 0 ? '+' : '−'}'
                                  '${(change.abs() * 100).round()}%',
                        change == null
                            ? 'No completed orders in those months of $earlier to '
                                  'compare with.'
                            : 'The same months of both years: ${_ordersText(sameA)} in '
                                  '$earlier, ${_ordersText(sameB)} in $later.',
                        false,
                      ),
                    if (a != null)
                      (
                        'Busiest month · $earlier',
                        busiestText(a, 12),
                        null,
                        false,
                      ),
                    (
                      'Busiest month · $later',
                      busiestText(b, reached),
                      null,
                      false,
                    ),
                  ]),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  // The orders could not be loaded: what happened, and a way to try again.
  // Never a chart from made-up or partial figures.
  Widget _errorState(AdminPalette c) => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: c.red, size: 28),
          const SizedBox(height: 10),
          Text(
            'Could not load completed orders. Check your connection and try '
            'again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 13),
          ),
          if (widget.onRetry != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: _retrying
                  ? Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.green,
                        ),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: _retry,
                      style: TextButton.styleFrom(foregroundColor: c.green),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text(
                        'Retry',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
            ),
          ],
        ],
      ),
    ),
  );

  // Opens or closes the summary under the chart.
  Widget _summaryToggle(AdminPalette c) => TextButton.icon(
    onPressed: () => setState(() => _showSummary = !_showSummary),
    style: TextButton.styleFrom(
      foregroundColor: c.textSecondary,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    iconAlignment: IconAlignment.end,
    icon: Icon(
      _showSummary ? Icons.expand_less_rounded : Icons.expand_more_rounded,
      size: 18,
    ),
    label: Text(
      _showSummary ? 'Hide summary' : 'Show summary',
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );

  // The two years, the product search and what demand means, one height
  // and level with each other; wrapping onto more rows when narrow. All
  // pills, as everywhere in the portal.
  Widget _controls(
    AdminPalette c,
    List<String> names,
    int firstYear,
    int lastYear,
    String? product,
    YearPair pair,
    bool comparing,
  ) {
    const height = AdminMarketDemandCard.controlHeight;
    // Room for the calendar icon, a whole year and the arrow.
    Widget year(int value, {required bool first}) => AdminYearPill(
      year: value,
      firstYear: firstYear,
      lastYear: lastYear,
      width: 128,
      height: height,
      semanticLabel: first ? 'Earlier year' : 'Later year',
      onChanged: (y) => _pickYear(y, first: first, pair: pair),
    );
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Earlier "vs" later; one year alone until there are two.
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            if (comparing) ...[
              year(pair.previous, first: true),
              Text(
                'vs',
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            year(pair.current, first: false),
          ],
        ),
        AdminCommoditySearchField(
          // Shows the product now shown.
          key: ValueKey('market-demand-$product'),
          commodities: names,
          selected: product,
          hint: 'Search product',
          width: 180,
          height: height,
          semanticLabel: 'Search product for Market Demand',
          onQueryChanged: _typed,
          onSelected: (name) {
            _queryTimer?.cancel();
            setState(() {
              _product = name;
              _query = name;
            });
          },
        ),
        // How demand is counted: opened on a click, not on hover.
        SizedBox.square(
          dimension: height,
          child: IconButton(
            tooltip: 'How Market Demand is counted',
            onPressed: () => showAdminInfoPopup(
              context,
              title: 'How Market Demand is counted',
              paragraphs: const [
                'Demand = the number of completed orders of the product in '
                    'each month, dated by when each order was completed. Each '
                    'order is for one product, so it counts once.',
                'Pending, cancelled and rejected orders are not counted. '
                    'Orders are counted, not kilos, pieces or heads, as units '
                    'differ.',
                'Every listing of a product counts under it: Native Chicken '
                    'is Chicken. Both years are counted the same way.',
                'The earlier year is light green and the later year dark '
                    'green. A month of this year that has not come yet has no '
                    'bar.',
                'From AgriTrade+ completed orders only, not the whole market '
                    'of Laurel, Batangas.',
              ],
            ),
            icon: Icon(Icons.info_outline, size: 20, color: c.textSecondary),
          ),
        ),
      ],
    );
  }

  // The figures behind the chart, on their own row: wrapping on a wide
  // card, one line that scrolls sideways on a narrow one.
  Widget _summary(
    AdminPalette c,
    List<(String label, String value, String? help, bool attention)> items,
  ) {
    final chips = [
      for (final (label, value, help, attention) in items)
        Tooltip(
          message: help ?? '',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(AdminRadii.control),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label  ',
                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                  ),
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      color: attention ? c.amber : c.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < 600
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(spacing: 8, children: chips),
            )
          : Wrap(spacing: 8, runSpacing: 6, children: chips),
    );
  }

  Widget _legend(AdminPalette c, Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      adminLegendDot(color),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: c.textSecondary, fontSize: 11)),
    ],
  );

  // Twelve months, January to December; in each, the earlier year's bar
  // then the later year's. A month of [later] not reached yet has no bar.
  Widget _chart(
    AdminPalette c,
    String product,
    List<int>? a,
    List<int> b,
    int reached,
    int? earlier,
    int later,
  ) {
    final highest = [...?a, ...b].fold<int>(0, math.max);
    // Whole orders in about four steps, the top step just above the
    // tallest bar.
    final step = math.max(1.0, adminAxisTop(highest / 4));
    final top = ((highest / step).floor() + 1) * step;
    final axisStyle = TextStyle(color: c.textSecondary, fontSize: 10.5);
    const light = AdminMarketDemandCard.earlierColor;
    const dark = AdminMarketDemandCard.laterColor;
    const radius = BorderRadius.vertical(top: Radius.circular(4));
    const barsSpace = 3.0;

    return LayoutBuilder(
      builder: (context, box) {
        // Bars as wide as a month's share of the chart allows, so all
        // twelve months fit on a narrow card too.
        final month = (box.maxWidth - 46) / 12;
        final width = a == null
            ? (month * 0.45).clamp(6.0, 18.0)
            : ((month * 0.62 - barsSpace) / 2).clamp(4.0, 14.0);
        return BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            minY: 0,
            maxY: top,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: step,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: c.border, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                axisNameWidget: Text('Completed Orders', style: axisStyle),
                axisNameSize: 16,
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: step,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(value.round().toString(), style: axisStyle),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (value, meta) {
                    final m = value.toInt();
                    if (m < 0 || m > 11) return const SizedBox.shrink();
                    return SideTitleWidget(
                      meta: meta,
                      space: 4,
                      child: Text(
                        _monthNames[m].substring(0, 3),
                        style: axisStyle,
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => c.textPrimary,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                // Either bar of a month: the product and both years'
                // figures.
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final m = group.x;
                  return BarTooltipItem(
                    '$product · ${_monthNames[m]}\n',
                    const TextStyle(
                      fontFamily: kAdminFontFamily,
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      TextSpan(
                        text:
                            '${a == null ? '' : '$earlier: ${_ordersText(a[m])}\n'}'
                            '$later: ${m < reached ? _ordersText(b[m]) : 'not yet'}',
                        style: const TextStyle(
                          fontFamily: kAdminFontFamily,
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            barGroups: [
              for (var m = 0; m < 12; m++)
                BarChartGroupData(
                  x: m,
                  barsSpace: barsSpace,
                  barRods: [
                    if (a != null)
                      BarChartRodData(
                        toY: a[m].toDouble(),
                        width: width,
                        color: light,
                        borderRadius: radius,
                      ),
                    BarChartRodData(
                      toY: m < reached ? b[m].toDouble() : 0,
                      width: width,
                      color: m < reached ? dark : Colors.transparent,
                      borderRadius: radius,
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
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
  // The pair the Admin picked; the newest until then.
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
        final pairs = PriceTrendService.yearPairs(
          PriceTrendService.yearsOnRecord(widget.completedOrders, now),
        );
        // Null while there is one year on record: that year alone.
        final YearPair? pair = pairs.contains(_picked)
            ? _picked
            : (pairs.isEmpty ? null : pairs.last);
        final year = pair?.current ?? now.year;
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
          // The year shown, in the same pill, until there is a second.
          trailing: pair == null
              ? AdminPillDropdown<int>(
                  value: year,
                  icon: Icons.date_range_outlined,
                  items: [DropdownMenuItem(value: year, child: Text('$year'))],
                  onChanged: (_) {},
                )
              : AdminYearPairPicker(
                  pairs: pairs,
                  value: pair,
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
