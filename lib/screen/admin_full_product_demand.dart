import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/audit_log_service.dart';
import '../services/market_price_helpers.dart' show formatPeso;
import '../services/monthly_demand_service.dart';
import '../services/pdf_report_service.dart';
import '../widgets/app_scaffold_messenger.dart';
import 'admin_dashboard_screen.dart'
    show AdminPalette, AdminQuickActionButton, AdminThemeScope;
import 'admin_filter_controls.dart'
    show AdminPillDropdown, adminActionColor, adminCard;
import 'admin_market_demand.dart' show kDemandGold;

/// The two analyses of Full Product Demand: how many completed orders
/// contain a product, and how much of it was sold.
enum DemandAnalysis {
  orders('By Orders'),
  quantity('By Quantity Sold');

  const DemandAnalysis(this.label);
  final String label;
}

enum _Sort { mainDown, mainUp, name, value }

/// FULL PRODUCT DEMAND (the user's design, 2026-11-10): one month's
/// products, opened from Market Demand's View Full Product Demand inside
/// the portal (the sidebar and header stay; Back returns to the dashboard
/// as it was). Two tabs:
///
///  * By Orders: the most in-demand products, by completed orders
///    containing them, with each one's share of the month's orders (order
///    penetration) and demand level.
///  * By Quantity Sold: the top-selling products, by quantity sold, one
///    unit at a time (kilos and heads are never ranked together), with
///    their completed orders and sales value.
///
/// Search, category (and unit) filters, sorting, pages of 10, and the
/// report export of exactly the table on screen.
class AdminFullProductDemand extends StatefulWidget {
  final List<DemandOrder> orders;
  final DateTime month;
  final VoidCallback onBack;

  /// The product Market Demand was showing, put in the search.
  final String? product;

  const AdminFullProductDemand({
    super.key,
    required this.orders,
    required this.month,
    required this.onBack,
    this.product,
  });

  static const int pageSize = 10;

  @override
  State<AdminFullProductDemand> createState() => _AdminFullProductDemandState();
}

class _AdminFullProductDemandState extends State<AdminFullProductDemand> {
  late DateTime _month = widget.month;
  late final _search = TextEditingController(
    text: widget.product == null || widget.product == kAllProducts
        ? ''
        : widget.product,
  );
  DemandAnalysis _analysis = DemandAnalysis.orders;
  String? _category;
  String? _unit;
  _Sort _sort = _Sort.mainDown;
  int _page = 0;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _page = 0));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // Every month with a completed order, newest first, and the one shown.
  List<DateTime> _months() {
    final set = {for (final o in widget.orders) o.month, _month};
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  String get _query => _search.text.trim().toLowerCase();

  bool _matches(String product, String category) =>
      (_category == null || category == _category) &&
      (_query.isEmpty || product.toLowerCase().contains(_query));

  int _compareName(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  // ---- By Orders ----

  List<RankedProductDemand> _orderRows(FullProductDemand data) {
    final rows = data.filtered(query: _search.text, category: _category);
    switch (_sort) {
      case _Sort.mainDown || _Sort.value:
        break; // Already ranked.
      case _Sort.mainUp:
        rows.sort((a, b) {
          final c = a.row.orders.compareTo(b.row.orders);
          return c != 0 ? c : _compareName(a.row.product, b.row.product);
        });
      case _Sort.name:
        rows.sort((a, b) => _compareName(a.row.product, b.row.product));
    }
    return rows;
  }

  // ---- By Quantity Sold ----

  List<RankedQuantity> _quantityRows(
    List<ProductQuantityRow> all,
    String unit,
  ) {
    final rows = [
      for (final r in rankQuantities(all, unit))
        if (_matches(r.row.product, r.row.category)) r,
    ];
    switch (_sort) {
      case _Sort.mainDown:
        break; // Already ranked.
      case _Sort.mainUp:
        rows.sort((a, b) {
          final c = a.row.quantity.compareTo(b.row.quantity);
          return c != 0 ? c : _compareName(a.row.product, b.row.product);
        });
      case _Sort.name:
        rows.sort((a, b) => _compareName(a.row.product, b.row.product));
      case _Sort.value:
        rows.sort((a, b) {
          final c = b.row.sales.compareTo(a.row.sales);
          return c != 0 ? c : _compareName(a.row.product, b.row.product);
        });
    }
    return rows;
  }

  static String _qty(num n) => NumberFormat('#,##0.##').format(n);

  FullDemandExport _export(
    FullProductDemand data,
    List<RankedProductDemand> orderRows,
    List<RankedQuantity> quantityRows,
    String? unit,
  ) {
    final top = data.ranked.isEmpty ? null : data.ranked.first.row;
    final sortLabel = switch ((_analysis, _sort)) {
      (_, _Sort.name) => 'Product name, A to Z',
      (DemandAnalysis.orders, _Sort.mainUp) => 'Completed orders, fewest first',
      (DemandAnalysis.orders, _) => 'Completed orders, most first',
      (DemandAnalysis.quantity, _Sort.mainUp) => 'Quantity sold, least first',
      (DemandAnalysis.quantity, _Sort.value) => 'Sales value, highest first',
      (DemandAnalysis.quantity, _) => 'Quantity sold, most first',
    };
    final filters = <(String, String)>[
      ('Category', _category ?? 'All Categories'),
      if (_analysis == DemandAnalysis.quantity) ('Unit', unit ?? '—'),
      if (_query.isNotEmpty) ('Product search', _search.text.trim()),
      ('Sorted by', sortLabel),
    ];
    final summary = [
      ['Distinct completed orders', '${data.totalOrders}'],
      ['Products ordered', '${data.ranked.length}'],
      [
        'Most in-demand product',
        top == null
            ? '—'
            : '${top.product} (${top.orders} ${top.orders == 1 ? 'order' : 'orders'})',
      ],
    ];
    if (_analysis == DemandAnalysis.orders) {
      return FullDemandExport(
        month: _month,
        analysis: _analysis.label,
        filters: filters,
        summary: summary,
        headers: const [
          'Rank',
          'Product',
          'Category',
          'Completed Orders',
          'Share of Monthly Orders',
          'Demand Level',
        ],
        rows: [
          for (final r in orderRows)
            [
              '${r.rank}',
              r.row.product,
              r.row.category,
              '${r.row.orders}',
              '${r.row.share.toStringAsFixed(1)}%',
              r.tier.label,
            ],
        ],
        weights: const [0.5, 1.7, 1.2, 1.1, 1.3, 1.3],
        notes: [
          'Share of Monthly Orders is order penetration: the share of the '
              'month\'s ${data.totalOrders} completed orders that include the '
              'product. An order with several products counts once for each, '
              'so the shares can add up to more than 100%. They are not '
              'shares of sales value.',
        ],
      );
    }
    return FullDemandExport(
      month: _month,
      analysis: _analysis.label,
      filters: filters,
      summary: summary,
      headers: const [
        'Rank',
        'Product',
        'Category',
        'Quantity Sold',
        'Unit',
        'Completed Orders',
        'Total Sales Value',
      ],
      rows: [
        for (final r in quantityRows)
          [
            '${r.rank}',
            r.row.product,
            r.row.category,
            _qty(r.row.quantity),
            r.row.unit,
            '${r.row.orders}',
            formatPeso(r.row.sales),
          ],
      ],
      weights: const [0.5, 1.6, 1.2, 1.1, 0.9, 1.1, 1.3],
      notes: [
        'Quantity sold is the total bought in completed orders, in $unit. '
            'Products sold in other units are ranked under those units: '
            'quantities in different units are never added together.',
      ],
    );
  }

  Future<void> _download(FullDemandExport export) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await PdfReportService.buildFullProductDemandReport(export);
      await PdfReportService.share(
        bytes,
        'agritrade_full_product_demand_${DateFormat('yyyy_MM').format(_month)}.pdf',
      );
      AuditLogService.log(
        AuditAction.exportReport,
        'Exported the Full Product Demand Report (${demandMonthLabel(_month)}, '
        '${export.analysis}, ${_category ?? 'All Categories'}, PDF).',
      );
    } catch (error) {
      debugPrint('Full Product Demand export failed: $error');
      if (mounted) {
        showAppMessage(
          context,
          'Could not export the Full Product Demand Report. Please try again.',
          kind: MessageKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final data = FullProductDemand.of(widget.orders, _month);
    final quantities = productQuantities(widget.orders, [_month]);
    final units = quantityUnits(quantities);
    if (_unit == null || !units.contains(_unit)) {
      _unit = units.isEmpty ? null : units.first;
    }
    final categories = {
      ...data.categories,
      for (final q in quantities) q.category,
    }.toList()..sort();
    if (_category != null && !categories.contains(_category)) _category = null;

    final orderRows = _orderRows(data);
    final quantityRows = _unit == null
        ? const <RankedQuantity>[]
        : _quantityRows(quantities, _unit!);
    final count = _analysis == DemandAnalysis.orders
        ? orderRows.length
        : quantityRows.length;
    final pages = math.max(1, (count / AdminFullProductDemand.pageSize).ceil());
    if (_page >= pages) _page = pages - 1;
    final start = _page * AdminFullProductDemand.pageSize;
    final export = _export(data, orderRows, quantityRows, _unit);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('fullDemandBack'),
              onPressed: widget.onBack,
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
            'Full Product Demand',
            style: TextStyle(
              color: c.heading,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Detailed product demand for ${demandMonthLabel(_month)}.',
            style: TextStyle(color: c.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          _controls(c, categories, units, export),
          const SizedBox(height: 16),
          _summary(c, data),
          const SizedBox(height: 16),
          _tabs(c),
          const SizedBox(height: 12),
          Container(
            decoration: adminCard(c),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _headerRow(c),
                if (count == 0)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      data.totalOrders == 0
                          ? 'No completed orders in ${demandMonthLabel(_month)}.'
                          : 'No product matches the search or filters.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                    ),
                  )
                else if (_analysis == DemandAnalysis.orders)
                  for (final (i, r)
                      in orderRows
                          .skip(start)
                          .take(AdminFullProductDemand.pageSize)
                          .indexed) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: c.border),
                    _OrdersRow(palette: c, item: r),
                  ]
                else
                  for (final (i, r)
                      in quantityRows
                          .skip(start)
                          .take(AdminFullProductDemand.pageSize)
                          .indexed) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: c.border),
                    _QuantityRow(palette: c, item: r),
                  ],
                Divider(height: 1, thickness: 1, color: c.border),
                _footer(c, count, start, pages),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final text in export.notes)
            Text(text, style: TextStyle(color: c.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _controls(
    AdminPalette c,
    List<String> categories,
    List<String> units,
    FullDemandExport export,
  ) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AdminPillDropdown<DateTime>(
          key: const Key('fullDemandMonth'),
          value: _month,
          width: 190,
          icon: Icons.calendar_today_outlined,
          items: [
            for (final m in _months())
              DropdownMenuItem(value: m, child: Text(demandMonthLabel(m))),
          ],
          onChanged: (m) => setState(() {
            _month = m;
            _page = 0;
          }),
        ),
        Container(
          width: 240,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 16, color: c.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('fullDemandSearch'),
                  controller: _search,
                  style: TextStyle(color: c.textPrimary, fontSize: 12.5),
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
        AdminPillDropdown<String?>(
          key: const Key('fullDemandCategory'),
          value: _category,
          width: 190,
          icon: Icons.category_outlined,
          items: [
            const DropdownMenuItem(value: null, child: Text('All Categories')),
            for (final name in categories)
              DropdownMenuItem(value: name, child: Text(name)),
          ],
          onChanged: (value) => setState(() {
            _category = value;
            _page = 0;
          }),
        ),
        // One unit at a time for quantities: never kilos with heads.
        if (_analysis == DemandAnalysis.quantity && _unit != null)
          AdminPillDropdown<String>(
            key: const Key('fullDemandUnit'),
            value: _unit!,
            width: 170,
            icon: Icons.straighten,
            items: [
              for (final u in units)
                DropdownMenuItem(value: u, child: Text('Per $u')),
            ],
            onChanged: (value) => setState(() {
              _unit = value;
              _page = 0;
            }),
          ),
        AdminQuickActionButton(
          icon: Icons.download,
          label: _exporting ? 'Exporting…' : 'Export Report',
          onPressed: () => _download(export),
        ),
      ],
    );
  }

  Widget _summary(AdminPalette c, FullProductDemand data) {
    final top = data.ranked.isEmpty ? null : data.ranked.first.row;
    Widget card(String label, String value, String caption, {Key? key}) =>
        Expanded(
          child: Container(
            key: key,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: adminCard(c),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        card(
          'COMPLETED ORDERS',
          NumberFormat('#,##0').format(data.totalOrders),
          'Distinct orders in ${DateFormat('MMMM y').format(_month)}',
          key: const Key('fullDemandTotal'),
        ),
        const SizedBox(width: 12),
        card(
          'PRODUCTS ORDERED',
          '${data.ranked.length}',
          'Distinct products with completed orders',
        ),
        const SizedBox(width: 12),
        card(
          'MOST IN-DEMAND',
          top?.product ?? '—',
          top == null
              ? 'No completed orders'
              : '${top.orders} ${top.orders == 1 ? 'order' : 'orders'} · '
                    '${top.share.toStringAsFixed(1)}% of orders',
        ),
      ],
    );
  }

  Widget _tabs(AdminPalette c) {
    Widget tab(DemandAnalysis a) {
      final on = a == _analysis;
      return InkWell(
        key: Key('fullDemandTab_${a.name}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() {
          _analysis = a;
          _sort = _Sort.mainDown;
          _page = 0;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: on ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: on ? adminActionColor(c) : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Text(
            a.label,
            style: TextStyle(
              color: on ? adminActionColor(c) : c.textSecondary,
              fontSize: 12.5,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final a in DemandAnalysis.values) tab(a)],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _analysis == DemandAnalysis.orders
                ? 'Most in-demand products: completed orders containing each '
                      'product.'
                : 'Top-selling products: quantity sold in completed orders, '
                      'per ${_unit ?? 'unit'}.',
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _headerRow(AdminPalette c) {
    final style = TextStyle(
      color: c.textSecondary,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
    );
    Widget sortable(String label, Key key, _Sort down, _Sort? up) {
      final active = _sort == down || (up != null && _sort == up);
      return InkWell(
        key: key,
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() {
          _sort = up != null && _sort == down ? up : down;
          _page = 0;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label, style: style)),
              const SizedBox(width: 4),
              Icon(
                !active
                    ? Icons.unfold_more
                    : _sort == _Sort.mainUp
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 14,
                color: active ? adminActionColor(c) : c.textMuted,
              ),
            ],
          ),
        ),
      );
    }

    Widget cell(int flex, Widget child) => Expanded(
      flex: flex,
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
    final name = sortable(
      'Product Name',
      const Key('fullDemandSortName'),
      _Sort.name,
      null,
    );
    return Container(
      color: c.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: _analysis == DemandAnalysis.orders
          ? Row(
              children: [
                SizedBox(width: 56, child: Text('Rank', style: style)),
                cell(3, name),
                cell(2, Text('Category', style: style)),
                cell(
                  2,
                  sortable(
                    'Completed Orders',
                    const Key('fullDemandSortOrders'),
                    _Sort.mainDown,
                    _Sort.mainUp,
                  ),
                ),
                cell(
                  3,
                  sortable(
                    'Share of Monthly Orders',
                    const Key('fullDemandSortShare'),
                    _Sort.mainDown,
                    _Sort.mainUp,
                  ),
                ),
                cell(2, Text('Demand Level', style: style)),
              ],
            )
          : Row(
              children: [
                SizedBox(width: 56, child: Text('Rank', style: style)),
                cell(3, name),
                cell(2, Text('Category', style: style)),
                cell(
                  2,
                  sortable(
                    'Quantity Sold',
                    const Key('fullDemandSortQuantity'),
                    _Sort.mainDown,
                    _Sort.mainUp,
                  ),
                ),
                cell(1, Text('Unit', style: style)),
                cell(2, Text('Completed Orders', style: style)),
                cell(
                  2,
                  sortable(
                    'Total Sales Value',
                    const Key('fullDemandSortValue'),
                    _Sort.value,
                    null,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _footer(AdminPalette c, int total, int start, int pages) {
    final count = math.min(AdminFullProductDemand.pageSize, total - start);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total == 0
                  ? 'No products'
                  : 'Showing ${start + 1}–${start + count} of $total '
                        '${total == 1 ? 'product' : 'products'}',
              style: TextStyle(color: c.textSecondary, fontSize: 11.5),
            ),
          ),
          IconButton(
            key: const Key('fullDemandPrev'),
            tooltip: 'Previous page',
            iconSize: 18,
            onPressed: _page > 0 ? () => setState(() => _page--) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            '${_page + 1} / $pages',
            style: TextStyle(color: c.textPrimary, fontSize: 12),
          ),
          IconButton(
            key: const Key('fullDemandNext'),
            tooltip: 'Next page',
            iconSize: 18,
            onPressed: _page < pages - 1 ? () => setState(() => _page++) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// A rank on a small circle: the first dark green with a gold ring.
Widget _rankBadge(AdminPalette c, int rank) => Container(
  width: 24,
  height: 24,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    color: rank == 1 ? adminActionColor(c) : c.surfaceAlt,
    shape: BoxShape.circle,
    border: rank == 1 ? Border.all(color: kDemandGold, width: 1.5) : null,
  ),
  child: Text(
    '$rank',
    style: TextStyle(
      color: rank == 1 ? Colors.white : c.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    ),
  ),
);

/// A table row that turns pale green under the pointer.
class _HoverRow extends StatefulWidget {
  final AdminPalette palette;
  final Key rowKey;
  final List<Widget> children;
  const _HoverRow({
    required this.palette,
    required this.rowKey,
    required this.children,
  });

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: Container(
      key: widget.rowKey,
      color: _hover ? widget.palette.greenBg : null,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      child: Row(children: widget.children),
    ),
  );
}

class _OrdersRow extends StatelessWidget {
  final AdminPalette palette;
  final RankedProductDemand item;
  const _OrdersRow({required this.palette, required this.item});

  @override
  Widget build(BuildContext context) {
    final c = palette;
    final r = item;
    final text = TextStyle(color: c.textPrimary, fontSize: 12.5);
    return _HoverRow(
      palette: c,
      rowKey: Key('fullDemandRow_${r.row.product}'),
      children: [
        SizedBox(
          width: 56,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _rankBadge(c, r.rank),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            r.row.product,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            r.row.category,
            style: text.copyWith(color: c.textSecondary),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            '${r.row.orders}',
            style: text.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Text('${r.row.share.toStringAsFixed(1)}%', style: text),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (r.row.share / 100).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: c.surfaceAlt,
                    color: r.tier.color,
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: r.tier.color,
                  shape: BoxShape.circle,
                  border: r.tier == DemandTier.veryLow
                      ? Border.all(color: c.textMuted, width: 0.8)
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  r.tier.label.replaceAll(' Demand', ''),
                  style: text.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuantityRow extends StatelessWidget {
  final AdminPalette palette;
  final RankedQuantity item;
  const _QuantityRow({required this.palette, required this.item});

  @override
  Widget build(BuildContext context) {
    final c = palette;
    final r = item.row;
    final text = TextStyle(color: c.textPrimary, fontSize: 12.5);
    return _HoverRow(
      palette: c,
      rowKey: Key('fullDemandQtyRow_${r.product}'),
      children: [
        SizedBox(
          width: 56,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _rankBadge(c, item.rank),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            r.product,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(r.category, style: text.copyWith(color: c.textSecondary)),
        ),
        Expanded(
          flex: 2,
          child: Text(
            NumberFormat('#,##0.##').format(r.quantity),
            style: text.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          flex: 1,
          child: Text(r.unit, style: text.copyWith(color: c.textSecondary)),
        ),
        Expanded(flex: 2, child: Text('${r.orders}', style: text)),
        Expanded(flex: 2, child: Text(formatPeso(r.sales), style: text)),
      ],
    );
  }
}
