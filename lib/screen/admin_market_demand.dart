import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/monthly_demand_service.dart';
import 'admin_dashboard_screen.dart' show AdminPalette, AdminThemeScope;
import 'admin_filter_controls.dart'
    show AdminPillDropdown, AdminYearPill, adminActionColor, adminCard;

/// The selected month's golden outline and label (the user's design,
/// 2026-11-10).
const Color kDemandGold = Color(0xFFF5BB24);
const Color _goldWash = Color(0xFFFFF4D6);
const Color _panelGreen = Color(0xFF0B4225);

/// What the dashboard opens Full Product Demand with.
typedef FullDemandRequest = ({DateTime month, String product});

/// MARKET DEMAND (the user's design, 2026-11-10): completed orders month by
/// month for one year, for all products or one, as bars in four greens by
/// demand level; hover a month for its figures and top products, click it
/// to hold it and see its details on the right, where View Full Product
/// Demand opens the whole ranking. Opens on the latest year and All
/// Products, so it shows something at once. Months before the records
/// begin are left out.
class AdminMarketDemandSection extends StatefulWidget {
  final List<DemandOrder> orders;
  final ValueChanged<FullDemandRequest> onViewFull;
  final Object? error;
  final VoidCallback? onRetry;
  final DateTime? now;

  const AdminMarketDemandSection({
    super.key,
    required this.orders,
    required this.onViewFull,
    this.error,
    this.onRetry,
    this.now,
  });

  /// The section's height side by side (chart and panel).
  static const double wideHeight = 340;

  @override
  State<AdminMarketDemandSection> createState() =>
      _AdminMarketDemandSectionState();
}

class _AdminMarketDemandSectionState extends State<AdminMarketDemandSection> {
  int? _year;
  String _product = kAllProducts;
  DateTime? _selected;
  DateTime? _hovered;

  DateTime get _now => widget.now ?? DateTime.now();

  void _select(DateTime month) => setState(
    // The same month again lets it go.
    () => _selected = _selected == month ? null : month,
  );

  void _clear() => setState(() => _selected = null);

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final years = demandYears(widget.orders);
    if (_year != null && !years.contains(_year)) _year = null;
    final year = _year ?? (years.isEmpty ? _now.year : years.last);
    final months = reportingMonths(widget.orders, year, now: _now);
    final products = demandProducts(widget.orders);
    if (_product != kAllProducts && !products.contains(_product)) {
      _product = kAllProducts;
    }
    final counts = monthlyOrders(widget.orders, months, product: _product);
    final scale = DemandScale.of(counts.values);
    if (_selected != null && !months.contains(_selected)) _selected = null;

    final chartSide = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(c, years, year, products),
        const SizedBox(height: 14),
        Expanded(
          child: widget.error != null && widget.orders.isEmpty
              ? _Message(
                  palette: c,
                  text: 'Could not load completed orders.',
                  action: widget.onRetry == null
                      ? null
                      : TextButton(
                          onPressed: widget.onRetry,
                          child: const Text('Retry'),
                        ),
                )
              : months.isEmpty
              ? _Message(
                  palette: c,
                  text:
                      'No completed orders yet: Market Demand fills in '
                      'as orders are completed.',
                )
              : _DemandBars(
                  palette: c,
                  months: months,
                  counts: counts,
                  scale: scale,
                  selected: _selected,
                  hovered: _hovered,
                  onHover: (m) => setState(() => _hovered = m),
                  onSelect: _select,
                  tooltip: (m) => _tooltip(c, m, counts[m] ?? 0, scale),
                ),
        ),
        const SizedBox(height: 10),
        _legend(c, scale, counts.values.any((n) => n == 0)),
      ],
    );
    final panel = _DemandPanel(
      palette: c,
      orders: widget.orders,
      months: months,
      counts: counts,
      scale: scale,
      product: _product,
      selected: _selected,
      onClear: _clear,
      onViewFull: (month) =>
          widget.onViewFull((month: month, product: _product)),
    );

    return CallbackShortcuts(
      // Esc lets the held month go.
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clear},
      child: Focus(
        child: Container(
          decoration: adminCard(c),
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 980) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 340, child: chartSide),
                    const SizedBox(height: 16),
                    SizedBox(height: 380, child: panel),
                  ],
                );
              }
              return SizedBox(
                height: AdminMarketDemandSection.wideHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 68, child: chartSide),
                    const SizedBox(width: 20),
                    Expanded(flex: 32, child: panel),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(
    AdminPalette c,
    List<int> years,
    int year,
    List<String> products,
  ) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 10,
      spacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Market Demand',
              style: TextStyle(
                color: c.heading,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Completed orders per month, each order counted once',
              style: TextStyle(color: c.textSecondary, fontSize: 12),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AdminYearPill(
              key: const Key('marketDemandYear'),
              year: year,
              firstYear: years.isEmpty ? year : years.first,
              lastYear: years.isEmpty ? year : years.last,
              width: 134,
              semanticLabel: 'Year',
              onChanged: (y) => setState(() {
                _year = y;
                _selected = null;
              }),
            ),
            const SizedBox(width: 10),
            AdminPillDropdown<String>(
              key: const Key('marketDemandProduct'),
              value: _product,
              width: 200,
              icon: Icons.inventory_2_outlined,
              items: [
                for (final name in [kAllProducts, ...products])
                  DropdownMenuItem(
                    value: name,
                    child: Text(name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _product = value),
            ),
          ],
        ),
      ],
    );
  }

  Widget _legend(AdminPalette c, DemandScale scale, bool anyZero) {
    Widget entry(DemandTier tier) {
      final range = scale.rangeOf(tier);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: tier.color,
              borderRadius: BorderRadius.circular(3),
              border: tier == DemandTier.veryLow || tier == DemandTier.none
                  ? Border.all(color: c.border)
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${tier.label.replaceAll(' Demand', '')} '
            '(${range ?? '—'})',
            style: TextStyle(color: c.textSecondary, fontSize: 11.5),
          ),
        ],
      );
    }

    return Wrap(
      key: const Key('marketDemandLegend'),
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tier in const [
          DemandTier.veryLow,
          DemandTier.low,
          DemandTier.moderate,
          DemandTier.high,
        ])
          entry(tier),
        if (anyZero) entry(DemandTier.none),
        Text(
          'Completed orders only',
          style: TextStyle(color: c.textMuted, fontSize: 11),
        ),
      ],
    );
  }

  Widget _tooltip(AdminPalette c, DateTime month, int count, DemandScale s) {
    final tier = s.tierOf(count);
    final all = _product == kAllProducts;
    final top = all
        ? productDemand(widget.orders, [month]).rows.take(3).toList()
        : const <ProductDemandRow>[];
    return Container(
      key: const Key('marketDemandTooltip'),
      width: 220,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            demandMonthLabel(month),
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            _product,
            style: TextStyle(color: c.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            '$count Completed ${count == 1 ? 'Order' : 'Orders'}',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          _TierChip(palette: c, tier: tier),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Most In-Demand Products:',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            for (var i = 0; i < top.length; i++)
              Text(
                '${i + 1}. ${top[i].product} — ${_orders(top[i].orders)}',
                style: TextStyle(color: c.textPrimary, fontSize: 11.5),
              ),
          ],
        ],
      ),
    );
  }
}

String _orders(int n) => '$n ${n == 1 ? 'order' : 'orders'}';

/// A demand level as a small chip: its colour and name.
class _TierChip extends StatelessWidget {
  final AdminPalette palette;
  final DemandTier tier;
  const _TierChip({required this.palette, required this.tier});

  @override
  Widget build(BuildContext context) {
    final c = palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: tier.color,
              shape: BoxShape.circle,
              border: tier == DemandTier.veryLow || tier == DemandTier.none
                  ? Border.all(color: c.textMuted, width: 0.8)
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            tier.label,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- The bars ----

class _DemandBars extends StatelessWidget {
  final AdminPalette palette;
  final List<DateTime> months;
  final Map<DateTime, int> counts;
  final DemandScale scale;
  final DateTime? selected;
  final DateTime? hovered;
  final ValueChanged<DateTime?> onHover;
  final ValueChanged<DateTime> onSelect;
  final Widget Function(DateTime month) tooltip;

  const _DemandBars({
    required this.palette,
    required this.months,
    required this.counts,
    required this.scale,
    required this.selected,
    required this.hovered,
    required this.onHover,
    required this.onSelect,
    required this.tooltip,
  });

  static const double _axis = 36;
  static const double _labels = 30;
  static const double _countSpace = 22;

  @override
  Widget build(BuildContext context) {
    final c = palette;
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = still ? Duration.zero : const Duration(milliseconds: 220);
    final highest = counts.values.fold<int>(0, math.max);
    final step = _niceStep(math.max(1, highest) / 4);
    final top = math.max(step, (highest / step).ceil() * step);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final plotTop = _countSpace;
        final plotHeight = math.max(
          40.0,
          constraints.maxHeight - _labels - plotTop,
        );
        final slot = (width - _axis) / months.length;
        final barWidth = (slot * 0.52).clamp(14.0, 68.0);
        double yOf(num value) => plotTop + plotHeight * (1 - value / top);

        final children = <Widget>[
          // Gridlines and the count axis.
          for (var v = 0.0; v <= top + 1e-9; v += step) ...[
            Positioned(
              left: _axis,
              right: 0,
              top: yOf(v),
              child: Container(height: 1, color: c.border),
            ),
            Positioned(
              left: 0,
              width: _axis - 8,
              top: yOf(v) - 7,
              child: Text(
                NumberFormat('#,##0').format(v),
                textAlign: TextAlign.right,
                style: TextStyle(color: c.textSecondary, fontSize: 11),
              ),
            ),
          ],
        ];

        for (var i = 0; i < months.length; i++) {
          final month = months[i];
          final count = counts[month] ?? 0;
          final tier = scale.tierOf(count);
          final isSelected = month == selected;
          final dimmed = selected != null && !isSelected;
          final height = count == 0
              ? 2.0
              : math.max(3.0, plotHeight * count / top);
          final left = _axis + slot * i;
          children.add(
            Positioned(
              left: left,
              width: slot,
              top: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => onHover(month),
                onExit: (_) => onHover(null),
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label:
                      '${demandMonthLabel(month)}, ${_orders(count)}, '
                      '${tier.label}',
                  child: InkWell(
                    key: Key(
                      'marketDemandBar_${DateFormat('yyyy-MM').format(month)}',
                    ),
                    onTap: () => onSelect(month),
                    onFocusChange: (on) => onHover(on ? month : null),
                    hoverColor: Colors.transparent,
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    focusColor: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AnimatedOpacity(
                          duration: duration,
                          opacity: dimmed ? 0.5 : 1,
                          child: Text(
                            '$count',
                            style: TextStyle(
                              color: isSelected
                                  ? c.textPrimary
                                  : c.textSecondary,
                              fontSize: 11.5,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedScale(
                          duration: duration,
                          curve: Curves.easeOut,
                          alignment: Alignment.bottomCenter,
                          scale: isSelected ? 1.05 : 1,
                          child: AnimatedOpacity(
                            duration: duration,
                            opacity: dimmed ? 0.55 : 1,
                            child: AnimatedContainer(
                              duration: duration,
                              curve: Curves.easeOut,
                              width: barWidth,
                              height: height,
                              decoration: BoxDecoration(
                                color: tier.color,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                                border: isSelected
                                    ? Border.all(color: kDemandGold, width: 2)
                                    : null,
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.10,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: _labels,
                          child: Center(
                            child: AnimatedContainer(
                              duration: duration,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _goldWash
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                DateFormat(
                                  months.length > 8 ? 'MMM' : 'MMM y',
                                ).format(month),
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFF7A5A00)
                                      : c.textSecondary,
                                  fontSize: 11.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // The hovered month's box, beside its bar on whichever side has
        // room. It goes when the pointer leaves.
        final h = hovered;
        if (h != null && months.contains(h)) {
          final i = months.indexOf(h);
          final count = counts[h] ?? 0;
          final barRight = _axis + slot * i + slot / 2 + barWidth / 2;
          final barLeft = _axis + slot * i + slot / 2 - barWidth / 2;
          const boxWidth = 220.0;
          final left = barRight + 10 + boxWidth <= width
              ? barRight + 10
              : math.max(0.0, barLeft - 10 - boxWidth);
          final barTop = count == 0 ? plotTop + plotHeight : yOf(count);
          children.add(
            Positioned(
              left: left,
              top: math.max(0.0, math.min(barTop - 20, plotTop + 10)),
              child: IgnorePointer(child: tooltip(h)),
            ),
          );
        }

        return Stack(clipBehavior: Clip.none, children: children);
      },
    );
  }
}

/// A round step at least [raw]: 1, 2, 2.5 or 5 times a power of ten.
int _niceStep(double raw) {
  if (raw <= 1) return 1;
  final magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  for (final f in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    final step = f * magnitude;
    if (step >= raw && step == step.roundToDouble()) return step.round();
  }
  return (10 * magnitude).round();
}

// ---- The panel on the right ----

class _DemandPanel extends StatelessWidget {
  final AdminPalette palette;
  final List<DemandOrder> orders;
  final List<DateTime> months;
  final Map<DateTime, int> counts;
  final DemandScale scale;
  final String product;
  final DateTime? selected;
  final VoidCallback onClear;
  final ValueChanged<DateTime> onViewFull;

  const _DemandPanel({
    required this.palette,
    required this.orders,
    required this.months,
    required this.counts,
    required this.scale,
    required this.product,
    required this.selected,
    required this.onClear,
    required this.onViewFull,
  });

  @override
  Widget build(BuildContext context) {
    final c = palette;
    final month = selected;
    final scope = month == null ? months : [month];
    final ranking = productDemand(orders, scope);
    final all = product == kAllProducts;
    final total = month == null
        ? counts.values.fold<int>(0, (s, n) => s + n)
        : counts[month] ?? 0;
    final busiest = months.isEmpty
        ? null
        : months.reduce((a, b) => (counts[b] ?? 0) > (counts[a] ?? 0) ? b : a);
    final active = [
      for (final m in months)
        if ((counts[m] ?? 0) > 0) counts[m]!,
    ];
    final average = active.isEmpty
        ? 0.0
        : active.reduce((a, b) => a + b) / active.length;

    return Container(
      key: const Key('marketDemandPanel'),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The dark green heading.
          Container(
            color: _panelGreen,
            padding: const EdgeInsets.fromLTRB(16, 9, 8, 9),
            child: Row(
              children: [
                if (month != null) ...[
                  Container(
                    width: 3,
                    height: 34,
                    decoration: BoxDecoration(
                      color: kDemandGold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        month == null
                            ? 'OVERALL MARKET DEMAND'
                            : 'SELECTED MONTH',
                        style: TextStyle(
                          color: month == null ? Colors.white70 : kDemandGold,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${month == null ? demandPeriodLabel(months) : demandMonthLabel(month)}'
                        '${all ? '' : ' · $product'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (month != null)
                  IconButton(
                    key: const Key('marketDemandClear'),
                    tooltip: 'Back to the overall view',
                    onPressed: onClear,
                    icon: const Icon(Icons.close, size: 18),
                    color: Colors.white,
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        NumberFormat('#,##0').format(total),
                        key: const Key('marketDemandTotal'),
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          'completed ${total == 1 ? 'order' : 'orders'}',
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (month != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _TierChip(palette: c, tier: scale.tierOf(total)),
                    )
                  else if (busiest == null || (counts[busiest] ?? 0) == 0)
                    Text(
                      'No completed orders in this period.',
                      style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                    )
                  else ...[
                    _stat(
                      c,
                      'Average per month',
                      average.toStringAsFixed(
                        average == average.roundToDouble() ? 0 : 1,
                      ),
                    ),
                    _stat(
                      c,
                      'Busiest month',
                      '${demandMonthLabel(busiest)} (${counts[busiest]})',
                    ),
                  ],
                  const SizedBox(height: 8),
                  Divider(height: 1, thickness: 1, color: c.border),
                  const SizedBox(height: 8),
                  Text(
                    all
                        ? 'Most In-Demand Products'
                        : 'Most In-Demand Products (all products)',
                    style: TextStyle(
                      color: c.heading,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ranking.rows.isEmpty
                        ? Center(
                            child: Text(
                              'No completed orders.',
                              style: TextStyle(
                                color: c.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          )
                        // As many of the top five as fit whole (three at
                        // least, with the compact height of 2026-11-10).
                        : LayoutBuilder(
                            builder: (context, box) {
                              final fit = math.max(
                                1,
                                ((box.maxHeight + 1) / (_rankRowHeight + 1))
                                    .floor(),
                              );
                              final shown = math.min(
                                math.min(5, fit),
                                ranking.rows.length,
                              );
                              return ClipRect(
                                child: Column(
                                  children: [
                                    for (var i = 0; i < shown; i++) ...[
                                      if (i > 0)
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: c.border,
                                        ),
                                      _rankRow(c, i, ranking.rows[i]),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  // Always there (the user's request, 2026-11-10): the held
                  // month, else the latest month with orders.
                  SizedBox(
                    height: 36,
                    child: FilledButton.icon(
                      key: const Key('marketDemandViewFull'),
                      onPressed: (month ?? _latestWithOrders()) == null
                          ? null
                          : () => onViewFull(month ?? _latestWithOrders()!),
                      style: FilledButton.styleFrom(
                        backgroundColor: adminActionColor(c),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(Icons.table_rows_outlined, size: 16),
                      // Without a held month it opens the latest one,
                      // where a month can be picked.
                      label: const Text(
                        'View Full Product Demand',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // The latest month with a completed order, else the latest shown.
  DateTime? _latestWithOrders() {
    for (final m in months.reversed) {
      if ((counts[m] ?? 0) > 0) return m;
    }
    return months.isEmpty ? null : months.last;
  }

  static const double _rankRowHeight = 30;

  // A label and its figure on one line.
  Widget _stat(AdminPalette c, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: c.textSecondary, fontSize: 11.5),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _rankRow(AdminPalette c, int i, ProductDemandRow row) {
    final first = i == 0;
    return SizedBox(
      height: _rankRowHeight,
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: first ? adminActionColor(c) : c.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${i + 1}',
              style: TextStyle(
                color: first ? Colors.white : c.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.product,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            _orders(row.orders),
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final AdminPalette palette;
  final String text;
  final Widget? action;
  const _Message({required this.palette, required this.text, this.action});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bar_chart_rounded, size: 26, color: palette.textMuted),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
        ),
        ?action,
      ],
    ),
  );
}
