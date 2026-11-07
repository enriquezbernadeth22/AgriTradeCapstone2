import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/farmer_revenue_service.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';
import '../widgets/docked_nav_bar.dart';
import '../widgets/market_average_card.dart';
import '../widgets/market_card_shell.dart';
import '../services/market_demand_service.dart';
import '../widgets/collapsible_section.dart';
import '../widgets/market_demand_cards.dart';
import '../widgets/market_tab_guide.dart';
import '../widgets/month_year_picker.dart';
import '../widgets/page_header.dart';
import '../widgets/retry_message.dart';
import '../widgets/agri_refresh_indicator.dart';
import '../widgets/notification_bell.dart';
import 'add_product_screen.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../l10n/app_language.dart';

// Body-only widget — renders inside FarmerHomeScreen's Scaffold.
//
// onNavigateToTab lets this tab jump to another bottom-nav tab in the
// parent Scaffold (tapping "Welcome back" or the Total Products card goes
// to Profile; the Total Orders card goes to Orders). Wire it up in
// FarmerHomeScreen:
//   MarketTab(onNavigateToTab: (i) => setState(() => _selectedIndex = i))
// Index assumption, matching the rest of this build: 2=Orders, 3=Profile —
// adjust _ordersTabIndex/_profileTabIndex below if your order differs.
/// The first name of [fullName] ("Daniella Claveria" → "Daniella"), for
/// the Market welcome card; "Farmer" when there is no name.
String firstNameOf(String fullName) {
  final words = fullName.trim().split(RegExp(r'\s+'));
  return words.first.isEmpty ? 'Farmer' : words.first;
}

/// The Sales Performance chart's y-axis: a round [step] — 1, 2, 2.5 or 5
/// times a power of ten — giving about three steps up to the month's best
/// day, and a [max] that is a whole number of steps with a little room
/// above that day.
({double max, double step}) salesChartScale(double maxRevenue) {
  if (maxRevenue <= 0) return (max: 100, step: 25);
  final rough = maxRevenue / 3;
  final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor());
  final step = [
    1,
    2,
    2.5,
    5,
    10,
  ].map((m) => m * magnitude).firstWhere((s) => s >= rough).toDouble();
  return (max: (maxRevenue * 1.05 / step).ceil() * step, step: step);
}

/// Market's "Orders Today": the farmer's orders confirmed today that are
/// still Confirmed (not yet shipped) — the ones waiting on Orders'
/// Confirmed tab. Confirmed when stockDeductedAt was stamped, or — for an
/// older order without it — when it was last updated.
int confirmedTodayCount(
  Iterable<Map<String, dynamic>> orders, {
  required DateTime now,
}) {
  DateTime? at(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : null;
  return orders.where((order) {
    if ((order['status'] ?? '').toString().toLowerCase() != 'confirmed') {
      return false;
    }
    final when =
        at(order['confirmedAt']) ??
        at(order['stockDeductedAt']) ??
        at(order['updatedAt']);
    return when != null &&
        when.year == now.year &&
        when.month == now.month &&
        when.day == now.day;
  }).length;
}

/// What the Market tab's AgriTrade+ Insights can show: [label] is the
/// card's full name, [segment] the short name on the picker. In the
/// picker's order, Market Average in the middle (the user's choice).
enum MarketInsight {
  bestSellers('Best-Selling Products', 'Best Sellers'),
  marketAverage('Current Market Average', 'Market Average'),
  buyerLocations('Top Buyer Locations', 'Buyer Areas');

  final String label;
  final String segment;
  const MarketInsight(this.label, this.segment);
}

/// The Market insight picker: the three side by side in one rounded track,
/// the chosen one filled dark green (the user's design, 2026-11-07, in place
/// of a dropdown). Each is as wide as its name, and all three are always
/// the same size: 12 when they fit, a little smaller together on a narrow
/// phone. The font is the app's own Montserrat, like the rest of the tab.
class MarketInsightPicker extends StatelessWidget {
  final MarketInsight value;
  final ValueChanged<MarketInsight> onChanged;

  const MarketInsightPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const double height = 42;
  static const double fontSize = 12;
  static const double _minFontSize = 10;
  // Inside the track (4 each side, and its 1px border) and inside each part.
  static const double _trackInset = 10;
  static const double _segmentPadding = 14;

  static TextStyle textStyle({
    required bool selected,
    double size = fontSize,
  }) => GoogleFonts.montserrat(
    fontSize: size,
    fontWeight: FontWeight.w600,
    // Measured and drawn the same: no spacing added by the theme.
    letterSpacing: 0,
    color: selected ? Colors.white : AppColors.text,
  );

  static double _widthOf(BuildContext context, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle(selected: false)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      for (final insight in MarketInsight.values) tl(insight.segment),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = [for (final label in labels) _widthOf(context, label)];
        final text = widths.fold<double>(0, (total, w) => total + w);
        final room =
            constraints.maxWidth -
            _trackInset -
            _segmentPadding * labels.length;
        // One size for all three.
        final size = text <= room
            ? fontSize
            : (fontSize * room / text).clamp(_minFontSize, fontSize);
        return Container(
          key: const Key('marketInsightPicker'),
          height: height,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.adapt(const Color(0xFFF3F5F2)),
            borderRadius: BorderRadius.circular(AppTheme.pillRadius),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  // Its name at the shared size, plus its padding.
                  flex: ((widths[i] * size / fontSize + _segmentPadding) * 10)
                      .round()
                      .clamp(1, 1 << 20),
                  child: _Segment(
                    label: labels[i],
                    size: size,
                    selected: MarketInsight.values[i] == value,
                    onTap: () {
                      final insight = MarketInsight.values[i];
                      if (insight != value) onChanged(insight);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: selected ? AppColors.brandFill : Colors.transparent,
            ),
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: MarketInsightPicker.textStyle(
                selected: selected,
                size: size,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MarketTab extends StatefulWidget {
  final ValueChanged<int>? onNavigateToTab;

  /// The notification bell in this tab's header.
  final VoidCallback? onNotificationsPressed;

  /// Opens Orders at a status tab (Orders Today opens Confirmed).
  final ValueChanged<String>? onOpenOrders;

  const MarketTab({
    super.key,
    this.onNavigateToTab,
    this.onNotificationsPressed,
    this.onOpenOrders,
  });

  @override
  State<MarketTab> createState() => _MarketTabState();
}

class _MarketTabState extends State<MarketTab> {
  static const int _profileTabIndex = 3;
  static const int _ordersTabIndex = 2;
  DateTime? _selectedSalesMonth;

  // The month every dashboard analytics card shows: the one picked on
  // Sales Performance, or the current month until one is picked.
  DateTime get _analyticsMonth {
    final month = _selectedSalesMonth ?? DateTime.now();
    return DateTime(month.year, month.month);
  }

  // The live data this tab shows, each opened once (and again only on
  // Retry) — never on every rebuild. One stream per card: a stream that
  // another card is already listening to does not repeat its latest data
  // to a card that starts listening later, which would then wait forever.
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _salesProfile =
      _profileStream();
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _welcomeProfile =
      _profileStream();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _salesOrders = OrderService()
      .farmerOrdersStream();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _statOrders = OrderService()
      .farmerOrdersStream();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _products = ProductService()
      .myProductsStream();

  Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream() =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid ?? '_')
          .snapshots();

  void _reconnect() => setState(() {
    _salesProfile = _profileStream();
    _welcomeProfile = _profileStream();
    _salesOrders = OrderService().farmerOrdersStream();
    _statOrders = OrderService().farmerOrdersStream();
    _products = ProductService().myProductsStream();
  });

  int _lastProductCount = 0;
  // Until the product list has loaded, a count of 0 means "unknown", not
  // "no products".
  bool _productsLoaded = false;
  // A first-time farmer is told which cards are their own sales and which
  // are the whole marketplace — a small hint at each card as they scroll
  // to it, one at a time (MarketTabHints), instead of a popup up front.
  final _hints = MarketTabHints();

  Widget _salesPerformanceLineCard(int productCount) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return _salesCardMessage(tl('Log in to view your sales performance.'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _salesProfile,
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting &&
            !userSnapshot.hasData) {
          return _salesLoadingCard();
        }
        if (userSnapshot.hasError) {
          return RetryMessage(
            message: tl(
              'Could not load your verification date. Check your connection and retry.',
            ),
            onRetry: _reconnect,
          );
        }

        final user = userSnapshot.data?.data() ?? const <String, dynamic>{};
        if ((user['approvalStatus'] ?? 'approved').toString().toLowerCase() !=
            'approved') {
          return _salesCardMessage(
            tl(
              'Sales performance will be available once your farmer account is verified.',
            ),
          );
        }
        final now = DateTime.now();
        final storedVerifiedAt =
            _parseDateTime(user['verifiedAt']) ??
            _parseDateTime(user['reviewedAt']) ??
            _parseDateTime(user['createdAt']) ??
            now;
        final verifiedAt = storedVerifiedAt.isAfter(now)
            ? now
            : storedVerifiedAt;
        final firstMonth = DateTime(verifiedAt.year, verifiedAt.month);
        final currentMonth = DateTime(now.year, now.month);
        final months = <DateTime>[];
        for (
          var cursor = currentMonth;
          !cursor.isBefore(firstMonth);
          cursor = DateTime(cursor.year, cursor.month - 1)
        ) {
          months.add(cursor);
        }
        final selectedMonth = months.firstWhere(
          (month) =>
              month.year == _selectedSalesMonth?.year &&
              month.month == _selectedSalesMonth?.month,
          orElse: () => months.first,
        );

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _salesOrders,
          builder: (context, ordersSnapshot) {
            if (ordersSnapshot.connectionState == ConnectionState.waiting &&
                !ordersSnapshot.hasData) {
              return _salesLoadingCard();
            }
            if (ordersSnapshot.hasError) {
              return RetryMessage(
                message: tl(
                  'Could not load completed orders. Check your connection and retry.',
                ),
                onRetry: _reconnect,
              );
            }
            final orders =
                (ordersSnapshot.data?.docs ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                    .map((doc) => doc.data())
                    .toList();
            final days = FarmerRevenueService.dailyRevenueForMonth(
              orders: orders,
              month: selectedMonth,
              verifiedAt: verifiedAt,
            );
            final total = FarmerRevenueService.totalRevenueForDays(days);
            final spots = [
              for (var i = 0; i < days.length; i++)
                FlSpot(i.toDouble(), days[i].revenue),
            ];
            final maxRevenue = days.fold<double>(
              0,
              (max, day) => day.revenue > max ? day.revenue : max,
            );
            // A round step (₱50, ₱100, ₱200, ₱250…) and a top that is a
            // whole number of steps, so every axis label sits on a grid
            // line and the top one never lands on top of another.
            final scale = salesChartScale(maxRevenue);
            final chartMax = scale.max;
            final firstEligibleDate = DateTime(
              selectedMonth.year,
              selectedMonth.month,
              selectedMonth.year == verifiedAt.year &&
                      selectedMonth.month == verifiedAt.month
                  ? verifiedAt.day
                  : 1,
            );
            final periodLabel = firstEligibleDate.day == 1
                ? 'From ${MaterialLocalizations.of(context).formatShortDate(firstEligibleDate)}'
                : 'Starts on your verification date · ${MaterialLocalizations.of(context).formatShortDate(firstEligibleDate)}';

            return Container(
              padding: const EdgeInsets.all(18),
              decoration: AppTheme.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: _SalesHeading()),
                      MonthPickerPill(
                        month: selectedMonth,
                        onTap: () async {
                          final picked = await showMonthYearPicker(
                            context,
                            selectedMonth: selectedMonth,
                            firstMonth: firstMonth,
                            currentMonth: currentMonth,
                            note: tl(
                              'Available from {0}, based on your verification date. Future months cannot be selected.',
                              [DateFormat('MMMM yyyy').format(firstMonth)],
                            ),
                          );
                          if (picked != null && mounted) {
                            setState(() => _selectedSalesMonth = picked);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // No completed sales in the selected month: say so, with
                  // the next step, instead of a flat empty chart.
                  if (total <= 0)
                    _salesEmptyState(
                      newFarmer:
                          _productsLoaded &&
                          productCount == 0 &&
                          !orders.any(
                            (order) =>
                                (order['status'] ?? '')
                                    .toString()
                                    .toLowerCase() ==
                                'completed',
                          ),
                    )
                  else ...[
                    Text(
                      _formatCurrency(total),
                      style: GoogleFonts.montserrat(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      periodLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.grey(600),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 175,
                      child: LineChart(
                        LineChartData(
                          minX: 0,
                          maxX: (days.length - 1).clamp(1, 31).toDouble(),
                          minY: 0,
                          maxY: chartMax,
                          gridData: FlGridData(
                            drawVerticalLine: false,
                            horizontalInterval: scale.step,
                            getDrawingHorizontalLine: (_) => FlLine(
                              color: AppColors.adapt(const Color(0xFFE9EEE6)),
                              strokeWidth: 1,
                            ),
                          ),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 44,
                                interval: scale.step,
                                getTitlesWidget: (value, meta) => Text(
                                  '₱${value >= 1000 ? '${(value / 1000).toStringAsFixed(0)}k' : value.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.grey(600),
                                  ),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 24,
                                interval: days.length > 10 ? 5 : 1,
                                getTitlesWidget: (value, meta) {
                                  final index = value.round();
                                  if (index < 0 || index >= days.length) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      '${days[index].date.day}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.grey(600),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          lineTouchData: const LineTouchData(enabled: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: true,
                              // A smooth line that never swings below ₱0
                              // (or past a day's real total) before a
                              // sudden jump in sales.
                              preventCurveOverShooting: true,
                              color: AppColors.brand,
                              barWidth: 3,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: AppColors.brand.withValues(alpha: 0.10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tl('Revenue is based on orders marked completed.'),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.grey(600),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // What Sales Performance shows in place of the chart when the selected
  // month has no completed sales. A farmer with no products and no sales
  // ever is pointed at Add Product; one who already has products (or has
  // sold before) is pointed at their product list instead.
  Widget _salesEmptyState({required bool newFarmer}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.tint,
        border: AppColors.cardBorder,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(
            newFarmer ? Icons.storefront_outlined : Icons.show_chart_rounded,
            size: 30,
            color: AppColors.brand,
          ),
          const SizedBox(height: 8),
          Text(
            newFarmer ? tl('No sales yet') : tl('No completed sales yet'),
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            newFarmer
                ? tl(
                    'Start by listing your first product to begin tracking your sales performance.',
                  )
                : tl(
                    'Your sales performance will appear here once buyers complete their orders.',
                  ),
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: AppColors.grey(600),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (newFarmer)
            ElevatedButton.icon(
              // The same Add Product screen the + button opens.
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddProductScreen()),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(tl('Add Product')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandFill,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                textStyle: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            OutlinedButton(
              // The farmer's product list lives on the Profile tab.
              onPressed: () => widget.onNavigateToTab?.call(_profileTabIndex),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brand,
                side: BorderSide(color: AppColors.brand),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: AppTheme.buttonShape,
                textStyle: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(tl('View My Products')),
            ),
        ],
      ),
    );
  }

  Widget _salesCardMessage(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: AppTheme.card(),
    child: Text(
      tl(message),
      style: TextStyle(color: AppColors.grey(700), fontSize: 12),
    ),
  );

  Widget _salesLoadingCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: AppTheme.card(),
    child: const Row(
      children: [
        Expanded(child: _SalesHeading()),
        AgriLogoLoader(),
      ],
    ),
  );

  DateTime? _parseDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String _formatCurrency(num value) {
    final whole = value.round();
    final s = whole.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final indexFromEnd = s.length - i;
      if (i > 0 && indexFromEnd % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(s[i]);
    }
    return '₱$buffer';
  }

  // Pull to refresh: asks the server for the latest of everything this tab
  // shows. The cards are fed by live listeners, so they take the new data
  // in place — nothing is cleared or swapped for a loading state meanwhile.
  Future<void> _refresh() async {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    const fromServer = GetOptions(source: Source.server);
    try {
      await Future.wait([
        // Long enough for the pull to register as having done something.
        Future<void>.delayed(const Duration(milliseconds: 600)),
        db.collection('market_sales').get(fromServer),
        db.collection('products').get(fromServer),
        if (uid != null) ...[
          db.collection('users').doc(uid).get(fromServer),
          db
              .collection('orders')
              .where('sellerId', isEqualTo: uid)
              .get(fromServer),
        ],
      ]).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Offline or slow: the listeners keep showing what they have.
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _products,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return RetryMessage(
            message: tl(
              'Could not load your products. Check your connection and try again.',
            ),
            onRetry: _reconnect,
          );
        }
        // Active listings only — archived ones are not "listed", the same
        // count Inventory shows as Active Products.
        if (snapshot.hasData) {
          _lastProductCount = snapshot.data!.docs
              .where((doc) => doc.data()['isArchived'] != true)
              .length;
          _productsLoaded = true;
        }
        final productCount = _lastProductCount;

        // The header stays put; pull-to-refresh starts under it.
        return Column(
          children: [
            // The band stays put; the title scrolls with the page below.
            PageHeader(
              title: tr(context).navMarket,
              includeTitle: false,
              trailing: widget.onNotificationsPressed == null
                  ? null
                  : NotificationBell(
                      onPressed: widget.onNotificationsPressed!,
                      color: PageHeader.onBandColor,
                    ),
            ),
            Expanded(
              child: AgriRefreshIndicator(
                onRefresh: _refresh,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollUpdateNotification ||
                        n is ScrollEndNotification) {
                      _hints.onScroll(
                        context,
                        userScroll:
                            n is ScrollUpdateNotification &&
                            n.dragDetails != null,
                      );
                    }
                    return false;
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                      bottom: DockedNavBar.listEndPadding(context),
                    ),
                    children: [
                      PageTitle(title: tr(context).navMarket),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _welcomeHeader(productCount),
                            const SizedBox(height: 16),
                            _statRow(productCount),
                            const SizedBox(height: 16),
                            KeyedSubtree(
                              key: _hints.keys[0],
                              child: _salesPerformanceLineCard(productCount),
                            ),
                            const SizedBox(height: 20),
                            // The whole marketplace, one view at a time:
                            // the farmer picks which.
                            _insightsSection(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Which AgriTrade+ insight is showing.
  MarketInsight _insight = MarketInsight.marketAverage;

  // Best Sellers' and Buyer Areas' months, each chosen apart (picking one
  // never moves the other); both follow the Sales Performance month when
  // that changes.
  DateTime? _insightMonthsFrom;
  final Map<MarketDemandList, DateTime> _insightMonthsStore = {};
  Map<MarketDemandList, DateTime> get _insightMonths {
    final base = _analyticsMonth;
    if (_insightMonthsFrom != base) {
      _insightMonthsFrom = base;
      for (final list in MarketDemandList.values) {
        _insightMonthsStore[list] = base;
      }
    }
    return _insightMonthsStore;
  }

  static MarketDemandList? _demandListOf(MarketInsight insight) =>
      switch (insight) {
        MarketInsight.bestSellers => MarketDemandList.bestSellers,
        MarketInsight.buyerLocations => MarketDemandList.locations,
        MarketInsight.marketAverage => null,
      };

  // The month at the top of AgriTrade+ Insights: the calendar goes from the
  // first month with a completed sale on record to this month.
  Future<void> _pickInsightMonth(MarketDemandList list) async {
    final month = _insightMonths[list]!;
    var sales = const <Map<String, dynamic>>[];
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('market_sales')
          .get();
      sales = [for (final doc in snapshot.docs) doc.data()];
    } catch (_) {
      // Offline: the calendar still opens, on this month.
    }
    if (!mounted) return;
    final picked = await pickDemandMonth(
      context,
      selected: month,
      months: MarketDemandService.monthsOnRecord(sales: sales, month: month),
    );
    if (picked != null && mounted) {
      setState(() => _insightMonths[list] = picked);
    }
  }

  // "AgriTrade+ Insights": its title with the month on the right (like
  // Sales Performance; none for the market average, which is today's) and a
  // chevron to collapse it to that heading (the user's choice, 2026-11-07);
  // open, the picker under it, and under that only the one chosen.
  Widget _insightsSection() {
    final list = _demandListOf(_insight);
    return KeyedSubtree(
      key: _hints.keys[1],
      child: MarketCardShell(
        child: CollapsibleSection(
          heading: _SectionHeading(
            title: tl('AgriTrade+ Insights'),
            subtitle: tl('Across the whole marketplace'),
          ),
          trailing: list == null
              ? null
              : MonthPickerPill(
                  key: const Key('insightMonth'),
                  month: _insightMonths[list]!,
                  onTap: () => _pickInsightMonth(list),
                ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              MarketInsightPicker(
                value: _insight,
                onChanged: (value) => setState(() => _insight = value),
              ),
              Divider(height: 16, thickness: 1, color: AppColors.grey(200)),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey(_insight),
                  child: list == null
                      // What supported products are selling for right now.
                      ? const MarketAverageCard(embedded: true)
                      : MarketDemandCards(
                          month: _analyticsMonth,
                          only: list,
                          embedded: true,
                          months: _insightMonths,
                          onMonthChanged: (list, month) =>
                              setState(() => _insightMonths[list] = month),
                          monthTags: false,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _welcomeHeader(int productCount) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _welcomeProfile,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final fullName =
            (data['name'] ??
                    data['fullName'] ??
                    user.displayName ??
                    tl('Farmer'))
                .toString()
                .trim();
        // First name only: "Welcome, Daniella".
        final name = firstNameOf(fullName);
        final photoUrl = data['photoUrl']?.toString() ?? '';
        final imageProvider = photoUrl.isNotEmpty
            ? NetworkImage(photoUrl)
            : null;

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => widget.onNavigateToTab?.call(_profileTabIndex),
            child: Container(
              height: 106,
              // The text a little further in from the left edge, and the
              // photo a little further in from the right, both clear of the
              // banner's rounded corners.
              padding: const EdgeInsets.fromLTRB(40, 14, 34, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                image: const DecorationImage(
                  image: AssetImage('assets/images/market_farmer.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // On the banner's light picture: the same dark
                        // text in light and dark mode.
                        Text(
                          tr(context).welcomeBack,
                          style: TextStyle(
                            color: const Color(0xFF52614F),
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.montserrat(
                            color: const Color(0xFF173D21),
                            fontSize: 22,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr(context).productsListed(productCount),
                          style: TextStyle(
                            color: const Color(0xFF52614F),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // A white outline, on a soft shadow so it still shows
                  // against the light sky of the farm picture behind.
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 29,
                      backgroundColor: AppColors.surface,
                      backgroundImage: imageProvider,
                      child: imageProvider == null
                          ? Icon(Icons.person, color: AppColors.brand, size: 30)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statRow(int productCount) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _statOrders,
      builder: (context, snapshot) {
        final totalOrdersToday = confirmedTodayCount([
          for (final doc in snapshot.data?.docs ?? const []) doc.data(),
        ], now: DateTime.now());

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _statCard(
                  // The orders confirmed today and still to be sent — the
                  // ones on Orders' Confirmed tab, which it opens.
                  tr(context).ordersToday,
                  '$totalOrdersToday',
                  onTap: () => widget.onOpenOrders != null
                      ? widget.onOpenOrders!('confirmed')
                      : widget.onNavigateToTab?.call(_ordersTabIndex),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  tr(context).totalProductsCard,
                  '$productCount',
                  onTap: () => widget.onNavigateToTab?.call(_profileTabIndex),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String label, String value, {VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: AppTheme.card(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                  color: AppColors.grey(600),
                  letterSpacing: 0.4,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: GoogleFonts.montserrat(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashboard section title ("Sales Performance", "Best-Selling
/// Products"): Montserrat SemiBold. Built with GoogleFonts so the real
/// semibold face is used — a plain TextStyle(fontWeight: bold) only gets a
/// synthesized bold of the regular face, which reads noticeably weaker.
/// "Sales Performance" with "Completed-order revenue" under it.
class _SalesHeading extends StatelessWidget {
  const _SalesHeading();

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    return _SectionHeading(
      title: t.salesPerformance,
      subtitle: t.completedOrderRevenue,
    );
  }
}

/// A Market tab section's title with its one-line subtitle under it: the
/// same for Sales Performance and AgriTrade+ Insights.
class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionTitle(title),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GoogleFonts.montserrat(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    ),
  );
}
