import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import '../services/market_demand_service.dart';
import '../services/market_price_helpers.dart';
import 'agri_dialog.dart';
import 'demand_badge.dart';
import 'market_card_shell.dart';
import 'month_year_picker.dart';
import 'retry_message.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

/// The Farmer Dashboard's marketplace-wide analytics: Best-Selling Products
/// and, below it, Top Buyer Locations. Both open on [month] (the current
/// month, or the one picked on Sales Performance), and the Farmer can move
/// them to another month with the selector on either card. A month with no
/// completed orders says so: earlier figures are never shown under its
/// label, and the card fills in live as soon as an order completes. See
/// [MarketDemandService] for what is counted and how demand level and trend
/// are decided.
///
/// On the dashboard each card lists its first few rows and "View all";
/// that opens a screen with just that card ([only]) listing every row
/// ([showAll]).
class MarketDemandCards extends StatefulWidget {
  final DateTime month;

  /// On the two cards, for the Market tab's first-time hints.
  final Key? bestSellersKey;
  final Key? locationsKey;

  /// Just one of the two cards; both when null.
  final MarketDemandList? only;

  /// Every row, on a card's own full-list screen.
  final bool showAll;
  final bool embedded;

  /// Each list's month, when the screen holds them (the Market tab shows
  /// the month at the top of AgriTrade+ Insights); [onMonthChanged] then
  /// moves one, and [monthTags] false leaves the cards without their own.
  final Map<MarketDemandList, DateTime>? months;
  final void Function(MarketDemandList list, DateTime month)? onMonthChanged;
  final bool monthTags;

  /// The `market_sales` records, without Firestore.
  @visibleForTesting
  final Stream<List<Map<String, dynamic>>>? salesStream;

  /// Today, for tests.
  @visibleForTesting
  final DateTime? now;

  const MarketDemandCards({
    super.key,
    required this.month,
    this.bestSellersKey,
    this.locationsKey,
    this.only,
    this.showAll = false,
    this.embedded = false,
    this.months,
    this.onMonthChanged,
    this.monthTags = true,
    this.salesStream,
    this.now,
  });

  @override
  State<MarketDemandCards> createState() => _MarketDemandCardsState();
}

enum MarketDemandList { bestSellers, locations }

/// The calendar of months for a demand list: from the first month with a
/// completed sale on record ([months], newest first) to this month.
Future<DateTime?> pickDemandMonth(
  BuildContext context, {
  required DateTime selected,
  required List<DateTime> months,
}) {
  final firstMonth = months.last;
  return showMonthYearPicker(
    context,
    selectedMonth: selected,
    firstMonth: firstMonth,
    currentMonth: months.first,
    note: tl(
      'Available from {0}, based on the completed orders on record. Future months cannot be selected.',
      [DateFormat('MMMM yyyy').format(firstMonth)],
    ),
  );
}

class _MarketDemandCardsState extends State<MarketDemandCards> {
  // Created once — not on every dashboard rebuild.
  late Stream<List<Map<String, dynamic>>> _sales = _salesStream();

  // The month each card shows, chosen on that card alone: picking a month
  // on Best-Selling Products leaves Top Buyer Locations where it was. Both
  // follow [MarketDemandCards.month] when that changes.
  late final Map<MarketDemandList, DateTime> _months = {
    for (final list in MarketDemandList.values) list: _monthOf(widget.month),
  };

  static DateTime _monthOf(DateTime date) => DateTime(date.year, date.month);

  Stream<List<Map<String, dynamic>>> _salesStream() =>
      widget.salesStream ??
      FirebaseFirestore.instance
          .collection('market_sales')
          .snapshots()
          .map((snapshot) => [for (final doc in snapshot.docs) doc.data()]);

  @override
  void didUpdateWidget(MarketDemandCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_monthOf(oldWidget.month) != _monthOf(widget.month)) {
      for (final list in MarketDemandList.values) {
        _months[list] = _monthOf(widget.month);
      }
    }
  }

  DateTime _monthFor(MarketDemandList list) =>
      widget.months?[list] ?? _months[list]!;

  void _setMonth(MarketDemandList list, DateTime month) {
    final changed = widget.onMonthChanged;
    if (changed != null) {
      changed(list, month);
    } else {
      setState(() => _months[list] = month);
    }
  }

  bool _shows(MarketDemandList list) =>
      widget.only == null || widget.only == list;

  void _openAll(MarketDemandList list, String title) => openMarketCardScreen(
    context,
    title: title,
    child: MarketDemandCards(
      month: _monthFor(list),
      only: list,
      showAll: true,
      salesStream: widget.salesStream,
      now: widget.now,
    ),
  );

  // The month on a card's corner. It opens the same calendar of months as
  // Sales Performance, from the first sale on record to this month.
  Future<void> _pickMonth(MarketDemandList list, List<DateTime> months) async {
    final picked = await pickDemandMonth(
      context,
      selected: _monthFor(list),
      months: months,
    );
    if (picked != null && mounted) _setMonth(list, picked);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _sales,
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) {
          return RetryMessage(
            message: tl(
              'Could not load marketplace sales. Check your connection and retry.',
            ),
            onRetry: () => setState(() => _sales = _salesStream()),
          );
        }
        final loading = !snapshot.hasData;
        final sales = snapshot.data ?? const <Map<String, dynamic>>[];

        // Also rebuilt when the Admin changes the commodity list, since
        // names, categories and units come from it.
        return ListenableBuilder(
          listenable: CommodityRegistry.instance,
          builder: (context, _) {
            final bestSellersMonth = _monthFor(MarketDemandList.bestSellers);
            final locationsMonth = _monthFor(MarketDemandList.locations);
            final bestSellers = MarketDemandService.bestSellers(
              sales: sales,
              month: bestSellersMonth,
              now: widget.now,
            );
            final locations = MarketDemandService.topBuyerLocations(
              sales: sales,
              month: locationsMonth,
            );
            // Each card's month pill, and its "View previous month" when it
            // is empty, move that card only.
            Widget? monthTag(MarketDemandList list) {
              if (!widget.monthTags) return null;
              final month = _monthFor(list);
              return MonthPickerPill(
                month: month,
                onTap: () => _pickMonth(
                  list,
                  MarketDemandService.monthsOnRecord(
                    sales: sales,
                    month: month,
                    now: widget.now,
                  ),
                ),
              );
            }

            // Offered only when there is an earlier month to go to.
            VoidCallback? onPreviousMonth(MarketDemandList list) {
              final month = _monthFor(list);
              final previous = DateTime(month.year, month.month - 1);
              final months = MarketDemandService.monthsOnRecord(
                sales: sales,
                month: month,
                now: widget.now,
              );
              return months.contains(previous)
                  ? () => _setMonth(list, previous)
                  : null;
            }

            String monthLabel(DateTime month) =>
                DateFormat('MMMM y').format(month);
            final bestSellersTitle = tr(context).bestSellingProducts;
            final locationsTitle = tr(context).topBuyerLocations;
            return Column(
              children: [
                if (_shows(MarketDemandList.bestSellers))
                  KeyedSubtree(
                    key: widget.bestSellersKey,
                    child: _card(
                      title: bestSellersTitle,
                      subtitle: tr(context).bestSellersSubtitle(
                        MarketDemandService.bestSellerLimit,
                      ),
                      tag: monthTag(MarketDemandList.bestSellers),
                      loading: loading,
                      emptyIcon: Icons.shopping_basket_outlined,
                      emptyText: tl(
                        'No completed orders in {0} yet. Popular products will appear here as buyers complete orders.',
                        [monthLabel(bestSellersMonth)],
                      ),
                      onPreviousMonth: onPreviousMonth(
                        MarketDemandList.bestSellers,
                      ),
                      rows: [
                        for (var i = 0; i < bestSellers.length; i++)
                          _bestSellerRow(i + 1, bestSellers[i]),
                      ],
                      openAll: () => _openAll(
                        MarketDemandList.bestSellers,
                        bestSellersTitle,
                      ),
                    ),
                  ),
                if (widget.only == null) const SizedBox(height: 16),
                if (_shows(MarketDemandList.locations))
                  KeyedSubtree(
                    key: widget.locationsKey,
                    child: _card(
                      title: locationsTitle,
                      tag: monthTag(MarketDemandList.locations),
                      loading: loading,
                      emptyIcon: Icons.map_outlined,
                      emptyText: tl(
                        'No buyer locations on record for completed orders in {0} yet.',
                        [monthLabel(locationsMonth)],
                      ),
                      onPreviousMonth: onPreviousMonth(
                        MarketDemandList.locations,
                      ),
                      rows: [
                        for (var i = 0; i < locations.length; i++)
                          _locationRow(
                            i + 1,
                            locations[i],
                            onTap: () => _showLocationDetails(
                              locations[i],
                              sales,
                              locationsMonth,
                            ),
                          ),
                      ],
                      openAll: () =>
                          _openAll(MarketDemandList.locations, locationsTitle),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _card({
    required String? title,
    String? subtitle,
    required Widget? tag,
    required bool loading,
    required IconData emptyIcon,
    required String emptyText,
    required VoidCallback? onPreviousMonth,
    required List<Widget> rows,
    required VoidCallback openAll,
  }) {
    return MarketCardShell(
      title: widget.embedded ? null : title,
      subtitle: subtitle,
      tagWidget: tag,
      embedded: widget.embedded,
      child: loading
          ? const MarketCardLoading()
          : rows.isEmpty
          ? MarketCardEmpty(
              icon: emptyIcon,
              message: emptyText,
              actionLabel: onPreviousMonth == null
                  ? null
                  : tr(context).viewPreviousMonth,
              onAction: onPreviousMonth,
            )
          : marketCardRows(
              rows: rows,
              showAll: widget.showAll,
              openAll: openAll,
            ),
    );
  }

  // One ranked entry: a single plain line (no panel), so a long list
  // stays easy to scan.
  Widget _line(int rank, String name, List<Widget> trailing) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        _rank(rank),
        const SizedBox(width: 8),
        Expanded(child: _name(name)),
        for (final widget in trailing) ...[const SizedBox(width: 8), widget],
      ],
    ),
  );

  // The rank as a plain number; the leader in the brand's dark green.
  Widget _rank(int rank) => SizedBox(
    width: 22,
    child: Text(
      '$rank',
      style: GoogleFonts.montserrat(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: rank == 1 ? AppColors.brand : AppColors.grey(500),
      ),
    ),
  );

  Widget _pill(String label, Color color, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );

  // Short, so the line fits: High / Moderate / Low. The same words and
  // colours as the Buyer's product cards (see DemandBadge).
  Widget _demandTag(DemandLevel level) {
    final (label, color) = demandLevelStyle(level);
    return _pill(label, color);
  }

  Widget _name(String text) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: GoogleFonts.montserrat(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    ),
  );

  // Rank, product and the quantity sold — on one line. No trend icon (the
  // user's choice, 2026-11-07): its meaning showed only on a long press.
  Widget _bestSellerRow(int rank, BestSeller item) {
    return _line(rank, item.commodity, [
      _pill(formatStock(item.quantity, item.unit), AppColors.brand),
    ]);
  }

  // Rank, area, demand and its share of the month's orders — on one
  // line (the shares of all the month's areas add up to 100%). Tapping it shows what buyers there ordered (see
  // [_showLocationDetails]).
  Widget _locationRow(
    int rank,
    BuyerLocation location, {
    required VoidCallback onTap,
  }) {
    final share = location.sharePercent;
    return Semantics(
      button: true,
      hint: tl('Show what buyers here ordered'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: _line(rank, location.area, [
          _demandTag(location.demand),
          SizedBox(
            width: 38,
            child: Text(
              '$share%',
              textAlign: TextAlign.right,
              style: GoogleFonts.montserrat(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.brand,
              ),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppColors.grey(500),
          ),
        ]),
      ),
    );
  }

  // The products buyers in one area ordered in the card's month, most
  // completed orders first.
  void _showLocationDetails(
    BuyerLocation location,
    List<Map<String, dynamic>> sales,
    DateTime month,
  ) {
    final products = MarketDemandService.productsBoughtIn(
      sales: sales,
      month: month,
      area: location.area,
    );
    final total = MarketDemandService.ordersInArea(
      sales: sales,
      month: month,
      area: location.area,
    );
    showAgriSheet<void>(
      context: context,
      title: location.area,
      builder: (context) => LocationOrdersSheet(
        location: location,
        products: products,
        total: total,
        month: month,
      ),
    );
  }
}

/// What buyers in one area ordered in a month (Top Buyer Locations → an
/// area): a summary on top — the area's demand level, its completed orders,
/// and what its percentage on the card means (its share of all buyer
/// orders that month) — then each product with its orders and a bar showing
/// its share of the area's orders.
class LocationOrdersSheet extends StatelessWidget {
  final BuyerLocation location;
  final List<({String commodity, int orders})> products;

  /// Every completed order from the area that month.
  final int total;
  final DateTime month;

  const LocationOrdersSheet({
    super.key,
    required this.location,
    required this.products,
    required this.total,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    final share = location.sharePercent;
    final (level, levelColor) = demandLevelStyle(location.demand);
    TextStyle text(double size, FontWeight weight, Color color) =>
        GoogleFonts.montserrat(
          fontSize: size,
          fontWeight: weight,
          color: color,
        );

    Widget stat(String value, String label, {Color? color}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          border: Border.all(color: AppColors.grey(200)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text(16, FontWeight.w700, color ?? AppColors.brand),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: text(10.5, FontWeight.w500, AppColors.grey(600)),
            ),
          ],
        ),
      ),
    );

    // Lined up with the sheet's title (18 in), and scrolls on a short
    // screen instead of running off the bottom.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tl('Completed orders from buyers here in {0}', [
              DateFormat('MMMM y').format(month),
            ]),
            style: text(12.5, FontWeight.w400, AppColors.grey(600)),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                stat(level, tl('Demand'), color: levelColor),
                const SizedBox(width: 8),
                stat('$total', total == 1 ? tl('order') : tl('orders')),
                const SizedBox(width: 8),
                stat('$share%', tl('of all buyer orders this month')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tl('Most ordered here'),
            style: text(13.5, FontWeight.w700, AppColors.text),
          ),
          const SizedBox(height: 4),
          if (products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                tl('No completed orders here this month.'),
                style: text(12.5, FontWeight.w400, AppColors.grey(600)),
              ),
            )
          else
            for (var i = 0; i < products.length; i++)
              _productRow(i + 1, products[i], text),
        ],
      ),
    );
  }

  Widget _productRow(
    int rank,
    ({String commodity, int orders}) product,
    TextStyle Function(double, FontWeight, Color) text,
  ) {
    final fraction = total == 0 ? 0.0 : product.orders / total;
    final percent = (fraction * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rank == 1 ? AppColors.brandFill : AppColors.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: text(
                12,
                FontWeight.w700,
                rank == 1 ? Colors.white : AppColors.grey(700),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.commodity,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text(13.5, FontWeight.w600, AppColors.text),
                      ),
                    ),
                    Text(
                      product.orders == 1
                          ? tl('1 order')
                          : tl('{0} orders', [product.orders]),
                      style: text(12, FontWeight.w600, AppColors.grey(700)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 6,
                          backgroundColor: AppColors.grey(200),
                          valueColor: AlwaysStoppedAnimation(
                            AppColors.brandFill,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '$percent%',
                        textAlign: TextAlign.right,
                        style: text(12, FontWeight.w700, AppColors.brand),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
