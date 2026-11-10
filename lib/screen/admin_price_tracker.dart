import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/market_price_helpers.dart' show formatPeso;
import '../services/price_tracker_service.dart';
import 'admin_dashboard_screen.dart' show AdminPalette, AdminThemeScope;
import 'admin_filter_controls.dart' show adminActionColor, adminCard;

/// One commodity the price tracker lists: its record id in market_prices,
/// the unit both of its prices are compared in (its Price Management unit,
/// else the commodity list's), and its current Price Management record.
class PriceTrackerCommodity {
  final String id;
  final String name;
  final String category;
  final String unit;

  /// The market_prices document (`baselinePrice`, `unit`,
  /// `effectiveDate`), or null when the Admin has set no baseline.
  final Map<String, dynamic>? record;

  const PriceTrackerCommodity({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    this.record,
  });
}

// The Admin Baseline's colour: a soft red line and figure, as the second
// series of a price tracker (the user's reference, 2026-11-10).
const Color _baselineLine = Color(0xFFE07A7A);
const Color _baselineText = Color(0xFFC0392B);

/// AVERAGE PRICE VS. ADMIN BASELINE — a price tracker laid out from the
/// user's reference (2026-11-10): the commodities on the left (search,
/// category chips, a text-only list), and on the right the chosen one's
/// three figures (AgriTrade+ Average Price, Admin Baseline, Price
/// Difference) over an AgriTrade+ | Compare chart with 7D / 30D / 90D /
/// All Data.
///
/// The AgriTrade+ price is the quantity-weighted retail price of completed
/// orders, by the day they were completed; the baseline is Price
/// Management's, as it stood on each day ([loadBaselineHistory] gives a
/// commodity's dated history). Both in the commodity's own unit; nothing
/// is drawn where there is no record.
class AdminPriceTracker extends StatefulWidget {
  final List<PriceTrackerCommodity> commodities;
  final List<Map<String, dynamic>> completedOrders;
  final Future<List<Map<String, dynamic>>> Function(String commodityId)
  loadBaselineHistory;
  final DateTime? now;

  const AdminPriceTracker({
    super.key,
    required this.commodities,
    required this.completedOrders,
    required this.loadBaselineHistory,
    this.now,
  });

  /// The height of the tracker side by side (list and chart).
  static const double wideHeight = 540;

  @override
  State<AdminPriceTracker> createState() => _AdminPriceTrackerState();
}

class _AdminPriceTrackerState extends State<AdminPriceTracker> {
  final _search = TextEditingController();

  // The list's own: its always-shown scrollbar needs one on the web,
  // where a list never takes the page's primary controller.
  final _listScroll = ScrollController();
  String? _category;
  String? _selected;
  bool _compare = true;
  TrackerRange _range = TrackerRange.all;

  // Each commodity's daily prices, worked out once per set of orders.
  Map<String, ({List<PriceDay> days, int otherUnitSales})> _daily = {};
  final Map<String, Future<List<Map<String, dynamic>>>> _history = {};

  @override
  void initState() {
    super.initState();
    _computeDaily();
    _search.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(AdminPriceTracker old) {
    super.didUpdateWidget(old);
    if (!identical(old.completedOrders, widget.completedOrders) ||
        !identical(old.commodities, widget.commodities)) {
      _computeDaily();
    }
    if (!identical(old.commodities, widget.commodities)) _history.clear();
  }

  @override
  void dispose() {
    _search.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _computeDaily() {
    _daily = {
      for (final c in widget.commodities)
        c.id: dailyAveragePrices(
          widget.completedOrders,
          commodity: c.name,
          unit: c.unit,
        ),
    };
  }

  DateTime get _now => widget.now ?? DateTime.now();

  List<PriceDay> _daysOf(PriceTrackerCommodity c) =>
      _daily[c.id]?.days ?? const [];

  // The list: those with sales first (most recent sale first), then the
  // rest by name.
  List<PriceTrackerCommodity> _sorted() {
    final list = [...widget.commodities];
    list.sort((a, b) {
      final da = _daysOf(a);
      final db = _daysOf(b);
      if (da.isNotEmpty != db.isNotEmpty) return da.isNotEmpty ? -1 : 1;
      if (da.isNotEmpty) {
        final byDate = db.last.day.compareTo(da.last.day);
        if (byDate != 0) return byDate;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final sorted = _sorted();
    if (_selected == null || !sorted.any((x) => x.id == _selected)) {
      _selected = sorted.isEmpty ? null : sorted.first.id;
    }
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final x in sorted)
        if ((_category == null || x.category == _category) &&
            (query.isEmpty || x.name.toLowerCase().contains(query)))
          x,
    ];
    // In the app's category order (the list is sorted by sales), each once.
    final categories = <String>{
      for (final x in widget.commodities)
        if (x.category.isNotEmpty) x.category,
    }.toList();

    final list = _ProductList(
      palette: c,
      search: _search,
      scroll: _listScroll,
      categories: categories,
      category: _category,
      onCategory: (value) => setState(() => _category = value),
      items: shown,
      selectedId: _selected,
      daysOf: _daysOf,
      onSelect: (id) => setState(() => _selected = id),
    );
    final selected = sorted.where((x) => x.id == _selected).firstOrNull;
    final detail = selected == null
        ? Container(
            decoration: adminCard(c),
            child: _Empty(
              palette: c,
              message: 'No commodities in Price Management yet.',
            ),
          )
        : FutureBuilder<List<Map<String, dynamic>>>(
            future: _history.putIfAbsent(
              selected.id,
              () => widget
                  .loadBaselineHistory(selected.id)
                  .catchError((_) => const <Map<String, dynamic>>[]),
            ),
            builder: (context, snap) => _Detail(
              palette: c,
              commodity: selected,
              daily: _daily[selected.id] ?? (days: const [], otherUnitSales: 0),
              steps: baselineSteps(
                snap.data ?? const [],
                current: selected.record,
                unit: selected.unit,
              ),
              loadingBaseline: snap.connectionState != ConnectionState.done,
              now: _now,
              compare: _compare,
              onCompare: (value) => setState(() => _compare = value),
              range: _range,
              onRange: (value) => setState(() => _range = value),
            ),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 360, child: list),
              const SizedBox(height: 16),
              SizedBox(height: AdminPriceTracker.wideHeight, child: detail),
            ],
          );
        }
        return SizedBox(
          height: AdminPriceTracker.wideHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // About a quarter of the width for the list.
              SizedBox(
                width: (constraints.maxWidth * 0.26).clamp(280.0, 380.0),
                child: list,
              ),
              const SizedBox(width: 20),
              Expanded(child: detail),
            ],
          ),
        );
      },
    );
  }
}

// ---- The left side: title, search, category chips, the list ----

class _ProductList extends StatelessWidget {
  final AdminPalette palette;
  final TextEditingController search;
  final ScrollController scroll;
  final List<String> categories;
  final String? category;
  final ValueChanged<String?> onCategory;
  final List<PriceTrackerCommodity> items;
  final String? selectedId;
  final List<PriceDay> Function(PriceTrackerCommodity) daysOf;
  final ValueChanged<String> onSelect;

  const _ProductList({
    required this.palette,
    required this.search,
    required this.scroll,
    required this.categories,
    required this.category,
    required this.onCategory,
    required this.items,
    required this.selectedId,
    required this.daysOf,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Average Price vs. Admin Baseline',
          style: TextStyle(
            color: c.heading,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Retail prices from completed orders, per unit, against the '
          'Price Management baseline.',
          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
        ),
        const SizedBox(height: 12),
        // Search: 38 high, rounded 10 (the user's spec for the tracker).
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.search, size: 16, color: c.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('priceTrackerSearch'),
                  controller: search,
                  style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                  cursorHeight: 15,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText: 'Search products…',
                    hintStyle: TextStyle(color: c.textMuted, fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 28,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _chip(c, 'All', category == null, () => onCategory(null)),
              for (final name in categories)
                _chip(c, name, category == name, () => onCategory(name)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: items.isEmpty
                ? _Empty(palette: c, message: 'No products match.')
                : Scrollbar(
                    controller: scroll,
                    thumbVisibility: true,
                    child: ListView.separated(
                      controller: scroll,
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, thickness: 1, color: c.border),
                      itemBuilder: (context, i) => _row(c, items[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _chip(AdminPalette c, String label, bool on, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: on ? adminActionColor(c) : c.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: on ? Colors.white : c.textSecondary,
                  fontSize: 11.5,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(AdminPalette c, PriceTrackerCommodity item) {
    final selected = item.id == selectedId;
    final days = daysOf(item);
    final latest = days.isEmpty ? null : days.last;
    final details = [
      if (item.category.isNotEmpty) item.category,
      'per ${item.unit}',
      latest == null
          ? 'No sales yet'
          : DateFormat('MMM d, yyyy').format(latest.day),
    ].join(' · ');
    return Material(
      color: selected ? c.greenBg : Colors.transparent,
      child: InkWell(
        key: Key('priceTrackerRow_${item.id}'),
        onTap: () => onSelect(item.id),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? adminActionColor(c) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(13, 9, 14, 9),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // The latest day's AgriTrade+ price.
              Text(
                latest == null ? '—' : formatPeso(latest.average),
                style: TextStyle(
                  color: latest == null ? c.textMuted : adminActionColor(c),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- The right side: the chosen commodity ----

class _Detail extends StatelessWidget {
  final AdminPalette palette;
  final PriceTrackerCommodity commodity;
  final ({List<PriceDay> days, int otherUnitSales}) daily;
  final List<BaselineStep> steps;
  final bool loadingBaseline;
  final DateTime now;
  final bool compare;
  final ValueChanged<bool> onCompare;
  final TrackerRange range;
  final ValueChanged<TrackerRange> onRange;

  const _Detail({
    required this.palette,
    required this.commodity,
    required this.daily,
    required this.steps,
    required this.loadingBaseline,
    required this.now,
    required this.compare,
    required this.onCompare,
    required this.range,
    required this.onRange,
  });

  @override
  Widget build(BuildContext context) {
    final c = palette;
    final window = trackerWindow(
      range,
      now: now,
      days: daily.days,
      steps: steps,
    );
    final summary = PriceTrackerSummary.of(daily.days, steps, window);
    final unit = commodity.unit;
    final dateText = DateFormat('MMM d, yyyy');
    final latestSale = daily.days.isEmpty ? null : daily.days.last.day;
    final change = summary.changePercent;

    return Container(
      decoration: adminCard(c),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The name with its category beside it, one line, so the chart
          // keeps the height (the user's sizing pass, 2026-11-10).
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        commodity.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.heading,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (commodity.category.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: c.surfaceAlt,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          commodity.category,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (change != null) _changeBadge(c, change),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'AgriTrade+: ${latestSale == null ? 'No completed sales yet' : 'Latest sale · ${dateText.format(latestSale)}'}'
            '   •   Admin Baseline: '
            '${loadingBaseline
                ? 'Loading…'
                : steps.isEmpty
                ? 'Not set'
                : 'Effective · ${dateText.format(steps.last.day)}'}',
            style: TextStyle(color: c.textSecondary, fontSize: 11.5),
          ),
          if (daily.otherUnitSales > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${daily.otherUnitSales} completed '
              '${daily.otherUnitSales == 1 ? 'sale' : 'sales'} in another unit '
              'not compared: prices here are per $unit.',
              style: TextStyle(color: c.amber, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 88,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _averageCard(c, summary, unit)),
                const SizedBox(width: 12),
                Expanded(child: _baselineCard(c, summary, unit)),
                const SizedBox(width: 12),
                Expanded(child: _differenceCard(c, summary)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _controls(c, summary),
          const SizedBox(height: 10),
          Expanded(
            child: _TrackerChart(
              palette: c,
              days: summary.days,
              steps: steps,
              window: window,
              compare: compare,
              unit: unit,
            ),
          ),
        ],
      ),
    );
  }

  Widget _changeBadge(AdminPalette c, double change) {
    final down = change < 0;
    final color = down ? c.green : c.red;
    return Container(
      key: const Key('priceTrackerChange'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: down ? c.greenBg : c.redBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            down ? Icons.trending_down : Icons.trending_up,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _figureCard(
    AdminPalette c, {
    required Key key,
    required Color background,
    required Color border,
    required IconData icon,
    required Color accent,
    required String label,
    required String value,
    required Color valueColor,
    required String caption,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 19, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: valueColor,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _averageCard(AdminPalette c, PriceTrackerSummary s, String unit) =>
      _figureCard(
        c,
        key: const Key('priceTrackerAverage'),
        background: c.greenBg,
        border: c.green.withValues(alpha: 0.18),
        icon: Icons.sell_outlined,
        accent: c.green,
        label: 'AGRITRADE+ AVERAGE PRICE',
        value: s.average == null ? '—' : formatPeso(s.average!),
        valueColor: c.green,
        caption: s.average == null
            ? 'No completed sales in this period'
            : '/$unit · ${s.sales} ${s.sales == 1 ? 'sale' : 'sales'}',
      );

  Widget _baselineCard(AdminPalette c, PriceTrackerSummary s, String unit) =>
      _figureCard(
        c,
        key: const Key('priceTrackerBaseline'),
        background: c.surfaceAlt,
        border: c.border,
        icon: Icons.bar_chart_rounded,
        accent: c.textSecondary,
        label: 'ADMIN BASELINE',
        value: s.baseline == null ? '—' : formatPeso(s.baseline!),
        valueColor: s.baseline == null ? c.textMuted : _baselineText,
        caption: s.baseline == null ? 'Not set for this period' : '/$unit',
      );

  Widget _differenceCard(AdminPalette c, PriceTrackerSummary s) {
    final diff = s.difference;
    final percent = s.differencePercent;
    final lower = diff != null && diff < 0;
    final same = diff != null && diff.abs() < 0.005;
    return _figureCard(
      c,
      key: const Key('priceTrackerDifference'),
      background: diff == null || same
          ? c.surfaceAlt
          : lower
          ? c.greenBg
          : c.amberBg,
      border: diff == null || same
          ? c.border
          : (lower ? c.green : c.amber).withValues(alpha: 0.25),
      icon: diff == null || same
          ? Icons.horizontal_rule
          : lower
          ? Icons.south_east
          : Icons.north_east,
      accent: diff == null || same
          ? c.textSecondary
          : (lower ? c.green : c.amber),
      label: 'PRICE DIFFERENCE',
      value: diff == null
          ? '—'
          : '${diff > 0
                ? '+'
                : diff < 0
                ? '−'
                : ''}${formatPeso(diff.abs())}',
      valueColor: diff == null
          ? c.textMuted
          : same
          ? c.textPrimary
          : (lower ? c.green : c.amber),
      caption: diff == null
          ? 'Needs a sale and a baseline'
          : same
          ? 'Same as the baseline'
          : '${percent!.abs().toStringAsFixed(1)}% ${lower ? 'below' : 'above'} '
                'the baseline',
    );
  }

  Widget _controls(AdminPalette c, PriceTrackerSummary s) {
    Widget tab(String label, bool on, VoidCallback onTap, Key key) => InkWell(
      key: key,
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: on ? c.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: on ? c.textPrimary : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? adminActionColor(c) : c.textSecondary,
            fontSize: 12,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
    Widget legend(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 2.5, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
      ],
    );
    Widget rangeChip(TrackerRange r) {
      final on = r == range;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: on ? adminActionColor(c) : c.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            key: Key('priceTrackerRange_${r.name}'),
            borderRadius: BorderRadius.circular(999),
            onTap: () => onRange(r),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              child: Text(
                r.label,
                style: TextStyle(
                  color: on ? Colors.white : c.textSecondary,
                  fontSize: 11.5,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final dataDays = s.days.length;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tab(
                    'AgriTrade+',
                    !compare,
                    () => onCompare(false),
                    const Key('priceTrackerTab_agritrade'),
                  ),
                  tab(
                    'Compare',
                    compare,
                    () => onCompare(true),
                    const Key('priceTrackerTab_compare'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            legend(adminActionColor(c), 'AgriTrade+ Average Price'),
            if (compare) ...[
              const SizedBox(width: 12),
              legend(_baselineLine, 'Admin Baseline'),
            ],
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in TrackerRange.values) rangeChip(r),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$dataDays ${dataDays == 1 ? 'day' : 'days'} of data',
                style: TextStyle(color: c.textSecondary, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---- The chart ----

class _TrackerChart extends StatelessWidget {
  final AdminPalette palette;
  final List<PriceDay> days;
  final List<BaselineStep> steps;
  final DateTimeRange window;
  final bool compare;
  final String unit;

  const _TrackerChart({
    required this.palette,
    required this.days,
    required this.steps,
    required this.window,
    required this.compare,
    required this.unit,
  });

  double _x(DateTime day) =>
      DateUtils.dateOnly(day).difference(window.start).inDays.toDouble();

  DateTime _day(double x) => window.start.add(Duration(days: x.round()));

  // The baseline as drawn: its value on the window's first day (if one
  // was in effect), each change inside the window, and the last value held
  // to the window's end. Nothing before the first baseline.
  List<FlSpot> _baselineSpots() {
    final spots = <FlSpot>[];
    final atStart = baselineOn(steps, window.start);
    if (atStart != null) spots.add(FlSpot(0, atStart));
    for (final step in steps) {
      if (step.day.isAfter(window.start) && !step.day.isAfter(window.end)) {
        spots.add(FlSpot(_x(step.day), step.price));
      }
    }
    if (spots.isNotEmpty) {
      final end = _x(window.end);
      if (spots.last.x < end) spots.add(FlSpot(end, spots.last.y));
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final c = palette;
    final green = adminActionColor(c);
    final saleSpots = [for (final d in days) FlSpot(_x(d.day), d.average)];
    final baseSpots = compare ? _baselineSpots() : <FlSpot>[];
    if (saleSpots.isEmpty && baseSpots.isEmpty) {
      return _Empty(
        palette: c,
        message: compare
            ? 'No completed sales or baseline in this period.'
            : 'No completed retail sales in this period.',
      );
    }
    final values = [...saleSpots.map((s) => s.y), ...baseSpots.map((s) => s.y)];
    var low = values.reduce((a, b) => a < b ? a : b);
    var high = values.reduce((a, b) => a > b ? a : b);
    // About three round steps between the lowest and highest price, with
    // room above and below; only those steps are labelled.
    final spread = high - low < high * 0.1 ? high * 0.2 : high - low;
    final step = _niceStep(spread / 3);
    final minY = ((low - step * 0.3) / step).floorToDouble() * step < 0
        ? 0.0
        : ((low - step * 0.3) / step).floorToDouble() * step;
    final maxY = ((high + step * 0.3) / step).ceilToDouble() * step;
    final maxX = _x(window.end) < 1 ? 1.0 : _x(window.end);
    final axisStyle = TextStyle(color: c.textSecondary, fontSize: 11);
    final dense = maxX <= 14;
    // The year only when the range crosses one: "Oct 28, 2026" beside
    // "Nov 10, 2026" ran into each other.
    final dateLabel = DateFormat(
      dense || _day(0).year == _day(maxX).year ? 'MMM d' : 'MMM d, yy',
    );
    final labelEvery = dense ? 1.0 : (maxX / 6).ceilToDouble();

    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: step,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: c.border, strokeWidth: 1, dashArray: [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _leftReserved,
              interval: step,
              getTitlesWidget: (value, meta) {
                if ((value / step - (value / step).round()).abs() > 1e-6) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '₱${NumberFormat('#,##0.##').format(value)}',
                    textAlign: TextAlign.right,
                    style: axisStyle,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _bottomReserved,
              interval: labelEvery,
              getTitlesWidget: (value, meta) {
                // The last label only where it does not crowd the one
                // before it.
                if (value != meta.max && (value % labelEvery).abs() > 1e-6) {
                  return const SizedBox.shrink();
                }
                if (value == meta.max &&
                    !dense &&
                    meta.max % labelEvery < labelEvery * 0.75) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 8,
                  // The first and last dates stay inside the chart.
                  fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                  child: Text(dateLabel.format(_day(value)), style: axisStyle),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: saleSpots,
            color: green,
            barWidth: 2.2,
            isCurved: false,
            // Each real sale day is marked while there are few of them.
            dotData: FlDotData(
              show: saleSpots.length <= 40,
              getDotPainter: (spot, _, _, _) =>
                  FlDotCirclePainter(radius: 2.6, color: green, strokeWidth: 0),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  green.withValues(alpha: 0.16),
                  green.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          if (baseSpots.isNotEmpty)
            LineChartBarData(
              spots: baseSpots,
              color: _baselineLine,
              barWidth: 1.6,
              isStepLineChart: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _baselineLine.withValues(alpha: 0.12),
                    _baselineLine.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
        ],
        // Hovering is drawn by _HoverLayer: a line that follows the
        // pointer anywhere on the chart, not only on a point.
        lineTouchData: const LineTouchData(enabled: false),
      ),
      duration: const Duration(milliseconds: 250),
    );

    return _HoverLayer(
      palette: c,
      minX: 0,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      left: _leftReserved,
      bottom: _bottomReserved,
      probe: (x) {
        final day = _day(x);
        // The latest real sale on or before the day: the line between two
        // sale days is not a price anyone paid.
        final sale = days.where((d) => !d.day.isAfter(day)).lastOrNull;
        return _Probe(
          day: day,
          sale: sale,
          saleX: sale == null ? null : _x(sale.day),
          baseline: compare ? baselineOn(steps, day) : null,
          compare: compare,
          unit: unit,
        );
      },
      child: chart,
    );
  }
}

class _Empty extends StatelessWidget {
  final AdminPalette palette;
  final String message;
  const _Empty({required this.palette, required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.show_chart, size: 24, color: palette.textMuted),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textSecondary, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

/// A round step at least [raw]: 1, 2, 2.5 or 5 times a power of ten.
double _niceStep(double raw) {
  if (raw <= 0) return 1;
  final magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  for (final f in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (f * magnitude >= raw - 1e-9) return f * magnitude;
  }
  return 10 * magnitude;
}

// The chart's title space: the prices on the left, the dates below.
const double _leftReserved = 52;
const double _bottomReserved = 26;

/// What the hover shows for one day: the latest sale on or before it (and
/// where that sale is on the chart), and the baseline in effect that day.
class _Probe {
  final DateTime day;
  final PriceDay? sale;
  final double? saleX;
  final double? baseline;
  final bool compare;
  final String unit;

  const _Probe({
    required this.day,
    required this.sale,
    required this.saleX,
    required this.baseline,
    required this.compare,
    required this.unit,
  });
}

/// The chart's hover, as on the user's reference (2026-11-10): a thin line
/// that follows the pointer anywhere over the chart, a dot on each series,
/// and a white box with the day, the AgriTrade+ price in green and the
/// Admin Baseline in red.
class _HoverLayer extends StatefulWidget {
  final AdminPalette palette;
  final double minX, maxX, minY, maxY;

  /// The chart's title space on the left and at the bottom, so the hover
  /// lines up with the plot itself.
  final double left, bottom;
  final _Probe Function(double x) probe;
  final Widget child;

  const _HoverLayer({
    required this.palette,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.left,
    required this.bottom,
    required this.probe,
    required this.child,
  });

  @override
  State<_HoverLayer> createState() => _HoverLayerState();
}

class _HoverLayerState extends State<_HoverLayer> {
  // The pointer's distance from the chart's left edge; null when away.
  double? _pointer;

  static const double _tooltipWidth = 200;

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    final green = adminActionColor(c);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final plotWidth = math.max(1.0, width - widget.left);
        final plotHeight = math.max(1.0, constraints.maxHeight - widget.bottom);
        final spanX = widget.maxX == widget.minX
            ? 1.0
            : widget.maxX - widget.minX;
        final spanY = widget.maxY == widget.minY
            ? 1.0
            : widget.maxY - widget.minY;
        double toPx(double x) =>
            widget.left + (x - widget.minX) / spanX * plotWidth;
        double toPy(double v) => (widget.maxY - v) / spanY * plotHeight;

        void track(Offset position) {
          final px = position.dx.clamp(widget.left, width).toDouble();
          if (px != _pointer) setState(() => _pointer = px);
        }

        void leave() {
          if (_pointer != null) setState(() => _pointer = null);
        }

        final px = _pointer;
        final probe = px == null
            ? null
            : widget.probe(
                widget.minX + (px - widget.left) / plotWidth * spanX,
              );

        Widget dot(double x, double y, Color color) => Positioned(
          left: x - 5,
          top: y - 5,
          child: IgnorePointer(
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: c.surface, width: 2),
              ),
            ),
          ),
        );

        return MouseRegion(
          onHover: (e) => track(e.localPosition),
          onExit: (_) => leave(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // A finger works too: press and slide.
            onPanDown: (d) => track(d.localPosition),
            onPanUpdate: (d) => track(d.localPosition),
            onPanEnd: (_) => leave(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: widget.child),
                if (px != null && probe != null) ...[
                  Positioned(
                    key: const Key('priceTrackerHoverLine'),
                    left: px - 0.5,
                    top: 0,
                    height: plotHeight,
                    child: IgnorePointer(
                      child: Container(width: 1, color: c.textMuted),
                    ),
                  ),
                  if (probe.baseline != null)
                    dot(px, toPy(probe.baseline!), _baselineLine),
                  if (probe.sale != null && probe.saleX != null)
                    dot(toPx(probe.saleX!), toPy(probe.sale!.average), green),
                  Positioned(
                    top: 4,
                    // Beside the line, on whichever side has room.
                    left: px + 12 + _tooltipWidth <= width
                        ? px + 12
                        : math.max(0.0, px - 12 - _tooltipWidth),
                    // The figure in the palette's brighter green, so it reads green
                    // beside the red (the darker line green looks black there).
                    child: IgnorePointer(child: _tooltip(c, c.green, probe)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tooltip(AdminPalette c, Color green, _Probe p) {
    final sale = p.sale;
    final sameDay = sale != null && DateUtils.isSameDay(sale.day, p.day);
    TextStyle value(Color color) =>
        TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700);
    final muted = TextStyle(
      color: c.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w500,
    );
    return Container(
      key: const Key('priceTrackerTooltip'),
      width: _tooltipWidth,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${DateFormat('MMM d, yyyy').format(p.day)} · per ${p.unit}',
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: sale == null
                      ? 'AgriTrade+: No sales yet'
                      : 'AgriTrade+: ${formatPeso(sale.average)}',
                  style: value(green),
                ),
                // A day with no sale shows the last one before it, dated.
                if (sale != null && !sameDay)
                  TextSpan(
                    text: '  last sale ${DateFormat('MMM d').format(sale.day)}',
                    style: muted,
                  ),
                if (sale != null && sameDay)
                  TextSpan(
                    text:
                        '  ${sale.sales} ${sale.sales == 1 ? 'sale' : 'sales'}',
                    style: muted,
                  ),
              ],
            ),
          ),
          if (p.compare) ...[
            const SizedBox(height: 3),
            Text(
              p.baseline == null
                  ? 'Admin Baseline: Not set'
                  : 'Admin Baseline: ${formatPeso(p.baseline!)}',
              style: value(_baselineText),
            ),
          ],
        ],
      ),
    );
  }
}
