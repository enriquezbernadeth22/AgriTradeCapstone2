import '../widgets/agri_app_bar.dart';
import '../widgets/reviewer_avatar.dart';
import '../widgets/review_like_button.dart';
import '../widgets/farm_buyer_map.dart';
import '../widgets/docked_nav_bar.dart';
import '../widgets/section_tabs.dart';
import '../widgets/explore_product_card.dart';
import '../services/buyer_area_watcher.dart';
import '../services/delivery_coverage.dart';
import '../services/firebase_refs.dart';
import '../theme/app_theme.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/app_scaffold_messenger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/message_service.dart';
import '../services/product_service.dart';
import '../services/product_share_service.dart';
import '../services/public_farm_location.dart';
import '../services/harvest_info.dart';
import '../services/market_price_helpers.dart';
import '../widgets/agri_refresh_indicator.dart';
import '../widgets/save_product_button.dart';
import '../widgets/order_card.dart' show BarActionStyle;
import '../data/commodity_master_list.dart';
import 'chat_screen.dart';
import 'place_order_screen.dart';
import 'product_reviews_screen.dart';
import 'buyer_market_view.dart';
import 'farmer_storefront_screen.dart';
import '../widgets/chat_photo_viewer.dart' show openPhotoGallery;
import '../widgets/profile_avatar.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';
import '../services/buyer_type_watcher.dart';
import '../widgets/coach_mark.dart';
import '../services/road_route_service.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  final Map<String, dynamic> data;

  const ProductDetailScreen({
    super.key,
    required this.productId,
    required this.data,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Uint8List? _imageBytes;
  String? _imageUrl;
  late Map<String, dynamic> _currentData;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _productSub;

  late final Future<DocumentSnapshot<Map<String, dynamic>>?> _farmerProfile;
  late final Future<
    ({
      String area,
      double? buyerLat,
      double? buyerLng,
      double? centerLat,
      double? centerLng,
    })
  >
  _farmerLocation;
  // The road from the buyer's saved location to the farm area, once the
  // map preview has it: the distance then reads by road.
  RoadRoute? _previewRoad;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _reviews = FirebaseRefs
      .firestore
      .collection('productReviews')
      .where('productId', isEqualTo: widget.productId)
      .snapshots();
  final ValueNotifier<int> _galleryPage = ValueNotifier(0);
  bool _productUnavailable = false;
  bool _productLoadError = false;

  // What the first-time tour points at.
  final _messageKey = GlobalKey();
  final _mapKey = GlobalKey();

  // ---- Section tabs (the user's design, 2026-11-08) ----
  // Overview, Description, Reviews and Recommended, in one row under the
  // farmer that scrolls with the page (never pinned at the top). A tap
  // only chooses what shows under it — Overview everything, the others
  // their one section — and never moves the page (the user's choice,
  // 2026-11-08).
  final _scroll = ScrollController();
  int _activeTab = 0;

  void _chooseTab(int i) {
    if (i == _activeTab) return;
    setState(() => _activeTab = i);
  }

  // Whether section [tab] shows under the tabs (Overview shows them all).
  bool _shows(int tab) => _activeTab == 0 || _activeTab == tab;

  // ---- Recommended Products ----
  // Other listings of the same product (by its name), from other farmers:
  // not archived or suspended, and with stock. Read once per screen.
  late final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _recommended = _loadRecommended();

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadRecommended() async {
    final name = _currentData['name']?.toString() ?? '';
    if (name.isEmpty) return const [];
    try {
      final snapshot = await FirebaseRefs.firestore
          .collection('products')
          .where('name', isEqualTo: name)
          .limit(20)
          .get();
      return [
        for (final doc in snapshot.docs)
          if (doc.id != widget.productId &&
              doc.data()['isArchived'] != true &&
              doc.data()['isSuspended'] != true &&
              ((doc.data()['quantity'] as num?) ?? 0) > 0)
            doc,
      ];
    } catch (_) {
      return const [];
    }
  }

  Widget _recommendedSection(String name) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.shopping_bag_outlined,
                size: 19,
                color: DockedNavBar.selectedColor,
              ),
              const SizedBox(width: 8),
              Expanded(child: _sectionTitle(tl('Recommended Products'))),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 27, top: 2),
            child: Text(
              tl('Other listings of {0}', [name]),
              style: TextStyle(fontSize: 11.5, color: _muted),
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            future: _recommended,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 120,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final docs = snapshot.data!;
              if (docs.isEmpty) {
                return _PaleNote(
                  child: Text(
                    tl('No other listings of {0} right now.', [name]),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppColors.grey(800),
                    ),
                  ),
                );
              }
              const width = 160.0;
              final height = ExploreProductCard.extentFor(
                width,
                MediaQuery.textScalerOf(context),
              );
              return SizedBox(
                key: const Key('recommendedProducts'),
                height: height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data();
                    return SizedBox(
                      width: width,
                      child: ExploreProductCard(
                        data: data,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProductDetailScreen(
                              productId: doc.id,
                              data: data,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // The first product a buyer opens: the farm map (when it is in view) and
  // asking the farmer first. Order Now needs no explaining.
  void _showTour() {
    if (!mounted) return;
    // Not on the farmer's own listing: there is nobody to ask.
    try {
      final uid = FirebaseRefs.auth.currentUser?.uid;
      if (uid != null && uid == _currentData['farmerId']?.toString()) return;
    } catch (_) {}
    showCoachMarksOnce(
      context: context,
      prefsKey: '${TutorialTips.tourKeyPrefix}product',
      steps: [
        CoachMarkStep(
          targetKey: _mapKey,
          title: tl('Where the farm is'),
          message: tl(
            'Tap the map for the distance from you and directions to the farm.',
          ),
        ),
        CoachMarkStep(
          targetKey: _messageKey,
          title: tl('Ask before you order'),
          message: tl(
            'Message the farmer about the harvest, the price or delivery. The chat stays in Messages.',
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showTour());
    _currentData = Map<String, dynamic>.from(widget.data);
    _watchProduct();
    ProductService().logProductView(widget.productId);

    // Loaded once — not from build(), where every rebuild (a new gallery
    // page, expanding the reviews) would fetch the farmer again and reload
    // the map.
    final farmerId = widget.data['farmerId']?.toString();
    _farmerProfile = _fetchFarmerProfile(farmerId);
    _farmerLocation = _loadApproximateFarmerLocation(farmerId);

    final b64 = widget.data['imageBase64']?.toString();
    if (b64 != null && b64.isNotEmpty) {
      try {
        _imageBytes = base64Decode(b64);
      } catch (_) {
        _imageBytes = null;
      }
    }

    if (_imageBytes == null) {
      final url = widget.data['imageUrl']?.toString();
      if (url != null && url.isNotEmpty) {
        _imageUrl = url;
      } else if (widget.data['imageUrls'] is List &&
          (widget.data['imageUrls'] as List).isNotEmpty) {
        _imageUrl = (widget.data['imageUrls'] as List).first?.toString();
      }
    }
  }

  void _watchProduct() {
    _productSub?.cancel();
    _productSub = FirebaseRefs.firestore
        .collection('products')
        .doc(widget.productId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            final data = snapshot.data();
            setState(() {
              _productLoadError = false;
              final available =
                  snapshot.exists &&
                  data != null &&
                  data['isArchived'] != true &&
                  data['isSuspended'] != true;
              _productUnavailable = !available;
              if (snapshot.exists &&
                  data != null &&
                  data['isArchived'] != true &&
                  data['isSuspended'] != true) {
                _currentData = Map<String, dynamic>.from(data);
              }
            });
          },
          onError: (_) {
            if (mounted) setState(() => _productLoadError = true);
          },
        );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _productSub?.cancel();
    _galleryPage.dispose();
    super.dispose();
  }

  String? _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      return DateFormat('MMM d, y - h:mm a').format(ts.toDate());
    }
    return null;
  }

  Widget _productImage() {
    if (_imageBytes != null) {
      return Image.memory(
        _imageBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    if (_imageUrl != null && _imageUrl!.isNotEmpty) {
      return Image.network(
        _imageUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : Center(child: CircularProgressIndicator(color: AppColors.brand)),
        errorBuilder: (context, error, stackTrace) => Container(
          color: AppColors.accent,
          child: Icon(Icons.broken_image, size: 90, color: AppColors.brand),
        ),
      );
    }
    return Container(
      color: AppColors.accent,
      child: Icon(Icons.eco_rounded, size: 90, color: AppColors.brand),
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _fetchFarmerProfile(
    String? farmerId,
  ) async {
    if (farmerId == null || farmerId.isEmpty) return null;
    try {
      return await FirebaseRefs.firestore
          .collection('publicProfiles')
          .doc(farmerId)
          .get();
    } catch (_) {
      return null;
    }
  }

  Future<
    ({
      String area,
      double? buyerLat,
      double? buyerLng,
      double? centerLat,
      double? centerLng,
    })
  >
  _loadApproximateFarmerLocation(String? farmerId) async {
    if (farmerId == null || farmerId.isEmpty) {
      return (
        area: tl('Farm area unavailable'),
        buyerLat: null,
        buyerLng: null,
        centerLat: null,
        centerLng: null,
      );
    }
    final buyerId = FirebaseRefs.auth.currentUser?.uid;
    // The farmer's public, barangay-level location only (see
    // public_farm_location.dart) — the same source the Farm Location map
    // uses, so both show the same stable area and neither can reveal a
    // farm's exact pin.
    // The farm's area and the buyer's saved position, read at the same
    // time; the buyer's not being readable only leaves out the distance.
    Future<Map<String, dynamic>?> buyerPosition() async {
      if (buyerId == null || buyerId.isEmpty) return null;
      try {
        return (await FirebaseRefs.firestore
                .collection('users')
                .doc(buyerId)
                .collection('private')
                .doc('geo')
                .get())
            .data();
      } catch (_) {
        return null;
      }
    }

    final farmLookup = loadPublicFarmLocation(farmerId);
    final buyerLookup = buyerPosition();
    final farm = await farmLookup;
    final buyerData = await buyerLookup ?? const <String, dynamic>{};
    // A saved position outside the Philippines (e.g. captured from an
    // emulator's default location) is not used: it would show a distance
    // of thousands of kilometres.
    final savedLat = (buyerData['latitude'] as num?)?.toDouble();
    final savedLng = (buyerData['longitude'] as num?)?.toDouble();
    final buyerOk = isValidPublicCoordinate(savedLat, savedLng);
    return (
      area: farm.area.isEmpty ? tl('Farm area unavailable') : farm.area,
      buyerLat: buyerOk ? savedLat : null,
      buyerLng: buyerOk ? savedLng : null,
      centerLat: farm.latitude,
      centerLng: farm.longitude,
    );
  }

  Widget _approximateFarmerMap(String? farmerId) {
    return FutureBuilder<
      ({
        String area,
        double? buyerLat,
        double? buyerLng,
        double? centerLat,
        double? centerLng,
      })
    >(
      // Cached (see initState): a rebuild must not reload the map.
      future: _farmerLocation,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Text(tl('Approximate farm area is unavailable.'));
        }
        final location = snapshot.data!;
        final hasBuyer = location.buyerLat != null && location.buyerLng != null;
        final hasCenter =
            location.centerLat != null && location.centerLng != null;
        final distanceKm = hasBuyer && hasCenter
            ? Geolocator.distanceBetween(
                    location.buyerLat!,
                    location.buyerLng!,
                    location.centerLat!,
                    location.centerLng!,
                  ) /
                  1000
            : null;

        if (!hasCenter) {
          return Text(
            tl('Farm area: {0}\nApproximate map is unavailable.', [
              location.area,
            ]),
          );
        }
        final center = LatLng(location.centerLat!, location.centerLng!);
        final buyer = hasBuyer
            ? LatLng(location.buyerLat!, location.buyerLng!)
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              location.area,
              style: TextStyle(color: AppColors.text, fontSize: 12.5),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Icon(Icons.route_outlined, size: 15, color: _muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    distanceKm == null
                        ? tl(
                            'Distance unavailable. Add a saved location to see an estimate.',
                          )
                        : _previewRoad != null
                        ? tl('Approx. {0} km by road', [
                            _previewRoad!.km.toStringAsFixed(1),
                          ])
                        : tl('Approx. {0} km away', [
                            distanceKm.toStringAsFixed(1),
                          ]),
                    style: TextStyle(color: _muted, fontSize: 11.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // A still preview: it does not move under a finger, so the page
            // scrolls past it. Tapping it opens Farm Location (the same as
            // Open Map above), with the distance and a refresh.
            SizedBox(
              key: _mapKey,
              height: 175,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      child: _farmAreaMap(center, buyer, preview: true),
                    ),
                    Positioned.fill(
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          key: const Key('farmMapPreview'),
                          onTap: _openFarmLocation,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // That the farm point is only the general area is said on the
            // map itself (FarmBuyerMap's note).
          ],
        );
      },
    );
  }

  // The farm's approximate area (and the buyer's saved location, if any)
  // on a map, the two as their photos with the line between them
  // (FarmBuyerMap). As a [preview] nothing moves it.
  Widget _farmAreaMap(LatLng center, LatLng? buyer, {bool preview = false}) {
    return FarmBuyerMap(
      farm: center,
      buyer: buyer,
      farmerId: _currentData['farmerId']?.toString() ?? '',
      farmerName: _currentData['farmerName']?.toString() ?? tl('Farmer'),
      preview: preview,
      zoom: 12,
      onRoute: preview
          ? (route) {
              if (mounted) setState(() => _previewRoad = route);
            }
          : null,
    );
  }

  // Farm Location full screen (the same as Open Map beside the section
  // title): the approximate area, the distance from the buyer, and a
  // refresh for it.
  void _openFarmLocation() {
    final farmerId = _currentData['farmerId']?.toString() ?? '';
    if (farmerId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BuyerMapView(
          farmerId: farmerId,
          farmerName: _currentData['farmerName']?.toString() ?? 'Farmer',
        ),
      ),
    );
  }

  Future<void> _refreshData() async {
    _watchProduct();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _productLoadError = false);
  }

  // ---- Image gallery with the back / heart / share buttons on top ----
  List<String> get _galleryUrls {
    final urls = <String>[
      if (_currentData['imageUrls'] is List)
        for (final url in _currentData['imageUrls'] as List)
          if (url != null && url.toString().isNotEmpty) url.toString(),
    ];
    if (urls.isEmpty && _imageUrl != null && _imageUrl!.isNotEmpty) {
      urls.add(_imageUrl!);
    }
    // A listing has at most five photos (see AddProductScreen.maxPhotos).
    return urls.take(5).toList();
  }

  // Opens the listing's photos full screen at [index], to swipe through,
  // zoom and save.
  void _openPhotos(int index) =>
      openPhotoGallery(context, _galleryUrls, initialIndex: index);

  Widget _networkImage(String url) => Image.network(
    url,
    fit: BoxFit.cover,
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : Center(child: CircularProgressIndicator(color: AppColors.brand)),
    errorBuilder: (context, error, stackTrace) => Container(
      color: AppColors.accent,
      child: Icon(Icons.broken_image, size: 90, color: AppColors.brand),
    ),
  );

  Widget _gallery(Map<String, dynamic> data) {
    final urls = _galleryUrls;
    // A stored (base64) photo, or no photo at all, is a single image.
    final single = _imageBytes != null || urls.length <= 1;

    return AspectRatio(
      aspectRatio: 1.15,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Tapping a photo opens it full screen (a stored photo, with no
          // address to open, stays as it is).
          if (single)
            GestureDetector(
              key: const Key('productPhoto'),
              onTap: urls.isEmpty || _imageBytes != null
                  ? null
                  : () => _openPhotos(0),
              child: _productImage(),
            )
          else
            PageView.builder(
              itemCount: urls.length,
              onPageChanged: (page) => _galleryPage.value = page,
              itemBuilder: (context, index) => GestureDetector(
                key: Key('productPhoto$index'),
                onTap: () => _openPhotos(index),
                child: _networkImage(urls[index]),
              ),
            ),
          // The content panel's rounded top edge, drawn over the foot of
          // the image so the photo curves into the white panel below.
          Positioned(
            left: 0,
            right: 0,
            bottom: -1,
            height: 27,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: AppColors.cardBorder,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
            ),
          ),
          if (!single)
            Positioned(
              bottom: 38,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<int>(
                valueListenable: _galleryPage,
                builder: (context, page, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < urls.length; i++)
                      Container(
                        width: i == page ? 18 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(
                            alpha: i == page ? 1 : 0.6,
                          ),
                          border: AppColors.cardBorder,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // Each button's 44 tap area holds a 36 circle, 4 in from its
          // sides: 8 + 4 puts the circles 12 from the screen's edges, and
          // two side by side 8 apart.
          Positioned(
            top: 0,
            left: 8,
            right: 8,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    // Back again over the photo (the user's picture,
                    // 2026-11-08); the bar at the top has its own.
                    circleButton(
                      Icons.arrow_back_rounded,
                      () => Navigator.maybePop(context),
                      key: const Key('productBack'),
                      tooltip: tl('Back'),
                    ),
                    const Spacer(),
                    // The heart — buyers only (it draws nothing otherwise).
                    SaveProductButton(productId: widget.productId),
                    Builder(
                      builder: (buttonContext) => circleButton(
                        Icons.share_outlined,
                        () => ProductShareService.share(
                          buttonContext,
                          widget.productId,
                          data,
                        ),
                        key: const Key('productShare'),
                        tooltip: tl('Share'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // The thin rule inside the white panel.
  Widget _divider({double top = 14, double bottom = 4}) => Padding(
    padding: EdgeInsets.only(top: top, bottom: bottom),
    child: Divider(height: 1, thickness: 1, color: _line),
  );

  // One fact of the summary: a dark green icon and the text, with an
  // optional note after it.
  // The listing's delivery coverage in full: the reach, every area under its
  // province, the fee, and whether it reaches the buyer's saved area.
  Widget _deliveryCoverageSection(Map<String, dynamic> data) {
    final coverage = DeliveryCoverage.fromProduct(data);
    final origin = coverage.origin.label;
    final groups = areasByProvince(coverage.areas);
    final reach = coverage.reach(BuyerAreaWatcher.instance.area);
    final lineStyle = TextStyle(
      fontSize: 12.5,
      height: 1.45,
      color: AppColors.text,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 19,
              color: AppColors.brand,
            ),
            const SizedBox(width: 8),
            Expanded(child: _sectionTitle(tl('Delivery Coverage'))),
          ],
        ),
        const SizedBox(height: 8),
        if (coverage.type == DeliveryCoverageType.sameBarangay)
          Text(
            coverage.originBarangay.isEmpty
                ? tl('Same barangay as the farm only ({0})', [origin])
                : tl('Barangay {0}, {1} only', [
                    coverage.originBarangay,
                    origin,
                  ]),
            style: lineStyle,
          )
        else if (coverage.type == DeliveryCoverageType.municipality)
          Text(tl('Anywhere in {0}', [origin]), style: lineStyle)
        else if (groups.isEmpty)
          Text(tl('Areas to be arranged with the farmer.'), style: lineStyle)
        else
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: g.province.isEmpty ? tl('Other areas') : g.province,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: ': ${g.towns.join(', ')}'),
                  ],
                ),
                style: lineStyle,
              ),
            ),
        const SizedBox(height: 6),
        _infoRow(
          Icons.payments_outlined,
          coverage.feeKnown
              ? tl('Delivery fee: {0}', [coverage.feeLabel])
              : tl('Delivery fee: to be arranged with the farmer'),
        ),
        if (reach != DeliveryReach.unknownLocation) ...[
          const SizedBox(height: 8),
          _infoRow(
            reach == DeliveryReach.covered
                ? Icons.check_circle_outline
                : Icons.info_outline,
            reach == DeliveryReach.covered
                ? tl('Delivers to your area')
                : tl(
                    'Your area is outside this coverage. Message the farmer to arrange delivery.',
                  ),
          ),
        ],
      ],
    );
  }

  Widget _infoRow(IconData icon, String text, {Widget? trailing}) => Row(
    children: [
      Icon(icon, size: 16, color: AppColors.brand),
      const SizedBox(width: 9),
      Flexible(
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.3,
            color: AppColors.grey(800),
          ),
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 6), trailing],
    ],
  );

  Widget _sectionTitle(String text) => Text(
    text,
    style: TextStyle(
      fontFamily: 'Montserrat',
      fontSize: 15.5,
      fontWeight: FontWeight.w700,
      color: AppColors.brand,
    ),
  );

  // The muted grey and the hairline of the design.
  Color get _muted =>
      AppColors.isDark ? AppColors.textSecondary : const Color(0xFF757575);
  Color get _line =>
      AppColors.isDark ? AppColors.hairline : const Color(0xFFE8E9E3);

  // "View All (1) >" / "Open Map >": dark green text with a chevron.
  Widget _textAction(String label, VoidCallback onTap, {Key? key}) =>
      TextButton(
        key: key,
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brand,
          padding: const EdgeInsets.only(left: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(0, 32),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      );

  // Compact farmer row — opens that farmer's public profile. Photo and
  // Verified status come from the public profile, never assumed.
  Widget _farmerRow(String? farmerId, String farmerName) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: _farmerProfile,
      builder: (context, snapshot) {
        final farmer = snapshot.data?.data();
        final verified = farmer?['approvalStatus'] == 'approved';
        final displayName =
            (farmer?['name'] ?? farmer?['fullName'] ?? farmerName).toString();

        // A plain row between two dividers, not a card: the whole row is
        // the tap target.
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: farmerId == null || farmerId.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          FarmerStorefrontScreen(farmerId: farmerId),
                    ),
                  ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  ProfileAvatar(
                    photoUrl: farmer?['photoUrl']?.toString(),
                    name: displayName,
                    radius: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // A pale green badge, only when the Admin has
                        // verified this farmer.
                        if (verified)
                          Container(
                            padding: const EdgeInsets.fromLTRB(6, 3, 10, 3),
                            decoration: BoxDecoration(
                              color: _paleGreen,
                              borderRadius: BorderRadius.circular(
                                AppTheme.pillRadius,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 15,
                                  color: AppColors.brand,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  tl('Verified Farmer'),
                                  style: TextStyle(
                                    color: AppColors.brand,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Text(
                            tl('Farmer'),
                            style: TextStyle(
                              color: AppColors.grey(700),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.brand,
                    size: 26,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Farmer's general area (barangay, municipality) under the price.
  Widget _farmerAreaLine() {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: _farmerProfile,
      builder: (context, snapshot) {
        final farmer = snapshot.data?.data();
        final area = [farmer?['barangay'], farmer?['municipality']]
            .map((v) => (v ?? '').toString().trim())
            .where((v) => v.isNotEmpty)
            .join(', ');
        if (area.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _infoRow(Icons.place_outlined, area),
        );
      },
    );
  }

  static const int _reviewsPreviewed = 6;

  // A short preview of this exact product's reviews, newest first: the
  // rating summary, "View All", then a row of compact cards to swipe
  // through. The full text, photos and replies are on ProductReviewsScreen.
  Widget _reviewsSection(String productName, String? farmerId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reviews,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(tl('Buyer Reviews')),
              const SizedBox(height: 12),
              Center(child: CircularProgressIndicator(color: AppColors.brand)),
            ],
          );
        }
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(tl('Buyer Reviews')),
              const SizedBox(height: 8),
              Text(
                tl('Could not load reviews.'),
                style: TextStyle(color: AppColors.grey(700), fontSize: 12.5),
              ),
            ],
          );
        }

        final docs = visibleProductReviews(snapshot.data);

        // No rating summary at all — a "0.0" would read as a bad score.
        if (docs.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(tl('Buyer Reviews')),
              const SizedBox(height: 10),
              Text(
                tl('No reviews yet'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                tl(
                  'Be the first to review this product after completing an order.',
                ),
                style: TextStyle(
                  color: AppColors.grey(700),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          );
        }

        final average = averageReviewRating(docs);
        final shown = docs.take(_reviewsPreviewed).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle(tl('Buyer Reviews')),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 19,
                            color: DockedNavBar.selectedColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            average.toStringAsFixed(1),
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            docs.length == 1
                                ? '(1 review)'
                                : tl('({0} reviews)', [docs.length]),
                            style: TextStyle(fontSize: 11.5, color: _muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _textAction(
                  tl('View All ({0})', [docs.length]),
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProductReviewsScreen(
                        productId: widget.productId,
                        productName: productName,
                        farmerId: farmerId,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // One review fills the card's width; more slide sideways.
            if (shown.length == 1)
              _reviewPreviewCard(shown.first.id, shown.first.data())
            else
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) => SizedBox(
                    width: 260,
                    child: _reviewPreviewCard(
                      shown[index].id,
                      shown[index].data(),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // Compact on purpose: name, stars, date and a few lines of the text, on
  // a light cream card. No photos here — those are on the full reviews
  // screen.
  Widget _reviewPreviewCard(String reviewId, Map<String, dynamic> review) {
    final reviewer = review['buyerName']?.toString() ?? 'Buyer';
    final text = review['comment']?.toString() ?? '';
    final rating = (review['rating'] as num?)?.toDouble() ?? 0;
    final created = (review['createdAt'] as Timestamp?)?.toDate();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.isDark
            ? AppColors.surfaceAlt
            : const Color(0xFFF6F4EC),
        border: AppColors.cardBorder,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // The reviewer's photo (initials without one).
              ReviewerAvatar(
                buyerId: review['buyerId']?.toString(),
                name: reviewer,
                radius: 17,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reviewer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        ReviewStars(rating: rating, size: 14),
                        if (created != null) ...[
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '· ${DateFormat('MMM d, y').format(created)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: _muted),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              ReviewLikeButton(reviewId: reviewId, review: review),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text.isEmpty ? tl('No written review.') : text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: text.isEmpty ? _muted : AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _currentData;

    if (_productLoadError || _productUnavailable) {
      return Scaffold(
        appBar: AgriAppBar(title: tl('Product Details')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _productLoadError
                      ? tl(
                          'Could not load this product. Check your connection and try again.',
                        )
                      : tl('This listing is no longer available.'),
                  textAlign: TextAlign.center,
                ),
                if (_productLoadError) ...[
                  const SizedBox(height: 12),
                  TextButton(onPressed: _refreshData, child: Text(tl('Retry'))),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: SectionTabs.background,
      // The page, and only the Order Now / Message bar fixed below it: no
      // bar of tabs at the top (the user's choice, 2026-11-08).
      body: _content(context, data),
      bottomNavigationBar: _bottomBar(data),
    );
  }

  Widget _content(BuildContext context, Map<String, dynamic> data) {
    final name = data['name']?.toString() ?? 'Unnamed';
    final category = listingCategory(data);
    final price = (data['retailPrice'] as num?) ?? (data['price'] as num?) ?? 0;
    final wholesalePrice = (data['wholesalePrice'] as num?)?.toDouble();
    final wholesaleMinimum = (data['wholesaleMinimumQuantity'] as num?) ?? 1;
    // None for livestock sold per head or piece (listingHasWholesale).
    final wholesaleEnabled = listingHasWholesale(data);
    final hasWholesale =
        wholesaleEnabled && wholesalePrice != null && wholesalePrice > 0;
    // A buyer who orders in bulk sees the wholesale price first, unless the
    // stock is below the minimum and it cannot be ordered at that price.
    final wholesaleFirst =
        hasWholesale &&
        BuyerTypeWatcher.instance.wholesaleFirst &&
        ((data['quantity'] as num?) ?? 0) >= wholesaleMinimum;
    final available = (data['quantity'] as num?) ?? 0;
    final unit = (data['unit'] as String?) ?? unitForProductName(name);
    final description = data['description']?.toString() ?? '';
    final farmerName = data['farmerName']?.toString() ?? 'Farmer';
    final farmerId = data['farmerId']?.toString();
    final delivery = data['deliveryAvailable'] == true;
    final pickup = data['pickupOnly'] == true;
    final rating = (data['rating'] as num?)?.toDouble();
    final reviewCount = (data['reviewCount'] as num?)?.toInt() ?? 0;
    final postedOn = _formatDate(data['createdAt']);
    final updatedOn = _formatDate(data['updatedAt']);
    final harvested = harvestDateOf(data);

    // The summary's two halves: name, price and rating on the left; the
    // facts on the right (stacked on a narrow phone).
    final headline = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (category.isNotEmpty) ...[
          // The category alone: no icon on a category badge anywhere (the
          // user, 2026-11-08).
          Container(
            key: const Key('productCategoryPill'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _paleGreen,
              borderRadius: BorderRadius.circular(AppTheme.pillRadius),
            ),
            child: Text(
              category,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.brand,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          withSellingOption(name, data),
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 20,
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: AppColors.brand,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 6,
          runSpacing: 2,
          children: [
            Text(
              formatPeso(wholesaleFirst ? wholesalePrice : price),
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 23,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: AppColors.brand,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '/ $unit',
                style: TextStyle(fontSize: 13, color: _muted),
              ),
            ),
          ],
        ),
        // Only once the product actually has reviews.
        if (rating != null && reviewCount > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.star_rounded,
                size: 16,
                color: DockedNavBar.selectedColor,
              ),
              const SizedBox(width: 4),
              Text(
                rating.toStringAsFixed(1),
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  reviewCount == 1
                      ? '(1 review)'
                      : tl('({0} reviews)', [reviewCount]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ],
      ],
    );
    final facts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow(
          Icons.inventory_2_outlined,
          available <= 0
              ? tl('Out of stock')
              // Livestock sold by the animal shows "Available", not how
              // many are left (system testing, 2026-11-09).
              : isSoldPerAnimal(data)
              ? tl('Available')
              : tl('{0} available', [formatStock(available, unit)]),
        ),
        if (available <= 0)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.tone(Colors.red, 50),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.tone(Colors.red, 200)),
              ),
              child: Text(
                tl('OUT OF STOCK'),
                style: TextStyle(
                  color: AppColors.tone(Colors.red, 700),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        _farmerAreaLine(),
        const SizedBox(height: 10),
        _infoRow(
          Icons.sell_outlined,
          hasWholesale ? tl('Retail and wholesale') : tl('Retail only'),
        ),
        // Fulfillment, as one plain line with the rest of the summary.
        if (delivery || pickup) ...[
          const SizedBox(height: 10),
          _infoRow(
            Icons.local_shipping_outlined,
            delivery && pickup
                ? tl('Delivery and pick-up')
                : delivery
                ? 'Delivery'
                : 'Pick-up',
          ),
        ],
        if (harvested != null) ...[
          const SizedBox(height: 10),
          _infoRow(Icons.eco_outlined, harvestLabel(harvested)),
        ],
      ],
    );

    return AgriRefreshIndicator(
      color: AppColors.brand,
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        // Clear of the sticky Order Now / Message bar.
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _gallery(data),

            // The white panel the photo curves into (its top edge is drawn
            // over the photo, see _gallery), with rounded lower corners on
            // the cream page: the product, wholesale and the farmer.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(22),
                ),
                boxShadow: AppColors.isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 330) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            headline,
                            const SizedBox(height: 14),
                            facts,
                          ],
                        );
                      }
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 9, child: headline),
                            Container(
                              width: 1,
                              margin: const EdgeInsets.fromLTRB(8, 16, 12, 4),
                              color: _line,
                            ),
                            Expanded(
                              flex: 11,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: facts,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (harvested != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      [
                        if (isRecentlyHarvested(harvested))
                          '${tl('Recently Harvested')}.',
                        if (data['updatedAt'] is Timestamp)
                          tl('Last updated {0}.', [
                            DateFormat(
                              'MMM d, y',
                            ).format((data['updatedAt'] as Timestamp).toDate()),
                          ]),
                        tl(
                          'Harvest information is provided and updated by the farmer.',
                        ),
                      ].join(' '),
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: _muted,
                      ),
                    ),
                  ],

                  // ---- Wholesale: a pale green banner ----
                  if (hasWholesale) ...[
                    const SizedBox(height: 14),
                    _PaleNote(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.widgets_outlined,
                            size: 24,
                            color: AppColors.brand,
                          ),
                          Container(
                            width: 1,
                            height: 30,
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            color: AppColors.brand.withValues(alpha: 0.3),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tl('Wholesale available'),
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.brand,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  wholesaleFirst
                                      ? tl(
                                          'Wholesale price for orders of {0} or more. Retail price: {1}',
                                          [
                                            formatStock(wholesaleMinimum, unit),
                                            formatPriceWithUnit(price, unit),
                                          ],
                                        )
                                      : tl('{0} for orders of {1} or more', [
                                          formatPriceWithUnit(
                                            wholesalePrice,
                                            unit,
                                          ),
                                          formatStock(wholesaleMinimum, unit),
                                        ]),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.35,
                                    color: AppColors.grey(800),
                                  ),
                                ),
                                if (available < wholesaleMinimum) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    tl(
                                      'Wholesale is temporarily unavailable because current stock is below the minimum.',
                                    ),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.tone(Colors.orange, 800),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ---- Farmer ----
                  _divider(),
                  _farmerRow(farmerId, farmerName),
                ],
              ),
            ),

            // ---- The row of tabs: chooses what shows below ----
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: SectionTabs(
                labels: _tabLabels,
                active: _activeTab,
                onTap: _chooseTab,
              ),
            ),
            const SizedBox(height: 10),

            // ---- Description ----
            if (_shows(1)) ...[
              _SectionCard(
                key: const Key('descriptionSection'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(tl('Description')),
                    const SizedBox(height: 8),
                    Text(
                      description.isEmpty
                          ? tl('No description provided.')
                          : description,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.55,
                        color: description.isEmpty ? _muted : AppColors.text,
                      ),
                    ),
                    if (postedOn != null || updatedOn != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        [
                          if (postedOn != null) tl('Posted on {0}', [postedOn]),
                          if (updatedOn != null)
                            tl('Updated on {0}', [updatedOn]),
                        ].join('\n'),
                        style: TextStyle(
                          color: _muted,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ---- Reviews for this product ----
            if (_shows(2)) ...[
              _SectionCard(
                key: const Key('reviewsSection'),
                child: _reviewsSection(name, farmerId),
              ),
              const SizedBox(height: 12),
            ],

            // ---- Where the farmer delivers (system testing, 2026-11-09:
            // the coverage shown clearly): part of the Overview ----
            if (_activeTab == 0 && delivery) ...[
              _SectionCard(
                key: const Key('deliveryCoverageSection'),
                child: _deliveryCoverageSection(data),
              ),
              const SizedBox(height: 12),
            ],

            // ---- Approximate farm area (never the exact pin): part of the
            // Overview ----
            if (_activeTab == 0) ...[
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 19,
                          color: AppColors.brand,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _sectionTitle(tl('Farm Location'))),
                        // The approximate-area map, full screen.
                        if (farmerId != null && farmerId.isNotEmpty)
                          _textAction(tl('Open Map'), _openFarmLocation),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _approximateFarmerMap(farmerId),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ---- Other listings of the same product ----
            if (_shows(3))
              KeyedSubtree(
                key: const Key('recommendedSection'),
                child: _recommendedSection(name),
              ),
          ],
        ),
      ),
    );
  }

  // The four tabs.
  List<String> get _tabLabels => [
    tl('Overview'),
    tl('Description'),
    tl('Reviews'),
    tl('Recommended'),
  ];

  // The pale green of the design's badges and banners.
  Color get _paleGreen =>
      AppColors.isDark ? AppColors.tint : const Color(0xFFEAF2E4);

  // ---- Order Now (outlined) | Message (filled, on the right) ----
  // Two buttons of the same size filling the bar's width; Message,
  // the dark green one, is the main action (buyers talk to the farmer first).
  // No Map here: the Farm Location section above has Open Map.
  // Sticky: it is the Scaffold's bottom bar, so it never scrolls away.
  Widget _bottomBar(Map<String, dynamic> data) {
    final name = data['name']?.toString() ?? 'Unnamed';
    final price = (data['retailPrice'] as num?) ?? (data['price'] as num?) ?? 0;
    final available = (data['quantity'] as num?) ?? 0;
    final unit = (data['unit'] as String?) ?? unitForProductName(name);
    final farmerName = data['farmerName']?.toString() ?? 'Farmer';
    final farmerId = data['farmerId']?.toString();
    final delivery = data['deliveryAvailable'] == true;
    final pickup = data['pickupOnly'] == true;
    final canContact = farmerId != null && farmerId.isNotEmpty;
    final canOrder = available > 0 && canContact;

    // Compact, fixed under the page, in BarActionStyle (the user's sizes,
    // 2026-11-08; the same as Order Details' Review / View Receipt): 46
    // high, 13 labels, 18 icons, 7 between them. The icon gold on the
    // filled Message, dark green on the white Order Now; grey while off.
    Widget label(
      IconData icon,
      String text, {
      required bool on,
      required bool filled,
    }) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: BarActionStyle.iconSize,
          color: !on
              ? AppColors.grey(500)
              : filled
              ? BarActionStyle.gold
              : BarActionStyle.line,
        ),
        const SizedBox(width: BarActionStyle.gap),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BarActionStyle.label,
          ),
        ),
      ],
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(BarActionStyle.radius),
    );

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
        color: SectionTabs.background,
        child: Row(
          children: [
            _actionSlot(
              OutlinedButton(
                key: const Key('orderNow'),
                onPressed: !canOrder
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlaceOrderScreen(
                            sellerId: farmerId,
                            sellerName: farmerName,
                            productId: widget.productId,
                            productName: name,
                            productPrice: formatPriceWithUnit(price, unit),
                            productImage: _imageUrl ?? '',
                            deliveryAvailable: delivery,
                            pickupAvailable: pickup,
                            unit: unit,
                          ),
                        ),
                      ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BarActionStyle.line,
                  backgroundColor: AppColors.surface,
                  disabledForegroundColor: AppColors.grey(500),
                  side: BorderSide(
                    color: canOrder ? BarActionStyle.line : AppColors.grey(300),
                    width: 1.2,
                  ),
                  minimumSize: const Size.fromHeight(_actionHeight),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: shape,
                ),
                child: label(
                  available > 0 ? Icons.shopping_bag_outlined : Icons.block,
                  available > 0 ? tl('Order Now') : tl('Out of Stock'),
                  on: canOrder,
                  filled: false,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _actionSlot(
              ElevatedButton(
                key: const Key('messageFarmer'),
                onPressed: canOrder
                    ? () => _messageFarmer(farmerId, farmerName, name)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: BarActionStyle.fill,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.grey(300),
                  disabledForegroundColor: AppColors.grey(600),
                  elevation: 0,
                  minimumSize: const Size.fromHeight(_actionHeight),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: shape,
                ),
                child: label(
                  Icons.chat_bubble_outline_rounded,
                  tl('Message'),
                  on: canOrder,
                  filled: true,
                ),
              ),
              key: _messageKey,
            ),
          ],
        ),
      ),
    );
  }

  // One height for every action on this screen; the buttons are rounded
  // rectangles of it.
  static const double _actionHeight = BarActionStyle.height;

  // A bottom-bar button: the two share the bar's whole width equally, so
  // there is no empty space beside them.
  Widget _actionSlot(Widget button, {Key? key}) => Expanded(
    key: key,
    child: SizedBox(width: double.infinity, child: button),
  );

  Future<void> _messageFarmer(
    String farmerId,
    String farmerName,
    String productName,
  ) async {
    if (!mounted) return;

    final currentUserId = FirebaseRefs.auth.currentUser?.uid ?? '';

    if (currentUserId.isEmpty || farmerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar(
          tl('Unable to message this farmer. Try again later.'),
          kind: MessageKind.error,
        ),
      );
      return;
    }

    final messageService = MessageService();
    final conversationId = messageService.conversationIdFor(
      currentUserId,
      farmerId,
    );

    try {
      await messageService.startOrGetConversation(
        otherUserId: farmerId,
        otherUserName: farmerName,
        productId: widget.productId,
        productName: productName,
        productImageUrl: _imageUrl ?? '',
        retailPrice:
            (widget.data['retailPrice'] as num?) ??
            (widget.data['price'] as num?) ??
            0,
        wholesalePrice: widget.data['wholesalePrice'] as num?,
        wholesaleMinimumQuantity:
            (widget.data['wholesaleMinimumQuantity'] as num?)?.toInt() ?? 1,
        retailMaximumQuantity:
            (widget.data['retailMaximumQuantity'] as num?)?.toInt() ?? 1,
        unit:
            (widget.data['unit'] as String?) ?? unitForProductName(productName),
        deliveryAvailable: widget.data['deliveryAvailable'] == true,
        pickupOnly: widget.data['pickupOnly'] == true,
      );
    } catch (_) {
      // Swallow chat creation errors and continue to the chat view.
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        // The same Messages screen as everywhere else, with this product
        // on top — one conversation, one look (it was a separate screen).
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          otherUserId: farmerId,
          otherUserName: farmerName,
          productId: widget.productId,
          productName: productName,
          productImageUrl: _imageUrl,
          retailPrice:
              (widget.data['retailPrice'] as num?) ??
              (widget.data['price'] as num?),
          wholesalePrice: widget.data['wholesalePrice'] as num?,
          wholesaleMinimumQuantity:
              (widget.data['wholesaleMinimumQuantity'] as num?)?.toInt() ?? 1,
          retailMaximumQuantity:
              (widget.data['retailMaximumQuantity'] as num?)?.toInt() ?? 1,
        ),
      ),
    );
  }

  // A round button over the photo (the user's sizes, 2026-11-08): a 36
  // white circle at 95% on a very soft shadow, an 18 dark green icon, and
  // a 44 tap area around it (the circle stays 36).
  Widget circleButton(
    IconData icon,
    VoidCallback onTap, {
    Key? key,
    String? tooltip,
  }) {
    final circle = Material(
      color: AppColors.surface.withValues(alpha: 0.95),
      shape: const CircleBorder(),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(
          dimension: SaveProductButton.size,
          child: Icon(
            icon,
            color: AppColors.isDark ? AppColors.brand : const Color(0xFF0B4225),
            size: SaveProductButton.iconSize,
          ),
        ),
      ),
    );
    final button = GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(
        dimension: SaveProductButton.tapTarget,
        child: Center(child: circle),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// A white rounded card on the cream page, 16 in from the sides (the
/// user's picture of Product Details, 2026-11-08).
class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: AppColors.cardBorder,
        boxShadow: AppColors.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );
  }
}

/// A pale green rounded note (the wholesale banner, the empty
/// recommendations), with a small sprout and field drawn faintly at its
/// right.
class _PaleNote extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final AlignmentGeometry alignment;

  const _PaleNote({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        color: AppColors.isDark ? AppColors.tint : const Color(0xFFEEF4E8),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              bottom: 0,
              width: 96,
              height: 44,
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: AppColors.isDark ? 0.35 : 0.9,
                  child: const CustomPaint(painter: SproutFieldPainter()),
                ),
              ),
            ),
            Padding(
              padding: padding.copyWith(right: padding.right + 30),
              child: Align(alignment: alignment, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small sprout over curved field rows, for the corner of a pale note.
class SproutFieldPainter extends CustomPainter {
  const SproutFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Field rows, curving up to the right.
    final row = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = h * (0.55 + i * 0.16);
      row
        ..color = Color(i.isEven ? 0xFF9CCB6E : 0xFFC4E09F)
        ..strokeWidth = 4;
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.05, h + 2)
          ..quadraticBezierTo(w * 0.5, y + h * 0.1, w + 2, y - h * 0.2),
        row,
      );
    }
    // The sprout.
    final stem = Paint()
      ..color = const Color(0xFF5E9E33)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final sx = w * 0.62;
    canvas.drawLine(Offset(sx, h * 0.62), Offset(sx, h * 0.28), stem);
    final leaf = Paint()..color = const Color(0xFF6FB043);
    canvas.drawPath(
      Path()
        ..moveTo(sx, h * 0.34)
        ..quadraticBezierTo(sx - w * 0.16, h * 0.04, sx - w * 0.22, h * 0.22)
        ..quadraticBezierTo(sx - w * 0.10, h * 0.40, sx, h * 0.34),
      leaf,
    );
    canvas.drawPath(
      Path()
        ..moveTo(sx, h * 0.30)
        ..quadraticBezierTo(sx + w * 0.14, h * -0.02, sx + w * 0.22, h * 0.12)
        ..quadraticBezierTo(sx + w * 0.12, h * 0.34, sx, h * 0.30),
      leaf,
    );
  }

  @override
  bool shouldRepaint(SproutFieldPainter oldDelegate) => false;
}
