import 'package:flutter/material.dart';

import '../data/commodity_master_list.dart';
import '../services/admin_perf.dart';
import '../services/dashboard_data_service.dart';
import '../services/historical_demand_service.dart';
import '../services/market_diagnostics_service.dart';
import '../services/price_trend_service.dart';
import 'admin_analytics_widgets.dart'
    show AdminCommoditySearchField, matchCommodities;
import 'admin_dashboard_screen.dart'
    show
        AdminThemeScope,
        AdminPalette,
        AdminEmptyState,
        AdminLoadingSpinner,
        AdminQuickActionButton,
        AdminRadii;
import 'admin_overview_widgets.dart' show AdminCardHeader;
import 'admin_price_trend_chart.dart';
import 'historical_demand_import.dart';

/// Analytics Dashboard → Market Change Analysis: for one commodity, its
/// average price month by month, one year against another (see
/// [AdminPriceTrendSection]); then what changed in
/// its demand, local supply and price over the last 30 days against the 30
/// before, how this month compared in previous years, and the possible
/// factors the data points to (see [MarketDiagnosticsService]).
///
/// Read from AgriTrade+ completed orders and listings (the portal's shared
/// live data), Price Management's reference prices, and any imported
/// historical demand from the year of the first completed order on —
/// never an older year, as on the charts. Nothing is forecast.
class AdminMarketTrendsCard extends StatefulWidget {
  const AdminMarketTrendsCard({super.key});

  @override
  State<AdminMarketTrendsCard> createState() => _AdminMarketTrendsCardState();
}

class _AdminMarketTrendsCardState extends State<AdminMarketTrendsCard> {
  // From this width the card has two columns (price chart | last 30 days).
  static const double _twoColumnWidth = 900;

  // Between the two columns (the line in its middle), or above and below
  // the line between them when they are stacked.
  static const double _gutter = 48;

  // Whether the Import Historical Data button is shown. Hidden while there
  // is no reliable source to import from; the import itself is kept, and
  // setting this to true brings the button back.
  static const bool _importEnabled = false;

  late final Stream<List<HistoricalDemandRecord>> _historical =
      AdminPerf.firstEvent(
        'market trends: historical_demand stream',
        HistoricalDemandService.watch(),
        describe: (records) => '${records.length} records',
      );

  String? _commodity;

  @override
  void initState() {
    super.initState();
    DashboardDataService.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AdminRadii.card),
        border: Border.all(color: c.border),
      ),
      // Rebuilt when the commodity list, the orders or the listings change.
      child: ListenableBuilder(
        listenable: Listenable.merge([
          CommodityRegistry.instance,
          DashboardDataService.instance,
        ]),
        builder: (context, _) {
          final names = matchCommodities([
            for (final commodity in CommodityRegistry.instance.all)
              commodity.name,
          ], '');
          if (_commodity == null || !names.contains(_commodity)) {
            _commodity = names.isEmpty ? null : names.first;
          }
          final commodity = _commodity;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The search (and the import, when shown) level with the title
              // on the right, as on Market Demand and Price Trend vs.
              // Baseline.
              AdminCardHeader(
                title: 'Market Change Analysis',
                subtitle: commodity == null
                    ? 'Price over the years, and the last 30 days'
                    : '$commodity · price over the years, and the last 30 '
                          'days',
                stackBelow: 760,
                trailing: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    if (names.isNotEmpty)
                      AdminCommoditySearchField(
                        key: ValueKey(commodity),
                        commodities: names,
                        selected: commodity,
                        hint: 'Search product',
                        onSelected: (name) => setState(() => _commodity = name),
                      ),
                    if (_importEnabled)
                      AdminQuickActionButton(
                        icon: Icons.upload_file_outlined,
                        label: 'Import Historical Data',
                        filled: true,
                        onPressed: () => showHistoricalDemandImport(context),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (commodity == null)
                const AdminEmptyState(
                  icon: Icons.insights_outlined,
                  title: 'No supported commodities yet',
                  subtitle: 'Add commodities in Price Management first.',
                )
              else
                StreamBuilder<List<HistoricalDemandRecord>>(
                  stream: _historical,
                  builder: (context, historical) {
                    final data = DashboardDataService.instance;
                    if (!data.hasLoadedOnce && data.lastError == null) {
                      return const AdminLoadingSpinner();
                    }
                    if (!historical.hasData && !historical.hasError) {
                      return const AdminLoadingSpinner();
                    }
                    final completedOrders = [
                      for (final d in data.orders) d.data(),
                    ];
                    final products = [for (final d in data.products) d.data()];
                    // Imported records from the year of the first completed
                    // order on, as on the charts: an older year is never
                    // shown, here or in the seasonal pattern.
                    final firstYear = PriceTrendService.yearsOnRecord(
                      completedOrders,
                      DateTime.now(),
                    ).first;
                    final records = <HistoricalDemandRecord>[
                      for (final record in historical.data ?? const [])
                        if (record.year >= firstYear) record,
                    ];
                    // The price year against year, then what changed in
                    // the last 30 days and possibly why.
                    const last30Heading = AdminSubsectionHeader(
                      title: 'Last 30 Days',
                      subtitle: 'Against the 30 days before',
                    );
                    final last30 = _analysis(
                      c,
                      MarketDiagnosticsService.diagnose(
                        commodity: commodity,
                        historical: records,
                        completedOrders: completedOrders,
                        products: products,
                      ),
                      historicalMissing: historical.hasError,
                      liveMissing: !data.hasLoadedOnce,
                    );
                    // Two columns: the price chart, and beside it the last
                    // 30 days. On a narrow screen, one under the other.
                    return LayoutBuilder(
                      builder: (context, box) {
                        final twoColumns = box.maxWidth >= _twoColumnWidth;
                        return AdminPriceTrendSection(
                          commodity: commodity,
                          products: products,
                          completedOrders: completedOrders,
                          historical: records,
                          arrange: (heading, priceTrend) => twoColumns
                              ? _twoColumns(
                                  c,
                                  [heading, last30Heading],
                                  [priceTrend, last30],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    heading,
                                    const SizedBox(
                                      height: AdminSubsectionHeader.gapBelow,
                                    ),
                                    priceTrend,
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: _gutter / 2,
                                      ),
                                      child: Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: c.border,
                                      ),
                                    ),
                                    last30Heading,
                                    const SizedBox(
                                      height: AdminSubsectionHeader.gapBelow,
                                    ),
                                    last30,
                                  ],
                                ),
                        );
                      },
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  // The two parts side by side: their headings on one row, as tall as the
  // taller, so the chart and the tiles under them start on one line; a
  // thin line between them, top to bottom. A table rather than rows, as
  // its middle cells stretch to the row's height without measuring the
  // chart ahead of time.
  Widget _twoColumns(
    AdminPalette c,
    List<Widget> headings,
    List<Widget> contents,
  ) {
    TableCell line() => TableCell(
      verticalAlignment: TableCellVerticalAlignment.fill,
      child: Center(child: Container(width: 1, color: c.border)),
    );
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FixedColumnWidth(_gutter),
        2: FlexColumnWidth(2),
      },
      children: [
        TableRow(
          children: [
            for (final (i, heading) in headings.indexed) ...[
              if (i > 0) line(),
              Padding(
                padding: const EdgeInsets.only(
                  bottom: AdminSubsectionHeader.gapBelow,
                ),
                child: heading,
              ),
            ],
          ],
        ),
        TableRow(
          children: [
            for (final (i, content) in contents.indexed) ...[
              if (i > 0) line(),
              content,
            ],
          ],
        ),
      ],
    );
  }

  Widget _analysis(
    AdminPalette c,
    MarketDiagnosis d, {
    required bool historicalMissing,
    required bool liveMissing,
  }) {
    final notices = [
      if (historicalMissing)
        'Imported historical data could not be loaded, so it is not '
            'included here.',
      if (liveMissing)
        'Orders and listings could not be loaded, so they are not included '
            'here.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final notice in notices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: c.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    notice,
                    style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        if (!d.hasData)
          const AdminEmptyState(
            icon: Icons.insights_outlined,
            title: 'No data for this commodity yet',
            subtitle:
                'It has no listing, completed order or imported record to '
                'analyze.',
          )
        else ...[
          // The three changes at a glance — each tile's figures behind it
          // on hover — and their possible factors; no long detail lines.
          _tiles(c, d),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, thickness: 1, color: c.border),
          ),
          _detail(
            c,
            'Possible Factors',
            d.factors.isEmpty
                ? 'The data on record points to no specific factor behind '
                      'these changes.'
                : d.factors.map((f) => '• $f').join('\n'),
          ),
        ],
      ],
    );
  }

  // The three changes at a glance. For price, a rise is the caution colour.
  Widget _tiles(AdminPalette c, MarketDiagnosis d) {
    String word(ChangeDirection direction, String up, String down) =>
        switch (direction) {
          ChangeDirection.up => up,
          ChangeDirection.down => down,
          ChangeDirection.steady => 'Steady',
          ChangeDirection.unknown => 'Nothing to compare yet',
        };
    Color tone(ChangeDirection direction, {bool upIsGood = true}) =>
        switch (direction) {
          ChangeDirection.up => upIsGood ? c.green : c.amber,
          ChangeDirection.down => upIsGood ? c.red : c.green,
          _ => c.textSecondary,
        };
    final tiles = [
      (
        label: 'Demand',
        value: word(d.demand, 'Increased', 'Decreased'),
        color: tone(d.demand),
        detail: [
          d.demandSummary,
          if (d.seasonalPattern.isNotEmpty) d.seasonalPattern,
        ].join('\n\n'),
      ),
      (
        label: 'Local Supply',
        value: word(d.supply, 'Increased', 'Decreased'),
        color: tone(d.supply),
        detail: d.supplySummary,
      ),
      (
        label: 'Market Price',
        value: word(d.price, 'Increased', 'Decreased'),
        color: tone(d.price, upIsGood: false),
        detail: d.priceSummary,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 3 : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              // The figures behind the word, on hover.
              Tooltip(
                message: tile.detail,
                waitDuration: const Duration(milliseconds: 300),
                child: Container(
                  width: width,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  // Neutral; the word's own colour says the change.
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(AdminRadii.card),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tile.label,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tile.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tile.color,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // A labelled block of text under the tiles, its label over it, both on
  // the tiles' left edge.
  Widget _detail(AdminPalette c, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }
}
