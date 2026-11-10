import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/market_change_service.dart';
import '../services/market_price_helpers.dart'
    show formatPriceWithUnit, formatStock;
import '../services/monthly_demand_service.dart' show DemandOrder;
import 'admin_analytics_widgets.dart' show AdminCommoditySearchField;
import 'admin_dashboard_screen.dart'
    show AdminEmptyState, AdminLoadingSpinner, AdminPalette, AdminThemeScope;
import 'admin_filter_controls.dart'
    show
        AdminPillDropdown,
        adminActionColor,
        adminCard,
        kAdminFontFamily,
        kAdminGold,
        kAdminGreen;
import 'admin_overview_widgets.dart' show AdminChartEmpty;

/// The previous period's line: the portal's golden yellow.
const Color _previousLine = kAdminGold;

/// Golden text on white (the line's own yellow is too pale to read).
const Color _previousText = Color(0xFFA87800);

/// The current period's line in Dark Mode, where the dark green would not
/// show.
const Color _currentLineDark = Color(0xFF7FBF92);

Color _currentLine(AdminPalette c) => c.isDark ? _currentLineDark : kAdminGreen;

/// What the analysis is of: the product and the period, chosen on the
/// dashboard's preview or the page and shared by both.
typedef MarketChangeChoice = ({String? product, ChangeRange range});

/// MARKET CHANGE ANALYSIS on the dashboard (the user's design,
/// 2026-11-10): a compact preview of the product's last period against the
/// one before (Demand Trend, Local Supply, Market Price) with View
/// Detailed Analysis, which opens [AdminMarketChangeAnalysis] inside the
/// portal. The chart and the summary are on that page only.
class AdminMarketChangePreview extends StatelessWidget {
  /// The supported commodities, sorted.
  final List<String> products;
  final List<DemandOrder> orders;
  final List<Map<String, dynamic>> listings;
  final MarketChangeChoice choice;
  final ValueChanged<String> onProductChanged;
  final VoidCallback onViewDetails;

  /// "Now", for tests.
  final DateTime? now;

  const AdminMarketChangePreview({
    super.key,
    required this.products,
    required this.orders,
    required this.listings,
    required this.choice,
    required this.onProductChanged,
    required this.onViewDetails,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final today = now ?? DateTime.now();
    final product = MarketChangeService.productOrDefault(
      products,
      choice.product,
      orders,
      today,
    );
    final data = product == null
        ? null
        : MarketChangeService.analyze(
            product: product,
            range: choice.range,
            orders: orders,
            products: listings,
            now: today,
          );

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Market Change Analysis',
          style: TextStyle(
            color: c.heading,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          data == null
              ? 'Recent marketplace changes for one product'
              : '${choice.range.label} · ${data.window.currentLabel}, '
                    'against the ${choice.range.days} days before',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
        ),
      ],
    );
    final search = AdminCommoditySearchField(
      key: ValueKey('changePreview-$product'),
      commodities: products,
      selected: product,
      width: 190,
      height: 36,
      hint: 'Search product',
      semanticLabel: 'Market Change Analysis product',
      onSelected: onProductChanged,
    );
    final button = FilledButton.icon(
      key: const Key('marketChangeViewDetails'),
      onPressed: data == null ? null : onViewDetails,
      style: FilledButton.styleFrom(
        backgroundColor: adminActionColor(c),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(
          fontFamily: kAdminFontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.arrow_forward, size: 16),
      label: const Text('View Detailed Analysis'),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: adminCard(c),
      child: LayoutBuilder(
        builder: (context, box) {
          // Beside Sales by Category the card is given its height: the
          // button then sits at its foot.
          final fill = box.hasTightHeight;
          final tilesInRow = box.maxWidth >= 460;
          final tiles = data == null
              ? const <Widget>[]
              : [
                  for (final kind in const [
                    _Insight.demand,
                    _Insight.supply,
                    _Insight.price,
                  ])
                    _InsightTile(
                      palette: c,
                      data: data,
                      kind: kind,
                      compact: true,
                    ),
                ];
          return Column(
            mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (box.maxWidth >= 420)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 12),
                    if (products.isNotEmpty) search,
                  ],
                )
              else ...[
                heading,
                if (products.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  search,
                ],
              ],
              const SizedBox(height: 14),
              if (data == null)
                const AdminEmptyState(
                  icon: Icons.insights_outlined,
                  title: 'No supported commodities yet',
                  subtitle: 'Add commodities in Price Management first.',
                )
              else if (tilesInRow)
                // The three as tall as the tallest.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, tile) in tiles.indexed) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: tile),
                      ],
                    ],
                  ),
                )
              else
                for (final (i, tile) in tiles.indexed) ...[
                  if (i > 0) const SizedBox(height: 8),
                  tile,
                ],
              if (fill) const Spacer() else const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: button),
            ],
          );
        },
      ),
    );
  }
}

/// MARKET CHANGE ANALYSIS, the full page (the user's design, 2026-11-10),
/// opened from the dashboard's preview inside the portal: the sidebar and
/// header stay, and Back to Dashboard returns to the dashboard as it was.
///
/// The product and period chosen here, the Completed Orders Trend (each
/// day or week of the period against the same position in the one
/// before), and beside it Demand Trend, Local Supply, Market Price and
/// Net Change; under them a summary of what was observed.
class AdminMarketChangeAnalysis extends StatelessWidget {
  final List<String> products;
  final List<DemandOrder> orders;
  final List<Map<String, dynamic>> listings;
  final MarketChangeChoice choice;
  final ValueChanged<String> onProductChanged;
  final ValueChanged<ChangeRange> onRangeChanged;
  final VoidCallback onBack;

  /// True until the orders are in.
  final bool loading;

  /// "Now", for tests.
  final DateTime? now;

  const AdminMarketChangeAnalysis({
    super.key,
    required this.products,
    required this.orders,
    required this.listings,
    required this.choice,
    required this.onProductChanged,
    required this.onRangeChanged,
    required this.onBack,
    this.loading = false,
    this.now,
  });

  /// From this width, the chart and the insights side by side.
  static const double twoColumnWidth = 980;

  /// The chart card's height side by side (the insights match it).
  static const double chartHeight = 448;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final today = now ?? DateTime.now();
    final product = MarketChangeService.productOrDefault(
      products,
      choice.product,
      orders,
      today,
    );
    final data = product == null || loading
        ? null
        : MarketChangeService.analyze(
            product: product,
            range: choice.range,
            orders: orders,
            products: listings,
            now: today,
          );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('marketChangeBack'),
              onPressed: onBack,
              style: TextButton.styleFrom(
                foregroundColor: adminActionColor(c),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back to Dashboard'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Market Change Analysis',
            style: TextStyle(
              color: c.heading,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Track recent marketplace changes for the selected product.',
            style: TextStyle(color: c.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (products.isNotEmpty)
                AdminCommoditySearchField(
                  key: ValueKey('changePage-$product'),
                  commodities: products,
                  selected: product,
                  width: 240,
                  hint: 'Search product',
                  semanticLabel: 'Market Change Analysis product',
                  onSelected: onProductChanged,
                ),
              AdminPillDropdown<ChangeRange>(
                key: const Key('marketChangeRange'),
                value: choice.range,
                width: 170,
                icon: Icons.calendar_today_outlined,
                items: [
                  for (final range in ChangeRange.values)
                    DropdownMenuItem(value: range, child: Text(range.label)),
                ],
                onChanged: onRangeChanged,
              ),
              if (data != null)
                Text(
                  '${data.window.currentLabel}  vs.  ${data.window.previousLabel}',
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: AdminLoadingSpinner(),
            )
          else if (data == null)
            const AdminEmptyState(
              icon: Icons.insights_outlined,
              title: 'No supported commodities yet',
              subtitle: 'Add commodities in Price Management first.',
            )
          else ...[
            LayoutBuilder(
              builder: (context, box) {
                final chart = _ChartCard(palette: c, data: data);
                final insights = [
                  for (final kind in _Insight.values)
                    _InsightTile(palette: c, data: data, kind: kind),
                ];
                if (box.maxWidth < twoColumnWidth) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: chartHeight, child: chart),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final tile in insights)
                            SizedBox(
                              width: box.maxWidth >= 560
                                  ? (box.maxWidth - 12) / 2
                                  : box.maxWidth,
                              child: tile,
                            ),
                        ],
                      ),
                    ],
                  );
                }
                return SizedBox(
                  height: chartHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 68, child: chart),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 32,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (i, tile) in insights.indexed) ...[
                              if (i > 0) const SizedBox(height: 10),
                              Expanded(child: tile),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _SummaryCard(palette: c, data: data),
          ],
        ],
      ),
    );
  }
}

enum _Insight { demand, supply, price, net }

/// One of the four measures: its name, what it did, its figures, and what
/// it is measured from.
class _InsightTile extends StatelessWidget {
  final AdminPalette palette;
  final MarketChange data;
  final _Insight kind;

  /// The dashboard preview's smaller tile.
  final bool compact;

  const _InsightTile({
    required this.palette,
    required this.data,
    required this.kind,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = palette;
    final unit = data.unit;
    final ({
      String label,
      IconData icon,
      String status,
      Color tone,
      String percent,
      String figures,
      String note,
    })
    t;
    Color toneOf(ChangeStatus s, {bool upIsGood = true}) => switch (s) {
      ChangeStatus.increased => upIsGood ? c.green : c.amber,
      ChangeStatus.decreased => upIsGood ? c.red : c.green,
      _ => c.textSecondary,
    };
    // The change in words: a percentage, "New" when there was nothing
    // before, or a dash when there is nothing to compare.
    String change(MetricChange m) => m.percentLabel.isNotEmpty
        ? m.percentLabel
        : (m.status == ChangeStatus.increased ? 'New' : '—');
    switch (kind) {
      case _Insight.demand:
        final m = data.demand;
        t = (
          label: 'Demand Trend',
          icon: Icons.shopping_basket_outlined,
          status: m.status.label,
          tone: toneOf(m.status),
          percent: change(m),
          figures: '${data.currentOrders} vs ${data.previousOrders} orders',
          note: 'Distinct completed orders containing ${data.product}',
        );
      case _Insight.supply:
        final m = data.supply;
        t = (
          label: 'Local Supply',
          icon: Icons.inventory_2_outlined,
          status: m.status.label,
          tone: toneOf(m.status),
          percent: change(m),
          figures:
              '${data.currentListings} vs ${data.previousListings} new listings',
          note: data.activeListings == 0
              ? 'New listings posted · none on sale now'
              : 'New listings posted · ${formatStock(data.availableStock, unit)} '
                    'on sale now (${data.activeListings} '
                    '${data.activeListings == 1 ? 'listing' : 'listings'})',
        );
      case _Insight.price:
        final m = data.price;
        String money(double? v) =>
            v == null ? '—' : formatPriceWithUnit(v, unit);
        t = (
          label: 'Market Price',
          icon: Icons.sell_outlined,
          status: m.status.label,
          tone: toneOf(m.status, upIsGood: false),
          percent: change(m),
          figures: '${money(m.current)} vs ${money(m.previous)}',
          note:
              'Current Market Average, today vs. '
              '${DateFormat('MMM d').format(data.window.previousEnd.subtract(const Duration(days: 1)))}',
        );
      case _Insight.net:
        final net = data.netChange;
        final percent = data.demand.percentLabel;
        t = (
          label: 'Net Change',
          icon: Icons.swap_vert,
          status:
              '${net > 0 ? '+' : (net < 0 ? '−' : '')}${net.abs()} '
              '${net.abs() == 1 ? 'order' : 'orders'}'
              '${percent.isEmpty ? '' : ' ($percent)'}',
          tone: net > 0 ? c.green : (net < 0 ? c.red : c.textSecondary),
          percent: '',
          figures:
              '${data.currentOrders} current · ${data.previousOrders} previous',
          note: 'Completed orders, current minus previous period',
        );
    }
    final arrow = switch (kind == _Insight.net
        ? (data.netChange > 0
              ? ChangeStatus.increased
              : data.netChange < 0
              ? ChangeStatus.decreased
              : ChangeStatus.steady)
        : switch (kind) {
            _Insight.demand => data.demand.status,
            _Insight.supply => data.supply.status,
            _ => data.price.status,
          }) {
      ChangeStatus.increased => Icons.trending_up,
      ChangeStatus.decreased => Icons.trending_down,
      ChangeStatus.steady => Icons.trending_flat,
      ChangeStatus.insufficient => Icons.remove,
    };
    final value = t.percent.isEmpty || t.percent == '—'
        ? t.figures
        : '${t.percent} · ${t.figures}';

    Widget text(String s, TextStyle style, {int lines = 1}) =>
        Text(s, maxLines: lines, overflow: TextOverflow.ellipsis, style: style);
    final heading = Row(
      children: [
        Icon(t.icon, size: compact ? 15 : 16, color: c.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: text(
            t.label,
            TextStyle(
              color: c.textSecondary,
              fontSize: compact ? 12 : 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
    final status = Row(
      children: [
        Icon(arrow, size: compact ? 16 : 18, color: t.tone),
        const SizedBox(width: 5),
        Flexible(
          child: text(
            t.status,
            TextStyle(
              color: t.tone,
              fontSize: compact ? 14 : 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );

    // The preview's tile: label, status, the change, then the figures it
    // is from; the page's: the change with its figures, then what the
    // measure is.
    final children = compact
        ? [
            heading,
            const SizedBox(height: 6),
            status,
            const SizedBox(height: 4),
            text(
              t.percent,
              TextStyle(
                color: c.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            text(
              t.figures,
              TextStyle(color: c.textMuted, fontSize: 11, height: 1.35),
              lines: 2,
            ),
          ]
        : [
            heading,
            const SizedBox(height: 5),
            status,
            const SizedBox(height: 3),
            text(
              value,
              TextStyle(
                color: c.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            text(t.note, TextStyle(color: c.textMuted, fontSize: 11)),
          ];

    // Everything on hover, as a narrow tile may cut it short.
    return Tooltip(
      message: '$value\n${t.note}',
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        key: Key('marketChange-${kind.name}'),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 11 : 8,
        ),
        decoration: BoxDecoration(
          color: compact ? c.surfaceAlt : c.surface,
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          border: Border.all(color: c.border),
          boxShadow: compact
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: compact
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }
}

/// The Completed Orders Trend: the current period's line in dark green
/// over the previous period's in golden yellow, day by day (or week by
/// week) at the same positions.
class _ChartCard extends StatelessWidget {
  final AdminPalette palette;
  final MarketChange data;
  const _ChartCard({required this.palette, required this.data});

  @override
  Widget build(BuildContext context) {
    final c = palette;
    Widget legend(Color color, String label, String dates) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ($dates)',
          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: adminCard(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Completed Orders Trend',
            style: TextStyle(
              color: c.heading,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Current period vs. previous period · ${data.product}, by '
            '${data.window.range.bucketDays == 1 ? 'day' : 'week'}',
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              legend(
                _currentLine(c),
                'Current period',
                data.window.currentLabel,
              ),
              legend(
                _previousLine,
                'Previous period',
                data.window.previousLabel,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: data.currentOrders == 0 && data.previousOrders == 0
                ? AdminChartEmpty(
                    icon: Icons.show_chart,
                    message:
                        'No completed orders of ${data.product} in either '
                        'period.',
                  )
                : _TrendChart(palette: c, data: data),
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final AdminPalette palette;
  final MarketChange data;
  const _TrendChart({required this.palette, required this.data});

  // A step of 1, 2 or 5 times a power of ten giving about four lines.
  static double _step(int max) {
    if (max <= 4) return 1;
    final raw = max / 4;
    final power = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in const [1, 2, 5, 10]) {
      if (raw <= m * power) return m * power;
    }
    return 10 * power;
  }

  @override
  Widget build(BuildContext context) {
    final c = palette;
    final points = data.trend;
    final top = points.fold(
      0,
      (m, p) => math.max(m, math.max(p.current, p.previous)),
    );
    final step = _step(top);
    // A line above the highest point, so its peak is never cut off.
    final maxY = ((top / step).floor() + 1) * step;
    final current = _currentLine(c);
    final days = data.window.range.bucketDays == 1;
    final labelEvery = points.length <= 14 ? 1 : 5;
    final day = DateFormat('MMM d');
    String span(DateTime from, DateTime to) {
      final last = DateTime(to.year, to.month, to.day - 1);
      return last.isAfter(from)
          ? '${day.format(from)}–${day.format(last)}'
          : day.format(from);
    }

    LineChartBarData line(List<int> values, Color color, double alpha) =>
        LineChartBarData(
          spots: [
            for (final (i, v) in values.indexed)
              FlSpot(i.toDouble(), v.toDouble()),
          ],
          isCurved: true,
          preventCurveOverShooting: true,
          curveSmoothness: 0.2,
          color: color,
          barWidth: 2.5,
          isStrokeCapRound: true,
          dotData: FlDotData(show: points.length <= 14),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        );

    final text = TextStyle(
      fontFamily: kAdminFontFamily,
      color: c.textSecondary,
      fontSize: 11,
    );
    return LineChart(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
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
            axisNameWidget: Text('Orders', style: text),
            axisNameSize: 16,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: step,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  NumberFormat.decimalPattern().format(v.round()),
                  style: text,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: Text(
              days ? 'Day of period' : 'Week of period',
              style: text,
            ),
            axisNameSize: 16,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if ((v - i).abs() > 0.01 || i < 0 || i >= points.length) {
                  return const SizedBox.shrink();
                }
                final n = i + 1;
                if (labelEvery > 1 && n != 1 && n % labelEvery != 0) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                  child: Text(days ? '$n' : 'W$n', style: text),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          getTouchedSpotIndicator: (bar, indexes) => [
            for (final _ in indexes)
              TouchedSpotIndicatorData(
                FlLine(
                  color: c.textMuted.withValues(alpha: 0.5),
                  strokeWidth: 1,
                  dashArray: const [4, 4],
                ),
                FlDotData(
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius: 4,
                        color: Colors.white,
                        strokeWidth: 2.5,
                        strokeColor: bar.color ?? current,
                      ),
                ),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.white,
            tooltipBorder: BorderSide(color: c.border),
            tooltipBorderRadius: BorderRadius.circular(8),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 9,
            ),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            maxContentWidth: 260,
            getTooltipItems: (spots) {
              if (spots.isEmpty) return const [];
              final p =
                  points[spots.first.x.round().clamp(0, points.length - 1)];
              String orders(int n) => '$n ${n == 1 ? 'order' : 'orders'}';
              const base = TextStyle(
                fontFamily: kAdminFontFamily,
                fontSize: 12,
                height: 1.5,
              );
              return [
                for (final (k, _) in spots.indexed)
                  k > 0
                      ? null
                      : LineTooltipItem(
                          '${days ? 'Day' : 'Week'} ${p.position}\n',
                          base.copyWith(
                            color: const Color(0xFF202623),
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.left,
                          children: [
                            TextSpan(
                              text:
                                  'Current · ${span(p.currentFrom, p.currentTo)}: ${orders(p.current)}\n',
                              style: base.copyWith(
                                color: kAdminGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text:
                                  'Previous · ${span(p.previousFrom, p.previousTo)}: ${orders(p.previous)}',
                              style: base.copyWith(
                                color: _previousText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
              ];
            },
          ),
        ),
        // The previous period under the current one.
        lineBarsData: [
          line([for (final p in points) p.previous], _previousLine, 0.10),
          line([for (final p in points) p.current], current, 0.14),
        ],
      ),
    );
  }
}

/// What was observed, in a few plain sentences under the chart.
class _SummaryCard extends StatelessWidget {
  final AdminPalette palette;
  final MarketChange data;
  const _SummaryCard({required this.palette, required this.data});

  @override
  Widget build(BuildContext context) {
    final c = palette;
    final lines = data.summary;
    return Container(
      key: const Key('marketChangeSummary'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: adminCard(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Insights Summary',
            style: TextStyle(
              color: c.heading,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final (i, line) in lines.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: i == lines.length - 1
                            ? c.textMuted
                            : _currentLine(c),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        color: i == lines.length - 1
                            ? c.textMuted
                            : c.textPrimary,
                        fontSize: i == lines.length - 1 ? 11.5 : 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Local Supply counts new listings posted, as past stock is not '
            'kept. The earlier Current Market Average is from the listings '
            'on sale then, at the prices saved now.',
            style: TextStyle(color: c.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
