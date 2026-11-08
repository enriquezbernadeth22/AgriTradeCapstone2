import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/commodity_master_list.dart';
import '../services/buyer_area_watcher.dart';
import '../services/delivery_coverage.dart';
import '../services/firebase_refs.dart';
import '../services/product_service.dart';
import '../services/product_recommendation_service.dart';
import '../services/product_visibility_service.dart';
import '../services/saved_products_service.dart';
import '../services/search_suggestions.dart';
import '../services/search_trends.dart';
import '../widgets/explore_search_pill.dart';
import '../widgets/explore_product_card.dart';
import '../widgets/save_product_button.dart';
import '../widgets/retry_message.dart';
import 'product_detail_screen.dart';
import 'farmer_storefront_screen.dart';
import '../widgets/agri_empty_state.dart';
import '../services/personal_recommendations.dart';
import '../services/order_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../l10n/app_language.dart';

/// The dedicated Buyer Search experience — opened by tapping the (non-
/// editable) search bar on Explore, never an inline field on the
/// marketplace itself. Owns the whole search flow on one screen: Suggested
/// Searches (while typing), Trending Searches, Recent Searches and
/// Recommended Products while browsing, switching to a live results grid
/// once the buyer actually searches. No bottom navigation bar, no Add to
/// Cart (this app has no cart — tapping a product always goes straight to
/// Product Detail, same as Explore).
class BuyerSearchScreen extends StatefulWidget {
  const BuyerSearchScreen({super.key});

  @override
  State<BuyerSearchScreen> createState() => _BuyerSearchScreenState();
}

class _BuyerSearchScreenState extends State<BuyerSearchScreen> {
  // Same buyer + same normalized query within this window logs only once
  // instead of once per submission — see _logSearchEvent. "Do not count 15
  // repeated searches in 30 seconds as 15 independent demand signals."
  static const Duration _dedupWindow = Duration(seconds: 60);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Per-query last-logged time, for the client-side dedup above. Session-
  // scoped (resets if this screen is closed and reopened) rather than
  // enforced in Firestore itself — firestore.rules explicitly forbids any
  // update/delete on searchEvents ("allow update, delete: if false"), so a
  // server-side merge-and-increment dedup would be rejected outright
  // without a rules change. This still fully covers the actual scenario
  // described (a rapid burst of repeat taps/submissions in one sitting).
  final Map<String, DateTime> _lastLoggedAt = {};

  // Updates on every keystroke — drives the live "Suggested Searches" list
  // only. Never itself logged and never used to fetch results.
  String _typed = '';

  // Set only when the buyer actually commits to a search (submits the
  // field, or taps a suggested/trending/recent term/category) — this is
  // what switches to the results view AND is what gets logged. Staying
  // null means we're still in the browsing/suggestions state.
  String? _activeQuery;

  final ProductService _productService = ProductService();

  List<String> _trendingSearches = [];
  StreamSubscription? _trendingSub;

  // ---- One ready moment for the browsing page (2026-11-08) ----
  // Trending, Recent and the time of the last "Clear" arrive separately;
  // shown as each came, Recommended Products sat right under the search
  // bar and was then pushed down. Until all three have answered (data,
  // nothing, or an error), Trending and Recent show placeholder pills in
  // their places and Recommended waits, so it appears where it stays.
  // What was last seen is kept for the next visit, so it opens ready.
  bool _trendingLoaded = false;
  bool _clearedLoaded = false;
  bool get _historyReady =>
      _trendingLoaded && _recentSearchesLoaded && _clearedLoaded;

  static List<String>? _lastTrending;
  static String? _lastUid;
  static List<(String, int)>? _lastRecentRaw;
  static int? _lastClearedAt;

  // This buyer's own searches as (term, when), newest first; what is shown
  // is the latest 8 distinct terms since they last tapped "Clear".
  List<(String, int)> _recentRaw = [];
  int _recentClearedAt = 0;
  static const int _maxRecent = 8;

  void _onLikesChanged() {
    if (mounted) setState(() {});
  }

  List<String> _recentSearches = [];
  bool _recentSearchesLoaded = false;
  bool _recentSearchesError = false;
  StreamSubscription? _recentSub;

  Map<String, bool> _verifiedByFarmerUid = {};
  StreamSubscription? _usersSub;

  // This buyer's own orders — what they buy, for Recommended Products.
  List<Map<String, dynamic>> _myOrders = const [];
  StreamSubscription? _ordersSub;

  // Every listing, for Recommended Products and the results alike: read
  // once when Search opens — first the copy already on this phone, so
  // something shows at once, then kept live — never again per rebuild.
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _allProducts;
  bool _productsFailed = false;
  StreamSubscription? _productsSub;

  // What buyers in the buyer's town bought (for a buyer with no history
  // of their own yet).
  List<Map<String, dynamic>> _areaSales = const [];

  void _listenToProducts() {
    _productsSub?.cancel();
    if (_productsFailed && mounted) setState(() => _productsFailed = false);
    FirebaseRefs.firestore
        .collection('products')
        .get(const GetOptions(source: Source.cache))
        .then((snap) {
          if (mounted && _allProducts == null && snap.docs.isNotEmpty) {
            setState(() => _allProducts = snap.docs);
          }
        })
        .catchError((Object _) {});
    _productsSub = _productService.allProductsStream().listen(
      (snap) {
        if (mounted) setState(() => _allProducts = snap.docs);
      },
      onError: (Object _) {
        if (mounted && _allProducts == null) {
          setState(() => _productsFailed = true);
        }
      },
    );
  }

  Future<void> _loadAreaSales(String uid) async {
    try {
      final me = await FirebaseRefs.firestore
          .collection('users')
          .doc(uid)
          .get();
      final town = (me.data()?['municipality'] ?? '').toString().trim();
      if (town.isEmpty) return;
      final sales = await FirebaseRefs.firestore
          .collection('market_sales')
          .where('buyerArea', isEqualTo: town)
          .limit(300)
          .get();
      if (!mounted) return;
      setState(() {
        _areaSales = [for (final d in sales.docs) d.data()];
      });
    } catch (_) {
      // Then the newest listings are recommended instead.
    }
  }

  @override
  void initState() {
    super.initState();
    // Results that deliver to the buyer's area come first; reorder when
    // the area arrives or changes.
    BuyerAreaWatcher.instance.addListener(_onAreaChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(_focusNode);
    });

    // TRENDING SEARCHES = real aggregated buyer search activity — every
    // buyer's logged searchEvents, most frequent query text first. A
    // single-field orderBy needs no composite index, unlike the per-buyer
    // query below.
    //
    // Read from searchTrends — per-term, per-day totals kept by the
    // aggregateSearchTrend Cloud Function, with no buyer ids in them — not
    // from other buyers' raw searchEvents. Ranked over the last 7 days (see
    // topTrendingTerms); with too little activity the list is empty and
    // the section simply isn't shown.
    _trendingSub = FirebaseRefs.firestore
        .collection('searchTrends')
        .orderBy('updatedAt', descending: true)
        .limit(150)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() {
              _trendingSearches = topTrendingTerms(
                snap.docs.map((d) => d.data()),
                now: DateTime.now(),
              );
              _lastTrending = _trendingSearches;
              _trendingLoaded = true;
            });
          },
          // A failure shows no trending terms, not a placeholder forever.
          onError: (_) {
            if (mounted) setState(() => _trendingLoaded = true);
          },
        );

    // RECENT SEARCHES = this logged-in buyer's own recent searches. No
    // orderBy paired with the equality filter (avoids needing a composite
    // Firestore index) — sorted and deduplicated client-side instead.
    final uid = FirebaseRefs.auth.currentUser?.uid;
    _listenToProducts();

    // Opened before: what was last seen, at once (then kept current).
    final trending = _lastTrending;
    if (trending != null) {
      _trendingSearches = trending;
      _trendingLoaded = true;
    }
    final recentRaw = _lastRecentRaw;
    final clearedAt = _lastClearedAt;
    if (uid != null &&
        uid == _lastUid &&
        recentRaw != null &&
        clearedAt != null) {
      _recentRaw = recentRaw;
      _recentClearedAt = clearedAt;
      _recentSearches = _visibleRecent();
      _recentSearchesLoaded = true;
      _clearedLoaded = true;
    } else if (uid != _lastUid) {
      _lastRecentRaw = null;
      _lastClearedAt = null;
    }
    _lastUid = uid;
    // Signed out: no history to wait for.
    if (uid == null) {
      _recentSearchesLoaded = true;
      _clearedLoaded = true;
    }

    if (uid != null) {
      _loadRecentClearedAt(uid);
      _loadAreaSales(uid);

      _ordersSub = OrderService().buyerOrdersStream().listen((snap) {
        if (!mounted) return;
        setState(() => _myOrders = [for (final d in snap.docs) d.data()]);
      }, onError: (_) {});

      // Liked products (shared state — also draws the hearts on the cards).
      LikedProducts.instance
        ..start()
        ..addListener(_onLikesChanged);

      _recentSub = FirebaseRefs.firestore
          .collection('searchEvents')
          .where('userId', isEqualTo: uid)
          .limit(50)
          .snapshots()
          .listen(
            (snap) {
              if (!mounted) return;
              final docs = [...snap.docs]
                ..sort((a, b) {
                  final at = a.data()['createdAt'] as Timestamp?;
                  final bt = b.data()['createdAt'] as Timestamp?;
                  return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
                    at?.millisecondsSinceEpoch ?? 0,
                  );
                });
              _recentRaw = [
                for (final doc in docs)
                  (
                    _normalize((doc.data()['query'] ?? '').toString()),
                    // Not yet stamped by the server = just now.
                    (doc.data()['createdAt'] as Timestamp?)
                            ?.millisecondsSinceEpoch ??
                        DateTime.now().millisecondsSinceEpoch,
                  ),
              ];
              _lastRecentRaw = _recentRaw;
              setState(() {
                _recentSearches = _visibleRecent();
                _recentSearchesLoaded = true;
                _recentSearchesError = false;
              });
            },
            onError: (_) {
              if (mounted) {
                setState(() {
                  _recentSearchesLoaded = true;
                  _recentSearchesError = true;
                });
              }
            },
          );
    }

    // Visibility-ranking inputs for Recommended Products / results, same
    // signals Explore's own grid ranks by (ProductVisibilityService).
    _usersSub = FirebaseRefs.firestore
        .collection('publicProfiles')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            // Derived directly from approvalStatus — the single source of
            // truth for verification state — rather than the separate
            // isVerified field, which existed only as a mirror and could
            // historically drift from it.
            _verifiedByFarmerUid = {
              for (final doc in snap.docs)
                if ((doc.data()['role'] ?? '') == 'farmer')
                  doc.id: doc.data()['approvalStatus'] == 'approved',
            };
          });
        });
  }

  @override
  void dispose() {
    _trendingSub?.cancel();
    _recentSub?.cancel();
    _ordersSub?.cancel();
    _productsSub?.cancel();
    BuyerAreaWatcher.instance.removeListener(_onAreaChanged);
    LikedProducts.instance.removeListener(_onLikesChanged);
    _usersSub?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onAreaChanged() {
    if (mounted) setState(() {});
  }

  List<String> _visibleRecent() {
    final seen = <String>{};
    final recent = <String>[];
    for (final (term, at) in _recentRaw) {
      if (term.isEmpty || at <= _recentClearedAt || !seen.add(term)) continue;
      recent.add(term);
      if (recent.length >= _maxRecent) break;
    }
    return recent;
  }

  // "Clear" hides this buyer's history from their own list. The logged
  // searchEvents themselves are analytics (firestore.rules allows no
  // delete), so what is remembered — on this device — is the moment they
  // cleared it; only searches after that are shown again.
  static String _clearedKey(String uid) => 'recent_searches_cleared_$uid';

  Future<void> _loadRecentClearedAt(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _recentClearedAt = prefs.getInt(_clearedKey(uid)) ?? 0;
    } catch (_) {}
    _lastClearedAt = _recentClearedAt;
    if (mounted) {
      setState(() {
        _clearedLoaded = true;
        _recentSearches = _visibleRecent();
      });
    }
  }

  Future<void> _clearRecentSearches() async {
    final uid = FirebaseRefs.auth.currentUser?.uid;
    if (uid == null) return;
    _recentClearedAt = DateTime.now().millisecondsSinceEpoch;
    _lastClearedAt = _recentClearedAt;
    setState(() => _recentSearches = _visibleRecent());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_clearedKey(uid), _recentClearedAt);
    } catch (_) {}
  }

  // lowercase, trim, collapse repeated internal whitespace.
  static String _normalize(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  // Logs ONE meaningful search event — called only from _commitSearch
  // (submit, or picking a suggested/trending/recent term), never from
  // onChanged/every keystroke.
  Future<void> _logSearchEvent(String query) async {
    final uid = FirebaseRefs.auth.currentUser?.uid;
    if (uid == null) return;
    final normalized = _normalize(query);
    if (normalized.isEmpty) return; // never log a blank search

    // Dedup: the same buyer resubmitting the same normalized query within
    // the window is one demand signal, not one per tap — "do not count 15
    // repeated searches in 30 seconds as 15 independent demand signals".
    // Keyed per query text so searching something else in between still
    // logs normally.
    final now = DateTime.now();
    final last = _lastLoggedAt[normalized];
    if (last != null && now.difference(last) < _dedupWindow) return;
    _lastLoggedAt[normalized] = now;

    try {
      await FirebaseRefs.firestore.collection('searchEvents').add({
        'userId': uid,
        'query': normalized,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort telemetry only — never surface this to the buyer.
    }
  }

  void _commitSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _controller.text = trimmed;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: trimmed.length),
    );
    setState(() {
      _activeQuery = trimmed;
      _typed = trimmed;
    });
    _focusNode.unfocus();
    _logSearchEvent(trimmed);
  }

  void _clearSearch() {
    _controller.clear();
    setState(() {
      _typed = '';
      _activeQuery = null;
    });
    FocusScope.of(context).requestFocus(_focusNode);
  }

  // SUGGESTED SEARCHES = supported commodity names relevant to the typed
  // text — a master-list-only autocomplete, distinct from Trending
  // Searches (real aggregated activity) below.
  List<String> get _suggestedSearches => suggestedSearchTerms(
    _typed,
    commodities: CommodityRegistry.instance.all.map((c) => c.name),
    listings: [for (final d in _liveListings) d.data()],
  );

  // Active listings, as the results show them.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _liveListings => [
    for (final d in _allProducts ?? const [])
      if (d.data()['isArchived'] != true && d.data()['isSuspended'] != true) d,
  ];

  // While typing: the listings that match what is typed so far (product or
  // farmer name), best ranked first — the same match the results use.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _typedMatches {
    final q = _typed.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final matches = _liveListings.where((d) {
      final data = d.data();
      final name = (data['name'] ?? '').toString().toLowerCase();
      final farmer = (data['farmerName'] ?? '').toString().toLowerCase();
      return name.contains(q) || farmer.contains(q);
    }).toList();
    return _rankedByVisibility(matches);
  }

  @override
  Widget build(BuildContext context) {
    final showingResults = _activeQuery != null;
    // The cream page of the user's picture (2026-11-08).
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: showingResults ? _buildResults() : _buildBrowsingState(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 16, 8),
      child: Row(
        children: [
          // A plain dark green arrow, no circle (the user's picture).
          IconButton(
            tooltip: tl('Back'),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: AppColors.brand,
              size: 24,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          // Explore's very own search bar, here as the field itself: the
          // same height, outline, icon and text (2026-11-08).
          Expanded(
            child: ExploreSearchPill(
              hint: tl('Search crops, livestock, or farmers...'),
              controller: _controller,
              focusNode: _focusNode,
              onClear: _clearSearch,
              onChanged: (value) => setState(() {
                _typed = value;
                // Editing the field after a search was active returns to
                // live typing/suggestions instead of silently keeping a
                // stale results view on screen.
                _activeQuery = null;
              }),
              onSubmitted: _commitSearch,
            ),
          ),
        ],
      ),
    );
  }

  // A section's title in dark green, with its small icon before it
  // (gold flame for Trending, a clock for Recent, a gold star for
  // Recommended; the user's picture, 2026-11-08).
  Widget _sectionHeading(String text, {IconData? icon, Color? iconColor}) {
    final title = Text(
      text,
      style: TextStyle(
        fontFamily: 'Montserrat',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.brand,
      ),
    );
    if (icon == null) return title;
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor ?? AppColors.brand),
        const SizedBox(width: 7),
        Flexible(child: title),
      ],
    );
  }

  static const Color _gold = Color(0xFFF5BB24);

  // A wrap of search terms to tap: pale green pills with no outline for
  // Trending ([tinted]), white pills with a thin grey outline otherwise.
  Widget _chipRow(
    List<String> terms, {
    required IconData icon,
    bool tinted = false,
  }) {
    final fill = tinted
        ? (AppColors.isDark ? AppColors.tint : const Color(0xFFE3F0DA))
        : AppColors.surface;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final term in terms)
          Material(
            color: fill,
            shape: StadiumBorder(
              side: tinted
                  ? BorderSide.none
                  : BorderSide(color: AppColors.grey(300)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _commitSearch(term),
              child: Padding(
                // About as tall as Explore's pills.
                padding: const EdgeInsets.fromLTRB(10, 6, 13, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 13,
                      color: tinted ? AppColors.brand : AppColors.grey(600),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      term,
                      style: TextStyle(
                        fontSize: 11,
                        color: tinted ? AppColors.brand : AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Search bar (above), then: Trending Searches, Recent Searches,
  // Recommended Products. Categories are not repeated here — Explore's
  // category pills already cover that. "Suggested Searches" only appears
  // while the buyer is typing (it is the field's autocomplete).
  Widget _buildBrowsingState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        if (_suggestedSearches.isNotEmpty) ...[
          _sectionHeading(tl('Suggested Searches')),
          const SizedBox(height: 10),
          _chipRow(_suggestedSearches, icon: Icons.search),
          const SizedBox(height: 22),
        ],
        // As the buyer types: the products matching so far, before any
        // Enter — the full list is one tap away.
        if (_typed.trim().isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: _sectionHeading(tl('Matching Products'))),
              if (_typedMatches.isNotEmpty)
                TextButton(
                  key: const Key('seeAllResults'),
                  onPressed: () => _commitSearch(_typed),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.brand,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    tl('See all results ({0})', [_typedMatches.length]),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_typedMatches.isEmpty)
            Text(
              _allProducts == null
                  ? tl('Loading products…')
                  : tl('No products match “{0}” yet.', [_typed.trim()]),
              style: TextStyle(color: AppColors.grey(600), fontSize: 11.5),
            )
          else
            _productGrid(_typedMatches.take(4).toList()),
          const SizedBox(height: 22),
        ],
        // Until Trending and Recent have answered: their places held by
        // placeholder pills, Recommended not yet (see _historyReady).
        if (!_historyReady) ..._historyPlaceholder(),
        // Hidden entirely until there is real, recent search activity.
        if (_historyReady && _trendingSearches.isNotEmpty) ...[
          _sectionHeading(
            tl('Trending Searches'),
            icon: Icons.local_fire_department_rounded,
            iconColor: _gold,
          ),
          const SizedBox(height: 9),
          _chipRow(_trendingSearches, icon: Icons.trending_up, tinted: true),
          const SizedBox(height: 18),
        ],
        if (_historyReady && _recentSearches.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: _sectionHeading(
                  tl('Recent Searches'),
                  icon: Icons.schedule_rounded,
                ),
              ),
              TextButton(
                onPressed: _clearRecentSearches,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  tl('Clear'),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _chipRow(_recentSearches, icon: Icons.schedule_rounded),
          const SizedBox(height: 18),
        ],
        if (_historyReady && _recentSearches.isEmpty) ...[
          _sectionHeading(tl('Recent Searches'), icon: Icons.schedule_rounded),
          const SizedBox(height: 6),
          Text(
            _recentSearchesError
                ? tl('Could not load recent searches.')
                : tl('No recent searches yet.'),
            style: TextStyle(color: AppColors.grey(600), fontSize: 11.5),
          ),
          const SizedBox(height: 22),
        ],
        if (_historyReady) ...[
          _sectionHeading(
            tl('Recommended Products'),
            icon: Icons.star_rounded,
            iconColor: _gold,
          ),
          const SizedBox(height: 4),
          _buildRecommendedProducts(),
        ],
      ],
    );
  }

  // Trending and Recent while they load: their headings, and grey pills
  // the size of the real ones.
  List<Widget> _historyPlaceholder() {
    Widget pills(List<double> widths) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final width in widths)
          Container(
            width: width,
            height: 27,
            decoration: BoxDecoration(
              color: AppColors.grey(200),
              borderRadius: BorderRadius.circular(AppTheme.pillRadius),
            ),
          ),
      ],
    );
    return [
      KeyedSubtree(
        key: const Key('searchHistoryLoading'),
        child: _sectionHeading(
          tl('Trending Searches'),
          icon: Icons.local_fire_department_rounded,
          iconColor: _gold,
        ),
      ),
      const SizedBox(height: 9),
      pills(const [70, 82]),
      const SizedBox(height: 18),
      _sectionHeading(tl('Recent Searches'), icon: Icons.schedule_rounded),
      const SizedBox(height: 9),
      pills(const [78, 64, 104]),
      const SizedBox(height: 18),
    ];
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _rankedByVisibility(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final scores = ProductVisibilityService.scoreProducts(
      products: {for (final d in docs) d.id: d.data()},
      // Kept on each listing by Cloud Functions (a buyer cannot read
      // other buyers' orders to count them here).
      completedOrderCountByProductId: {
        for (final d in docs)
          d.id: ProductRecommendationService.completedOrders(d.data()),
      },
      verifiedByFarmerId: _verifiedByFarmerUid,
    );
    final sorted = [...docs]
      ..sort((a, b) {
        final scoreCompare = (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0);
        if (scoreCompare != 0) return scoreCompare;
        final aCreated = a.data()['createdAt'] as Timestamp?;
        final bCreated = b.data()['createdAt'] as Timestamp?;
        return (bCreated?.millisecondsSinceEpoch ?? 0).compareTo(
          aCreated?.millisecondsSinceEpoch ?? 0,
        );
      });
    // The buyer's area first: results whose delivery reaches it, each
    // group still ranked as above; nothing else is hidden.
    return deliveringFirst(
      sorted,
      BuyerAreaWatcher.instance.area,
      (d) => d.data(),
    );
  }

  // This buyer's own search terms, newest first.
  List<String> get _mySearchTerms => [for (final (term, _) in _recentRaw) term];

  // Made for this buyer (see PersonalRecommendations): their own orders,
  // likes and searches; with no history yet, what buyers in their town
  // buy; failing that, the newest listings. Only active, in-stock ones.
  ({
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    RecommendationBasis basis,
  })
  _recommended(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final byId = {for (final doc in docs) doc.id: doc};
    final result = PersonalRecommendations.recommend(
      products: {for (final doc in docs) doc.id: doc.data()},
      orders: _myOrders,
      likedIds: LikedProducts.instance.orderedIds,
      searches: _mySearchTerms,
      areaSales: _areaSales,
    );
    return (
      docs: [for (final id in result.ids.take(8)) byId[id]!],
      basis: result.basis,
    );
  }

  // The same two-column cards as Explore, sized the same way (height from
  // the column width and text size — see ExploreProductCard.extentFor).
  Widget _productGrid(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final cardWidth = (constraints.maxWidth - spacing) / 2;
        // Rows of two, each as tall as its cards need: a row where neither
        // listing sells wholesale leaves out the "Wholesale | Min" strip
        // (the user's picture, 2026-11-08).
        bool wholesale(Map<String, dynamic> d) {
          final price = (d['wholesalePrice'] as num?)?.toDouble();
          return d['wholesaleEnabled'] == true ||
              (d['wholesaleEnabled'] == null && price != null && price > 0);
        }

        Widget card(QueryDocumentSnapshot<Map<String, dynamic>> doc, bool row) {
          final data = doc.data();
          return ExploreProductCard(
            reserveWholesaleRow: row,
            data: data,
            saved: LikedProducts.instance.contains(doc.id),
            onToggleSave: LikedProducts.instance.canLike
                ? () => toggleLikedProduct(context, doc.id)
                : null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ProductDetailScreen(productId: doc.id, data: data),
              ),
            ),
          );
        }

        return Column(
          children: [
            for (var i = 0; i < docs.length; i += 2)
              Builder(
                builder: (context) {
                  final pair = docs.skip(i).take(2).toList();
                  final row = pair.any((d) => wholesale(d.data()));
                  return Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : spacing),
                    child: SizedBox(
                      height: ExploreProductCard.extentFor(
                        cardWidth,
                        MediaQuery.textScalerOf(context),
                        withWholesaleRow: row,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: card(pair[0], row)),
                          const SizedBox(width: spacing),
                          Expanded(
                            child: pair.length > 1
                                ? card(pair[1], row)
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildRecommendedProducts() {
    return Builder(
      builder: (context) {
        final all = _allProducts;
        if (all == null) {
          if (_productsFailed) {
            return RetryMessage(
              message: tl(
                'Could not load recommended products. Check your connection and try again.',
              ),
              onRetry: _listenToProducts,
            );
          }
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            ),
          );
        }
        final docs = all
            .where(
              (d) =>
                  d.data()['isArchived'] != true &&
                  d.data()['isSuspended'] != true,
            )
            .toList();
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              tl('No products available yet.'),
              style: TextStyle(color: AppColors.grey(600), fontSize: 11.5),
            ),
          );
        }
        final recommended = _recommended(docs);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // No line saying what they were chosen by: just the products.
            const SizedBox(height: 8),
            _productGrid(recommended.docs),
          ],
        );
      },
    );
  }

  Widget _buildResults() {
    return Builder(
      builder: (context) {
        final all = _allProducts;
        if (all == null) {
          if (_productsFailed) {
            return RetryMessage(
              message: tl(
                'Could not load products. Check your connection and try again.',
              ),
              onRetry: _listenToProducts,
            );
          }
          return Center(
            child: CircularProgressIndicator(color: AppColors.brand),
          );
        }
        var docs = [...all];
        docs = docs
            .where(
              (d) =>
                  d.data()['isArchived'] != true &&
                  d.data()['isSuspended'] != true,
            )
            .toList();

        final query = _activeQuery;
        if (query != null && query.isNotEmpty) {
          final q = query.toLowerCase();
          docs = docs.where((d) {
            final data = d.data();
            final name = (data['name'] ?? '').toString().toLowerCase();
            final farmer = (data['farmerName'] ?? '').toString().toLowerCase();
            return name.contains(q) || farmer.contains(q);
          }).toList();
        }

        final ranked = _rankedByVisibility(docs);
        final normalizedQuery = query?.trim().toLowerCase() ?? '';

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseRefs.firestore
              .collection('publicProfiles')
              .snapshots(),
          builder: (context, profileSnapshot) {
            final farmerHits = normalizedQuery.isEmpty
                ? <QueryDocumentSnapshot<Map<String, dynamic>>>[]
                : (profileSnapshot.data?.docs ?? const []).where((profile) {
                    final data = profile.data();
                    if (data['role'] != 'farmer' ||
                        data['approvalStatus'] != 'approved') {
                      return false;
                    }
                    final name = (data['name'] ?? data['fullName'] ?? '')
                        .toString()
                        .toLowerCase();
                    return name.contains(normalizedQuery);
                  }).toList();

            if (ranked.isEmpty &&
                farmerHits.isEmpty &&
                normalizedQuery.isNotEmpty) {
              return Center(
                child: AgriEmptyState(
                  icon: Icons.search_off_rounded,
                  title: tl('No results for "{0}"', [query]),
                  subtitle: tl('Try a different search term.'),
                  padding: const EdgeInsets.all(32),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (farmerHits.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      tl('Farmers'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brand,
                      ),
                    ),
                  ),
                  ...farmerHits.map(_buildFarmerCard),
                  if (ranked.isNotEmpty) const SizedBox(height: 12),
                ],
                if (ranked.isNotEmpty) ...[
                  if (farmerHits.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        tl('Products'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brand,
                        ),
                      ),
                    ),
                  _productGrid(ranked),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFarmerCard(
    QueryDocumentSnapshot<Map<String, dynamic>> farmerDoc,
  ) {
    final farmer = farmerDoc.data();
    final name = (farmer['name'] ?? farmer['fullName'] ?? tl('Farmer'))
        .toString();
    final photoUrl = farmer['photoUrl']?.toString() ?? '';
    final location =
        [farmer['barangay'], farmer['municipality'], farmer['province']]
            .where((part) => part != null && part.toString().trim().isNotEmpty)
            .join(', ');
    final rating = (farmer['rating'] as num?)?.toDouble();
    final reviewCount = (farmer['reviewCount'] as num?)?.toInt() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.accent,
          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: photoUrl.isEmpty
              ? Icon(Icons.person, color: AppColors.brand)
              : null,
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            if (location.isNotEmpty) location else tl('Verified farmer'),
            if (rating != null && reviewCount > 0)
              tl('{0} ★ · {1} reviews', [
                rating.toStringAsFixed(1),
                reviewCount,
              ]),
          ].join('  ·  '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FarmerStorefrontScreen(farmerId: farmerDoc.id),
          ),
        ),
      ),
    );
  }
}
