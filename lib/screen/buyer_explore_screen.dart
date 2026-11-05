import 'dart:math';
import '../widgets/docked_nav_bar.dart';
import '../widgets/notification_bell.dart';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/commodity_master_list.dart';
import '../services/bought_first.dart';
import '../services/buyer_area_watcher.dart';
import '../services/delivery_coverage.dart';
import '../services/filters_on_scroll.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';
import '../services/product_recommendation_service.dart';
import '../services/product_visibility_service.dart';
import '../services/saved_products_service.dart';
import '../widgets/page_header.dart';
import '../widgets/retry_message.dart';
import '../widgets/agri_refresh_indicator.dart';
import '../widgets/app_search_bar.dart';
import 'buyer_search_screen.dart';
import 'product_detail_screen.dart';
import '../widgets/explore_product_card.dart';
import '../widgets/save_product_button.dart';
import '../widgets/agri_empty_state.dart';
import '../widgets/new_posts_pill.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../l10n/app_language.dart';

/// Which listings Explore shows, from the ids of every listing now
/// ([latest]) and the list it settled on before ([fixed], null at first):
///
/// * While the data may still be the phone's saved copy ([fromCache]), the
///   list is not settled yet: everything is shown, so a post made since the
///   copy was saved is never taken for a "new" one and hidden.
/// * Once settled, posts made after it wait for the "new posts" pill — so
///   the grid never moves under a buyer scrolled down — but come in at
///   once ([fresh], shown first) when the buyer is at the top ([atTop]).
@visibleForTesting
({Set<String>? fixed, Set<String> shown, Set<String> fresh}) exploreFeed({
  required Set<String>? fixed,
  required Set<String> latest,
  required bool fromCache,
  required bool atTop,
}) {
  if (fixed == null) {
    return fromCache
        ? (fixed: null, shown: latest, fresh: const {})
        : (fixed: {...latest}, shown: latest, fresh: const {});
  }
  final added = latest.difference(fixed);
  if (atTop && added.isNotEmpty) {
    return (fixed: {...latest}, shown: latest, fresh: added);
  }
  return (fixed: fixed, shown: fixed, fresh: const {});
}

class BuyerExploreScreen extends StatefulWidget {
  /// The notification bell in this tab's header; [bellKey] lets the
  /// first-time walkthrough point at it.
  final VoidCallback? onNotificationsPressed;
  final Key? bellKey;

  const BuyerExploreScreen({
    super.key,
    this.onNotificationsPressed,
    this.bellKey,
  });

  @override
  State<BuyerExploreScreen> createState() => BuyerExploreScreenState();
}

class BuyerExploreScreenState extends State<BuyerExploreScreen> {
  String _selectedCategory = 'All Postings';
  // Derived from the Commodity Master List so every category a farmer can
  // pick on Add Product (Vegetables, Fruits, Livestock, and any the Admin
  // added, such as Grains) also has a matching buyer-side filter — not a
  // separately hand-maintained list that can fall out of sync.
  List<String> get _categories => [
    'All Postings',
    ...CommodityRegistry.instance.categories,
  ];

  final ProductService _productService = ProductService();

  // The listings, opened once — not again on every rebuild (a like, a
  // filter change…) — and again only on Retry.
  late Stream<QuerySnapshot<Map<String, dynamic>>> _products = _productService
      .allProductsStream(includeMetadataChanges: true);

  final _grid = ScrollController();

  // Which mix of the feed is shown: 0 is the plain ranking; each Back to
  // the top (see [backToTop]) deals a fresh mix, so other products come
  // first. It only changes then, so the grid never reshuffles by itself.
  int _feedMix = 0;

  /// Back pressed on Explore: when the grid is scrolled down, it glides
  /// back to the top with a fresh mix of products and true is returned
  /// (Back is handled); at the top it returns false.
  bool backToTop() {
    if (!_grid.hasClients || _grid.offset <= 0) return false;
    setState(() {
      _feedMix++;
      _filtersHidden = false;
      _filtersOnScroll.reset();
    });
    _grid.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
    return true;
  }

  String _selectedBarangay = 'All Locations';

  // New posts wait for the buyer: the feed shows the listings that were
  // there when Explore opened ([_shownIds]); one posted while the buyer is
  // browsing is announced by the "new posts" pill (NewPostsPill) and
  // appears when they tap it or pull to refresh (or the next time the app
  // is opened), so the grid never jumps under their finger. Changes to
  // listings already shown (stock, price, removal) still apply at once.
  Set<String>? _shownIds;

  // Every listing in the latest data, for the next refresh.
  Set<String> _latestIds = {};

  // The posts the last refresh brought in — shown first, newest first.
  Set<String> _freshIds = {};

  // Scrolling down tucks the category and location filters away; scrolling
  // up (or reaching the top) brings them back.
  bool _filtersHidden = false;

  Map<String, String> _barangayByFarmerUid = {};
  Map<String, bool> _verifiedByFarmerUid = {};
  StreamSubscription? _usersSub;

  // Visibility-ranking inputs (ProductVisibilityService) — the "demand"
  // signal is each listing's own completedOrderCount (kept by Cloud
  // Functions; a buyer cannot read other buyers' orders to count them);
  // seller verification feeds
  // "credibility" alongside each product's own rating/reviewCount.

  // Liked Products hearts: the shared LikedProducts state, so a like made
  // here, in Search, on a farmer profile or in Product Details shows the
  // same everywhere.
  void _onLikesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    LikedProducts.instance
      ..start()
      ..addListener(_onLikesChanged);
    // Listings that deliver to the buyer's area come first; reorder when
    // the area arrives or changes.
    BuyerAreaWatcher.instance.addListener(_onAreaChanged);
    _watchMyOrders();
    _usersSub = FirebaseFirestore.instance
        .collection('publicProfiles')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _barangayByFarmerUid = {
              for (final doc in snap.docs)
                if ((doc.data()['role'] ?? '') == 'farmer' &&
                    (doc.data()['barangay'] ?? '').toString().isNotEmpty)
                  doc.id: doc.data()['barangay'].toString(),
            };
            // Derived directly from approvalStatus — the single source of
            // truth for verification state across the whole app — rather than
            // the separate isVerified field, which existed only as a mirror
            // and could historically drift from it (see
            // verification_queue_view.dart's _setFarmerApproval).
            _verifiedByFarmerUid = {
              for (final doc in snap.docs)
                if ((doc.data()['role'] ?? '') == 'farmer')
                  doc.id: doc.data()['approvalStatus'] == 'approved',
            };
          });
        });
  }

  // How often this buyer bought each product (from their own orders), so
  // what they buy most comes first in the feed.
  Map<String, int> _boughtCounts = const {};
  StreamSubscription? _ordersSub;

  void _watchMyOrders() {
    if (FirebaseAuth.instance.currentUser == null) return;
    _ordersSub = OrderService().buyerOrdersStream().listen((snap) {
      if (!mounted) return;
      final counts = boughtCounts([for (final d in snap.docs) d.data()]);
      if (!mapEquals(counts, _boughtCounts)) {
        setState(() => _boughtCounts = counts);
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _usersSub?.cancel();
    _grid.dispose();
    BuyerAreaWatcher.instance.removeListener(_onAreaChanged);
    LikedProducts.instance.removeListener(_onLikesChanged);
    super.dispose();
  }

  void _onAreaChanged() {
    if (mounted) setState(() {});
  }

  // Brings in the posts made since the feed was loaded, at the top.
  void _bringInNewPosts() {
    final shown = _shownIds ?? const <String>{};
    _freshIds = _latestIds.difference(shown);
    _shownIds = {..._latestIds};
  }

  // Pull to refresh: the new posts come in, and the feed is dealt a fresh
  // mix (as Back to the top does) — the products this buyer buys most
  // still come first (see boughtFirst).
  Future<void> _refreshProducts() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {
      _feedMix++;
      _bringInNewPosts();
    });
  }

  // The "new posts" pill: the same as pulling to refresh, then back to the
  // top of the grid, where the new posts now are.
  void _showNewPosts() {
    setState(() {
      _bringInNewPosts();
      _filtersHidden = false;
      _filtersOnScroll.reset();
    });
    if (_grid.hasClients) {
      _grid.animateTo(
        0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Same title row as Messages, Orders and Profile.
        PageHeader(
          title: tr(context).navExplore,
          trailing: widget.onNotificationsPressed == null
              ? null
              : NotificationBell(
                  key: widget.bellKey,
                  onPressed: widget.onNotificationsPressed!,
                  color: PageHeader.onBandColor,
                ),
        ),
        _buildSearchBar(),
        // Tucked away while scrolling down the products (see
        // _filtersHidden).
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _filtersHidden
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_buildCategoryChips(), _buildLocationFilter()],
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(child: _buildProductGrid()),
      ],
    );
  }

  // Tapping this (not typing in it — it's not a real text field) opens the
  // dedicated Search Screen, which owns the entire search experience
  // (suggested/trending/recent searches, category browsing, recommended
  // products, and result matching) — Explore itself no longer performs
  // text search inline.
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: AppSearchBar(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BuyerSearchScreen()),
        ),
      ),
    );
  }

  // ---- Row 1: categories ----
  // Small individual pills, each only as wide as its own label, the same
  // size as the location pill below so the two rows read as a pair.
  // Plain pills in a horizontal list (not ChoiceChips, whose built-in
  // minimum height was taller than this row and got clipped). The list
  // scrolls edge to edge, so the last pill can always be brought fully
  // into view.
  Widget _buildCategoryChips() {
    final categories = _categories;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final category = categories[index];
          return Center(
            child: _FilterPill(
              // Shown as just "All" — the stored value stays 'All Postings',
              // which the filtering compares against.
              label: category == 'All Postings' ? tl('All') : tl(category),
              selected: category == _selectedCategory,
              onTap: () => setState(() => _selectedCategory = category),
            ),
          );
        },
      ),
    );
  }

  // ---- Row 2: location ----
  // One compact pill showing the current choice; tapping it drops a small
  // menu straight below it (never a bottom sheet or a full-screen picker).
  final GlobalKey _locationPillKey = GlobalKey();

  Widget _buildLocationFilter() {
    final barangays = _barangayByFarmerUid.values.toSet().toList()..sort();
    if (barangays.isEmpty) return const SizedBox.shrink();

    final active = _selectedBarangay != 'All Locations';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _FilterPill(
          key: _locationPillKey,
          label: tl(_selectedBarangay),
          selected: active,
          trailing: Icons.keyboard_arrow_down_rounded,
          onTap: () => _pickLocation(['All Locations', ...barangays]),
        ),
      ),
    );
  }

  // Down hides the filters (category pills and the location dropdown); a
  // deliberate scroll back up, or reaching the top, shows them again (see
  // FiltersOnScroll).
  final FiltersOnScroll _filtersOnScroll = FiltersOnScroll();

  bool _onGridScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    bool? hide;
    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.reverse &&
        notification.metrics.pixels > _filtersOnScroll.hideAfter) {
      hide = true;
    }
    if (notification is ScrollUpdateNotification) {
      hide =
          _filtersOnScroll.update(
            delta: notification.scrollDelta ?? 0,
            pixels: notification.metrics.pixels,
            dragging: notification.dragDetails != null,
          ) ??
          hide;
    }
    if (hide != null && hide != _filtersHidden) {
      setState(() => _filtersHidden = hide!);
    }
    return false;
  }

  // A floating dropdown anchored under the location pill: text-only rows,
  // the current choice on a light green background with a checkmark.
  // Tapping a row applies it and closes the menu; tapping outside just
  // closes it. With many locations only the list scrolls — the menu itself
  // stays this size.
  Future<void> _pickLocation(List<String> options) async {
    final pill = _locationPillKey.currentContext?.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (pill is! RenderBox || overlay is! RenderBox) return;

    const gap = 6.0;
    const rowHeight = 42.0;
    final pillTopLeft = pill.localToGlobal(Offset.zero, ancestor: overlay);
    final top = pillTopLeft.dy + pill.size.height + gap;
    // Never wider than the screen allows, never taller than the room left
    // below the pill (or about six rows).
    final maxWidth = (overlay.size.width - 32).clamp(160.0, 260.0);
    final maxHeight = (overlay.size.height - top - 24).clamp(
      rowHeight * 2,
      rowHeight * 6 + 12,
    );

    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        pillTopLeft.dx,
        top,
        overlay.size.width - pillTopLeft.dx - maxWidth,
        0,
      ),
      color: AppColors.surface,
      surfaceTintColor: AppColors.surface,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.grey(200)),
      ),
      clipBehavior: Clip.antiAlias,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      constraints: BoxConstraints(
        minWidth: 200.0.clamp(0.0, maxWidth),
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      items: [
        for (final option in options)
          PopupMenuItem<String>(
            value: option,
            height: rowHeight,
            padding: EdgeInsets.zero,
            child: _LocationOption(
              label: tl(option),
              selected: option == _selectedBarangay,
              height: rowHeight,
            ),
          ),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _selectedBarangay = picked);
    }
  }

  Widget _buildProductGrid() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _products,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: AppColors.brand),
          );
        }
        if (snapshot.hasError) {
          return RetryMessage(
            message: tl(
              'Could not load products. Check your connection and try again.',
            ),
            onRetry: () => setState(() {
              _products = _productService.allProductsStream(
                includeMetadataChanges: true,
              );
              _shownIds = null;
            }),
          );
        }
        final all = snapshot.data?.docs ?? [];

        // What opening Explore found is what is shown; later posts wait for
        // the pill or a refresh (see _shownIds).
        _latestIds = {for (final d in all) d.id};
        final feed = exploreFeed(
          fixed: _shownIds,
          latest: _latestIds,
          fromCache: snapshot.data?.metadata.isFromCache ?? false,
          atTop: !_grid.hasClients || _grid.offset <= 0,
        );
        _shownIds = feed.fixed;
        if (feed.fresh.isNotEmpty) _freshIds = feed.fresh;
        final shown = feed.shown;

        // On sale, and in the category and barangay the buyer picked.
        bool listed(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
          final data = doc.data();
          if (data['isArchived'] == true || data['isSuspended'] == true) {
            return false;
          }
          if (_selectedCategory != 'All Postings' &&
              // Root crops and spices are Vegetables (normalizeCategory).
              normalizeCategory(data['category']).toLowerCase() !=
                  _selectedCategory.toLowerCase()) {
            return false;
          }
          if (_selectedBarangay != 'All Locations' &&
              _barangayByFarmerUid[(data['farmerId'] ?? '').toString()] !=
                  _selectedBarangay) {
            return false;
          }
          return true;
        }

        var docs = [
          for (final d in all)
            if (shown.contains(d.id) && listed(d)) d,
        ];
        // Posted since, and waiting: counted on the pill only when the buyer
        // would see them, so tapping it never brings in nothing.
        final waiting = all
            .where((d) => !shown.contains(d.id) && listed(d))
            .length;

        // Rank by demand + seller credibility + interaction (prescriptive
        // analytics: which listings get priority visibility). Ties — most
        // commonly an all-zero score on a fresh marketplace with no orders/
        // reviews/views yet — fall back to newest-first, today's old order.
        final scores = ProductVisibilityService.scoreProducts(
          products: {for (final d in docs) d.id: d.data()},
          completedOrderCountByProductId: {
            for (final d in docs)
              d.id: ProductRecommendationService.completedOrders(d.data()),
          },
          verifiedByFarmerId: _verifiedByFarmerUid,
        );
        // After a Back to the top, a fresh mix: each listing's rank is
        // nudged by a random amount fixed for that mix, so the order
        // changes but well-ranked listings still tend to come first.
        int created(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            (d.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        if (_feedMix > 0) {
          final nudged = {
            for (final d in docs)
              d.id:
                  ((scores[d.id] ?? 0) + 1) *
                  (0.4 + Random(Object.hash(_feedMix, d.id)).nextDouble()),
          };
          docs.sort((a, b) => nudged[b.id]!.compareTo(nudged[a.id]!));
        } else {
          docs.sort((a, b) {
            final scoreCompare = (scores[b.id] ?? 0).compareTo(
              scores[a.id] ?? 0,
            );
            if (scoreCompare != 0) return scoreCompare;
            final aCreated = a.data()['createdAt'] as Timestamp?;
            final bCreated = b.data()['createdAt'] as Timestamp?;
            return (bCreated?.millisecondsSinceEpoch ?? 0).compareTo(
              aCreated?.millisecondsSinceEpoch ?? 0,
            );
          });
        }
        // What this buyer buys most comes first, most-bought first, each
        // group still in the order above.
        docs = boughtFirst(docs, _boughtCounts, (d) => d.data());
        // Then the buyer's area first: listings whose delivery reaches it,
        // each group still in the order above; nothing else is hidden.
        docs = deliveringFirst(
          docs,
          BuyerAreaWatcher.instance.area,
          (d) => d.data(),
        );
        // The posts the last refresh brought in come first, newest first.
        if (_freshIds.isNotEmpty) {
          final fresh = docs.where((d) => _freshIds.contains(d.id)).toList()
            ..sort((a, b) => created(b).compareTo(created(a)));
          docs = [...fresh, ...docs.where((d) => !_freshIds.contains(d.id))];
        }

        // The "new posts" pill floats over the top of the feed (or of the
        // empty message, when nothing was on offer yet).
        Widget withNewPostsPill(Widget feed) => Stack(
          children: [
            Positioned.fill(child: feed),
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: NewPostsPill(count: waiting, onTap: _showNewPosts),
              ),
            ),
          ],
        );

        if (docs.isEmpty) {
          final isFiltered =
              _selectedBarangay != 'All Locations' ||
              _selectedCategory != 'All Postings';

          return withNewPostsPill(
            Center(
              child: AgriEmptyState(
                icon: isFiltered
                    ? Icons.search_off_rounded
                    : Icons.eco_outlined,
                title: _selectedBarangay != 'All Locations'
                    ? tl('No listings yet in {0}', [_selectedBarangay])
                    : tl('No products available yet'),
                subtitle: isFiltered
                    ? tl(
                        'Try a different search or clear your filters to see everything on offer.',
                      )
                    : tl(
                        'New marketplace listings will appear here once farmers post products.',
                      ),
                padding: const EdgeInsets.all(32),
                action: !isFiltered
                    ? null
                    : OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedBarangay = 'All Locations';
                            _selectedCategory = 'All Postings';
                          });
                        },
                        icon: const Icon(
                          Icons.filter_alt_off_outlined,
                          size: 18,
                        ),
                        label: Text(tl('Clear filters')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.brand,
                          side: BorderSide(color: AppColors.brand),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
              ),
            ),
          );
        }

        return withNewPostsPill(
          AgriRefreshIndicator(
            color: AppColors.brand,
            onRefresh: _refreshProducts,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const padding = 12.0;
                const spacing = 12.0;
                // Card height follows the column width and the system text
                // size (see ExploreProductCard.extentFor) rather than a fixed
                // aspect ratio, which is what used to overflow on narrow
                // phones.
                final cardWidth =
                    (constraints.maxWidth - padding * 2 - spacing) / 2;
                return NotificationListener<ScrollNotification>(
                  onNotification: _onGridScroll,
                  child: CustomScrollView(
                    controller: _grid,
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          padding,
                          4,
                          padding,
                          DockedNavBar.listEndPadding(context),
                        ),
                        sliver: SliverGrid.builder(
                          itemCount: docs.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: spacing,
                                mainAxisSpacing: spacing,
                                mainAxisExtent: ExploreProductCard.extentFor(
                                  cardWidth,
                                  MediaQuery.textScalerOf(context),
                                ),
                              ),
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data();
                            return ExploreProductCard(
                              data: data,
                              saved: LikedProducts.instance.contains(doc.id),
                              onToggleSave: LikedProducts.instance.canLike
                                  ? () => toggleLikedProduct(context, doc.id)
                                  : null,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProductDetailScreen(
                                    productId: doc.id,
                                    data: data,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// The pill used by both filter rows: dark green with white text when
// selected, white with a subtle border otherwise.
class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? trailing;
  final VoidCallback onTap;

  const _FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppColors.brand;
    return Material(
      color: selected ? AppColors.brandFill : AppColors.surface,
      // With a [trailing] arrow it opens a list, so it takes a dropdown's
      // corners; the category filters stay pills.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          trailing == null
              ? AppTheme.pillRadius
              : AppTheme.compactDropdownRadius,
        ),
        side: BorderSide(
          color: selected
              ? AppColors.brand
              : AppColors.brand.withValues(alpha: 0.25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A very long name is cut with an ellipsis rather than
              // making one pill as wide as the screen.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    height: 1.2,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 2),
                Icon(trailing, size: 16, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// One row of the location dropdown — text only, no icons. The current
// choice sits on a light green background with a checkmark on the right.
class _LocationOption extends StatelessWidget {
  final String label;
  final bool selected;
  final double height;

  const _LocationOption({
    required this.label,
    required this.selected,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      color: selected ? AppColors.tint : AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.brand : AppColors.text,
              ),
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_rounded, size: 18, color: AppColors.brand),
          ],
        ],
      ),
    );
  }
}
