import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/firebase_refs.dart';
import '../services/order_date_filter.dart';
import '../services/order_format.dart';
import '../widgets/agri_dialog.dart' show showAgriPopupMenu, AgriMenuItem;
import '../widgets/coach_mark.dart';
import '../services/order_seen_service.dart';
import '../services/order_service.dart';
import '../widgets/order_card.dart';
import '../widgets/fitted_menu_width.dart';
import '../widgets/order_status_pager.dart';
import '../widgets/explore_hero.dart';
import '../widgets/page_header.dart';
import 'inventory_screen.dart';
import 'order_actions.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../l10n/app_language.dart';

/// The Orders screen body for both the Farmer and the Buyer: same header,
/// tabs, swipe, badges, cards, loading and empty states. [role] only
/// changes the wording, whose name a card shows, and which actions exist.
///
/// Body-only — it renders inside the Farmer/Buyer home Scaffold, which
/// already provides the app bar and bottom navigation.
class OrdersView extends StatefulWidget {
  final OrderRole role;

  /// Buyer only: jumps to the marketplace from an empty state.
  final VoidCallback? onBrowseMarketplace;

  /// A status tab to open on request (see OrderStatusPager.showStatus).
  final ValueListenable<String?>? showStatus;

  /// Whether its tab is the one on screen: its first-time tour waits for
  /// that, since the home screens build every tab up front.
  final bool active;

  const OrdersView({
    super.key,
    required this.role,
    this.onBrowseMarketplace,
    this.showStatus,
    this.active = true,
  });

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> {
  // What the first-time tour points at.
  final _periodKey = GlobalKey();
  final _inventoryKey = GlobalKey();
  bool _tourAsked = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _askForTour();
  }

  @override
  void didUpdateWidget(OrdersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _askForTour();
  }

  // The first time the tab is open: where the farmer's stock is, and how to
  // find older orders. The status tabs need no explaining.
  void _askForTour() {
    if (_tourAsked) return;
    _tourAsked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showCoachMarksOnce(
        context: context,
        prefsKey: '${TutorialTips.tourKeyPrefix}orders_${widget.role.name}',
        steps: [
          if (_isFarmer)
            CoachMarkStep(
              targetKey: _inventoryKey,
              title: tl('Your stock'),
              message: tl(
                'See how much of each product is left, and update it.',
              ),
            ),
          CoachMarkStep(
            targetKey: _periodKey,
            title: tl('Find older orders'),
            message: tl(
              "Show only today's orders, the last 7 or 30 days, a few months, or dates you pick.",
            ),
          ),
        ],
      );
    });
  }

  // The four workflow statuses, plus declined orders so they stay findable.
  static const _tabs = [...kOrderStatusTabs, kRejectedTab];

  final OrderService _orderService = OrderService();
  late final OrderSeenStore _seenStore = OrderSeenStore(
    uid: FirebaseRefs.auth.currentUser?.uid ?? 'unknown',
    role: widget.role.name,
  );

  OrderRole get _role => widget.role;
  bool get _isFarmer => _role == OrderRole.farmer;

  // The period shown, by the day each order was placed (every tab).
  OrderDateFilter _dateFilter = OrderDateFilter.all;

  DateTimeRange? get _range => _dateFilter.rangeOn(DateTime.now());

  // [all], kept to the chosen period.
  List<OrderDoc> _inPeriod(List<OrderDoc> all) {
    final range = _range;
    if (range == null) return all;
    final now = DateTime.now();
    return [
      for (final doc in all)
        if (placedIn(OrderInfo.fromDoc(doc).createdAt, range, now: now)) doc,
    ];
  }

  String get _periodLabel => tl(_dateFilter.label);

  // The period picker: a menu that drops down from the period button
  // itself (not a sheet from the bottom), in the Messages menu's compact
  // style (dense: white, 16 icons, 12 labels, lines between, a pointer).
  Future<void> _pickPeriod(BuildContext anchorContext) async {
    final chosen = await showAgriPopupMenu<OrderDateFilter>(
      anchorContext: anchorContext,
      dense: true,
      // As wide as the longest period: the text plus its icon (16), the
      // gap (10) and the row's sides (12 + 12), with a little room.
      width: fittedMenuWidth(
        context,
        [for (final option in OrderDateFilter.values) tl(option.label)],
        style: GoogleFonts.montserrat(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        extra: 58,
      ),
      items: [
        for (final option in OrderDateFilter.values)
          AgriMenuItem(
            value: option,
            selected: option == _dateFilter,
            icon: option == _dateFilter
                ? Icons.check_rounded
                : Icons.calendar_today_outlined,
            label: tl(option.label),
          ),
      ],
    );
    if (chosen == null || !mounted) return;
    setState(() => _dateFilter = chosen);
  }

  // The period shown: a small pale green pill with a calendar and a
  // chevron (the user's design, 2026-11-08; no ×); All time is picked from
  // its menu.
  // The Farmer's period, under the status tabs on the right (the title
  // row has Inventory). The Buyer's is on the title row, opposite Orders.
  Widget _periodBar() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [_periodControls()],
    ),
  );

  Widget _periodControls() {
    final foreground = AppColors.brand;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Builder(
          builder: (anchorContext) => Material(
            key: _periodKey,
            color: AppColors.isDark ? AppColors.tint : const Color(0xFFEAF2E4),
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('ordersPeriod'),
              onTap: () => _pickPeriod(anchorContext),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 9, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_month_outlined,
                      size: 16,
                      color: foreground,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _periodLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: foreground,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // The list is a live Firestore stream and is already current; this only
  // gives the pull gesture its feedback.
  Future<void> _refresh() => Future.delayed(const Duration(milliseconds: 700));

  String _emptySubtitle(OrderStatusTab tab) =>
      _dateFilter != OrderDateFilter.all
      ? tl('No orders here from {0}. Try a longer period.', [
          _periodLabel.toLowerCase(),
        ])
      : switch (tab.value) {
          'pending' =>
            _isFarmer
                ? 'New buyer orders will appear here.'
                : 'Orders waiting for farmer confirmation will appear here.',
          'confirmed' =>
            _isFarmer
                ? 'Accepted buyer orders will appear here.'
                : 'Orders confirmed by farmers will appear here.',
          'shipped' =>
            _isFarmer
                ? 'Orders marked as shipped or in fulfillment will appear here.'
                : 'Orders being fulfilled or delivered will appear here.',
          'completed' =>
            _isFarmer
                ? 'Completed transactions will appear here.'
                : 'Your completed purchases will appear here.',
          _ =>
            _isFarmer
                ? 'Orders you decline will appear here.'
                : 'Orders declined by farmers will appear here.',
        };

  // A farmer's pending orders: due soonest first ("needed by"). Everything
  // else: latest activity first.
  List<Widget> _cardsFor(
    OrderStatusTab tab,
    List<OrderDoc> all,
    bool Function(OrderDoc) isNew,
  ) {
    final docs = _inPeriod(
      all,
    ).where((d) => orderStatusOf(d) == tab.value).toList();
    final info = {for (final d in docs) d.id: OrderInfo.fromDoc(d)};
    docs.sort((a, b) {
      final ao = info[a.id]!;
      final bo = info[b.id]!;
      if (_isFarmer && tab.value == 'pending') {
        final aNeed = ao.neededBy;
        final bNeed = bo.neededBy;
        if (aNeed != null || bNeed != null) {
          if (aNeed == null) return 1;
          if (bNeed == null) return -1;
          final due = aNeed.compareTo(bNeed);
          if (due != 0) return due;
        }
      }
      final aAt = (ao.statusChangedAt ?? ao.createdAt)?.millisecondsSinceEpoch;
      final bAt = (bo.statusChangedAt ?? bo.createdAt)?.millisecondsSinceEpoch;
      return (bAt ?? 0).compareTo(aAt ?? 0);
    });

    return [
      for (final doc in docs)
        Builder(
          key: ValueKey(doc.id),
          builder: (context) {
            final order = info[doc.id]!;
            return OrderCard(
              order: order,
              role: _role,
              isNew: isNew(doc),
              // Messaging and the order's actions are in its details.
              onDetails: () => OrderActions.openDetails(context, order, _role),
            );
          },
        ),
    ];
  }

  // Buyer, Completed tab: a nudge to review finished purchases.
  List<Widget> _header(OrderStatusTab tab, List<OrderDoc> all) {
    if (_isFarmer || tab.value != 'completed') return const [];
    final unreviewed = _inPeriod(all).where((doc) {
      final data = doc.data();
      return orderStatusOf(doc) == 'completed' && data['reviewedAt'] == null;
    }).length;
    if (unreviewed == 0) return const [];
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.tint,
          border: AppColors.cardBorder,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          tl(
            'Review your completed orders to earn the Trusted Buyer badge. {0} order{1} still need{2} a review.',
            [
              unreviewed,
              unreviewed == 1 ? '' : 's',
              unreviewed == 1 ? 's' : '',
            ],
          ),
          style: GoogleFonts.montserrat(
            color: AppColors.brand,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final browse = widget.onBrowseMarketplace;
    // On Explore's cream, under the dark green band, "Orders" as big as
    // Explore's and Messages' titles (the user's design, 2026-11-08).
    return ColoredBox(
      color: exploreBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(title: tr(context).navOrders, includeTitle: false),
          Padding(
            padding: const EdgeInsets.fromLTRB(21, 8, 14, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr(context).navOrders,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: AppTheme.mainTitleSize,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.heading,
                    ),
                  ),
                ),
                // Farmers only: a quiet text link to their own stock.
                _isFarmer
                    ? Padding(
                        padding: const EdgeInsets.only(right: 0),
                        child: TextButton(
                          key: _inventoryKey,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const InventoryScreen(),
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            minimumSize: const Size(48, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.standard,
                            textStyle: GoogleFonts.montserrat(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text('${tr(context).inventory} →'),
                        ),
                      )
                    // The Buyer's period, opposite the title.
                    : _periodControls(),
              ],
            ),
          ),
          Expanded(
            child: OrderStatusPager(
              streamFactory: _isFarmer
                  ? _orderService.farmerOrdersStream
                  : _orderService.buyerOrdersStream,
              tabs: _tabs,
              showStatus: widget.showStatus,
              belowTabs: _isFarmer ? _periodBar() : null,
              itemsBuilder: _cardsFor,
              headerBuilder: _header,
              onRefresh: _refresh,
              emptySubtitle: _emptySubtitle,
              emptyAction: browse == null
                  ? null
                  : TextButton.icon(
                      onPressed: browse,
                      icon: const Icon(Icons.storefront_outlined, size: 17),
                      label: Text(tl('Browse Marketplace')),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.brand,
                        textStyle: GoogleFonts.montserrat(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
              errorMessage: tl(
                'Could not load your orders. Check your connection and try again.',
              ),
              tutorialPrefsKey: ordersSwipeTutorialKey(),
              activityOf: (doc) =>
                  OrderInfo.fromDoc(doc).unseenActivityMs(_role),
              seenStore: _seenStore,
            ),
          ),
        ],
      ),
    );
  }
}
