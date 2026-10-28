import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/dashboard_analytics_service.dart';
import '../services/market_price_helpers.dart';
import '../widgets/shimmer.dart';
import 'admin_dashboard_screen.dart'
    show AdminThemeScope, AdminPalette, AdminRadii;
import 'admin_filter_controls.dart' show AdminPillDropdown, adminActionColor;

// ============================================================
// The top of the Admin Analytics Dashboard: the Overview summary strip,
// the shared chart card and Sales by Category. One green accent throughout, in
// lighter and darker steps, on neutral surfaces with thin borders.
//
// Every widget here shows only what it is handed or computes from real
// orders — nothing is sampled, padded or estimated. A period with no
// completed sales shows an empty state, never a chart of zeros.
// ============================================================

/// The portal's green at strength [t]: 0 is the palest step, 1 the
/// strongest. Used for bars and donut slices so that "more" reads darker.
Color adminGreenAt(AdminPalette c, double t) {
  final pale = Color.lerp(c.green, c.surface, 0.68)!;
  final strong = c.isDark ? c.green : Color.lerp(c.green, Colors.black, 0.28)!;
  return Color.lerp(pale, strong, t.clamp(0.0, 1.0))!;
}

/// One figure of the Overview strip.
class AdminOverviewItem {
  final String label;
  final IconData icon;

  /// Null while the figure is still loading.
  final String? value;
  final String caption;

  /// The figure could not be loaded (shown as a dash, never as zero).
  final bool failed;

  /// Something waiting on the Admin: its card is tinted amber, not green.
  final bool attention;

  /// Opens the page the figure comes from; null for a card that is not
  /// clickable.
  final VoidCallback? onTap;

  /// The card is the one chosen, where the cards filter what is under
  /// them: a stronger border in its own colour.
  final bool selected;

  const AdminOverviewItem({
    required this.label,
    required this.icon,
    required this.value,
    required this.caption,
    this.failed = false,
    this.attention = false,
    this.onTap,
    this.selected = false,
  });
}

/// The Overview: each figure on its own white card, side by side
/// and equal in width and height. Wraps to two per row, then one, on
/// narrower windows.
class AdminOverviewStrip extends StatelessWidget {
  final List<AdminOverviewItem> items;
  const AdminOverviewStrip({super.key, required this.items});

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900 ? items.length : (width >= 520 ? 2 : 1);
        final rows = <List<AdminOverviewItem>>[
          for (var i = 0; i < items.length; i += columns)
            items.sublist(i, math.min(i + columns, items.length)),
        ];
        return Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: _gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      Expanded(
                        child: i < rows[r].length
                            ? _card(c, rows[r][i])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _card(AdminPalette c, AdminOverviewItem item) {
    final radius = BorderRadius.circular(AdminRadii.card);
    // Material + InkWell, so a clickable card shows the pointer, a hover
    // tint and a ripple inside its own rounded shape.
    // White with a light grey border, as every card; the icon box carries
    // the colour. One needing attention keeps a faint amber, a warning.
    return Material(
      color: item.attention && !c.isDark
          ? Color.alphaBlend(c.amber.withValues(alpha: 0.06), c.surface)
          : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: item.selected
            ? BorderSide(
                color: item.attention ? c.amber : adminActionColor(c),
                width: 1.5,
              )
            : BorderSide(
                color: item.attention && !c.isDark
                    ? Color.alphaBlend(
                        c.amber.withValues(alpha: 0.16),
                        c.border,
                      )
                    : c.border,
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        hoverColor: c.surfaceAlt,
        splashColor: c.border,
        child: _OverviewSegment(item: item),
      ),
    );
  }
}

class _OverviewSegment extends StatelessWidget {
  final AdminOverviewItem item;
  const _OverviewSegment({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final loading = item.value == null;

    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              // Neutral, with the icon in dark green; amber when it needs
              // attention.
              color: item.attention ? c.amberBg : c.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              item.icon,
              size: 22,
              color: item.attention ? c.amber : adminActionColor(c),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                // Same line heights loading or loaded, so nothing shifts.
                SizedBox(
                  height: 28,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: loading
                        ? Shimmer(
                            baseColor: c.surfaceAlt,
                            highlightColor: c.border,
                            child: bar(72, 20),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              item.value!,
                              style: TextStyle(
                                color: item.failed
                                    ? c.textMuted
                                    : c.textPrimary,
                                fontSize: 22,
                                height: 1.1,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loading ? ' ' : item.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Last 6 Months" period filter on a chart card.
class AdminPeriodDropdown extends StatelessWidget {
  final int months;
  final ValueChanged<int> onChanged;
  const AdminPeriodDropdown({
    super.key,
    required this.months,
    required this.onChanged,
  });

  static const List<int> options = [3, 6, 12];
  static const int initial = 6;

  static String label(int months) => 'Last $months Months';

  // The portal's dropdown: the same size and look as every other.
  @override
  Widget build(BuildContext context) => AdminPillDropdown<int>(
    // Room for "Last 12 Months" and no more.
    width: 184,
    value: months,
    icon: Icons.date_range_outlined,
    items: [
      for (final option in options)
        DropdownMenuItem(value: option, child: Text(label(option))),
    ],
    onChanged: onChanged,
  );
}

/// The shell every analytics card shares — same padding, header and body
/// height — so they stay the same size next to each other.
class AdminChartCard extends StatelessWidget {
  final String title;
  final String subtitle;

  /// Optional control at the right of the header (a filter, a search).
  final Widget? trailing;

  /// Below this card width, [trailing] goes under the title (still on the
  /// right) instead of beside it; 0 keeps it beside the title always.
  final double trailingStackBelow;
  final Widget child;

  /// Height of the area under the header; equal on cards that sit side
  /// by side.
  final double bodyHeight;

  const AdminChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.trailingStackBelow = 0,
    required this.child,
    this.bodyHeight = 264,
  });

  /// The space inside every chart card, on all four sides.
  static const double padding = 24;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AdminRadii.card),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminCardHeader(
            title: title,
            subtitle: subtitle,
            trailing: trailing,
            stackBelow: trailingStackBelow,
          ),
          const SizedBox(height: 16),
          SizedBox(height: bodyHeight, child: child),
        ],
      ),
    );
  }
}

/// A card's header: the title and subtitle on the left, and its controls
/// (a search, a year, a filter) level with them on the right. Below
/// [stackBelow] wide, the controls go under the title, still on the right,
/// so the title is never cut short.
class AdminCardHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  final double stackBelow;

  const AdminCardHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.stackBelow = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.textSecondary, fontSize: 12),
        ),
      ],
    );
    final controls = trailing;
    if (controls == null) return Row(children: [Expanded(child: heading)]);
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < stackBelow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: controls),
              ],
            )
          : Row(
              crossAxisAlignment: stackBelow > 0
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                const SizedBox(width: 12),
                controls,
              ],
            ),
    );
  }
}

class AdminChartEmpty extends StatelessWidget {
  final IconData icon;

  /// A short heading over [message] ("No data to display"), if any.
  final String? title;
  final String message;
  const AdminChartEmpty({
    super.key,
    required this.icon,
    this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final heading = title;
    // In the middle of the space it is given, the icon, the heading and the
    // line under it.
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(AdminRadii.card),
            ),
            child: Icon(icon, size: 26, color: c.textSecondary),
          ),
          const SizedBox(height: 12),
          if (heading != null) ...[
            Text(
              heading,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget adminLegendDot(Color color) => Container(
  width: 10,
  height: 10,
  decoration: BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(3),
  ),
);

// "₱20k", "₱1.5M" — axis labels only; exact figures use formatPeso.
String adminCompactPeso(double value) {
  String trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  if (value >= 1000000) return '₱${trim(value / 1000000)}M';
  if (value >= 1000) return '₱${trim(value / 1000)}k';
  return '₱${trim(value)}';
}

// The next "round" number at or above [value] that divides into 4 even
// steps, for the top of the value axis.
double adminAxisTop(double value) {
  if (value <= 0) return 4;
  final magnitude = math
      .pow(10, (math.log(value) / math.ln10).floor())
      .toDouble();
  final fraction = value / magnitude;
  for (final step in const [1.0, 2.0, 4.0, 5.0, 8.0, 10.0]) {
    if (fraction <= step) return step * magnitude;
  }
  return 10 * magnitude;
}

/// SALES BY CATEGORY — what buyers actually purchased: completed-order
/// revenue in the selected period, grouped by the product's commodity
/// category (see [DashboardAnalyticsService.categoryRevenue]).
class AdminSalesByCategoryCard extends StatefulWidget {
  /// Completed-order revenue per category for the last N calendar months.
  final Map<String, num> Function(int months) revenueFor;

  /// The card's body height (the card beside it uses the same).
  final double bodyHeight;

  const AdminSalesByCategoryCard({
    super.key,
    required this.revenueFor,
    this.bodyHeight = 264,
  });

  @override
  State<AdminSalesByCategoryCard> createState() =>
      _AdminSalesByCategoryCardState();
}

class _AdminSalesByCategoryCardState extends State<AdminSalesByCategoryCard> {
  int _months = AdminPeriodDropdown.initial;

  // Beyond this many categories the smallest are shown together as "Other".
  static const int _maxSlices = 7;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final sorted =
        widget
            .revenueFor(_months)
            .entries
            .where((e) => e.value > 0)
            .map((e) => (name: e.key, value: e.value.toDouble()))
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<double>(0, (sum, e) => sum + e.value);

    var slices = sorted;
    if (sorted.length > _maxSlices) {
      final rest = sorted.sublist(_maxSlices - 1);
      slices = [
        ...sorted.take(_maxSlices - 1),
        (name: 'Other', value: rest.fold<double>(0, (sum, e) => sum + e.value)),
      ];
    }
    // Largest share strongest, down to the palest.
    Color colorOf(int i) =>
        adminGreenAt(c, slices.length == 1 ? 1 : 1 - i / (slices.length - 1));

    return AdminChartCard(
      title: 'Sales by Category',
      subtitle: 'Completed purchases by commodity category',
      bodyHeight: widget.bodyHeight,
      trailing: AdminPeriodDropdown(
        months: _months,
        onChanged: (months) => setState(() => _months = months),
      ),
      child: slices.isEmpty
          ? const AdminChartEmpty(
              icon: Icons.pie_chart_outline_rounded,
              message:
                  'No completed category sales data available for the '
                  'selected period.',
            )
          : Row(
              children: [
                SizedBox(
                  width: 172,
                  height: 172,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          startDegreeOffset: -90,
                          centerSpaceRadius: 56,
                          sectionsSpace: 2,
                          sections: [
                            for (var i = 0; i < slices.length; i++)
                              PieChartSectionData(
                                value: slices[i].value,
                                color: colorOf(i),
                                radius: 28,
                                showTitle: false,
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                formatPeso(total),
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Total Sales',
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < slices.length; i++)
                        Padding(
                          padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                          child: Row(
                            children: [
                              adminLegendDot(colorOf(i)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  slices[i].name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _share(slices[i].value, total),
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static String _share(double value, double total) {
    if (total <= 0) return '0%';
    final percent = value / total * 100;
    if (percent > 0 && percent < 1) return '<1%';
    return '${percent.round()}%';
  }
}

/// A chart card that has not loaded yet: the same box, padding and height
/// as [AdminChartCard], with shimmering bars where the title and the chart
/// will be — so the section is in place at once and nothing shifts when
/// the real card replaces it.
class AdminChartCardSkeleton extends StatelessWidget {
  final double bodyHeight;
  const AdminChartCardSkeleton({super.key, this.bodyHeight = 264});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    Widget bar(double? width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AdminChartCard.padding),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AdminRadii.card),
        border: Border.all(color: c.border),
      ),
      // The shimmer only covers the bars, not the card around them.
      child: Shimmer(
        baseColor: c.surfaceAlt,
        highlightColor: c.border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Same height as the real header: a 16px title and a 12.5px
            // subtitle with 3px between them.
            SizedBox(
              height: 38,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [bar(170, 16), bar(240, 12)],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: bodyHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  bar(120, 18),
                  const SizedBox(height: 16),
                  Expanded(child: bar(null, double.infinity)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
