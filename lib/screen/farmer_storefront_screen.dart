import 'dart:math' as math;

import '../services/firebase_refs.dart';
import '../widgets/review_like_button.dart';
import '../widgets/reviewer_avatar.dart';
import '../theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/saved_products_service.dart';
import '../widgets/chat_photo_viewer.dart' show openPhotoGallery;
import 'product_reviews_screen.dart'
    show
        ProductReviewsScreen,
        ReviewStars,
        averageReviewRating,
        visibleProductReviews;
import '../widgets/explore_product_card.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/save_product_button.dart';
import 'product_detail_screen.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

/// A farmer's public profile, as a buyer sees it: photo, name, general
/// location and Verified Farmer badge, then what buyers said (the rating
/// over all their products, the latest two reviews and See all), then their
/// active listings in a two-column grid. Everything comes from
/// publicProfiles/{farmerId} (the allow-listed projection — no email, phone
/// or exact location), the farmer's own products and their reviews.
class FarmerStorefrontScreen extends StatefulWidget {
  final String farmerId;

  const FarmerStorefrontScreen({super.key, required this.farmerId});

  @override
  State<FarmerStorefrontScreen> createState() => _FarmerStorefrontScreenState();
}

class _FarmerStorefrontScreenState extends State<FarmerStorefrontScreen> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _profile =
      FirebaseRefs.firestore
          .collection('publicProfiles')
          .doc(widget.farmerId)
          .snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _products =
      FirebaseRefs.firestore
          .collection('products')
          .where('farmerId', isEqualTo: widget.farmerId)
          .snapshots();
  // Every review of this farmer's products (reviews are open to read).
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _reviews = FirebaseRefs
      .firestore
      .collection('productReviews')
      .where('sellerId', isEqualTo: widget.farmerId)
      .snapshots();

  // The heart on each card (buyers only) — the shared LikedProducts state,
  // the same one Explore, Search and Product Details use.
  void _onLikesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    LikedProducts.instance
      ..start()
      ..addListener(_onLikesChanged);
  }

  @override
  void dispose() {
    LikedProducts.instance.removeListener(_onLikesChanged);
    super.dispose();
  }

  // The farmer's active listings (not archived, not hidden).
  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _active(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) => (snapshot?.docs ?? const [])
      .where(
        (doc) =>
            doc.data()['isArchived'] != true &&
            doc.data()['isSuspended'] != true,
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    // The user's design (2026-11-08): no app bar — a Back over a drawn
    // cover, the photo in a full gold ring, name, place and badge, a thin
    // line, then the reviews (with their rating) and the products.
    return Scaffold(
      backgroundColor: AppColors.page,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _profile,
        builder: (context, profileSnap) {
          if (profileSnap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            );
          }
          final profile = profileSnap.data?.data();
          if (profileSnap.hasError || profile == null) {
            return SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _backButton(),
                  Expanded(
                    child: Center(
                      child: Text(tl('Farmer profile is unavailable.')),
                    ),
                  ),
                ],
              ),
            );
          }
          final farmerName =
              (profile['name'] ?? profile['fullName'] ?? tl('Farmer'))
                  .toString();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _reviews,
            builder: (context, reviewSnap) =>
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _products,
                  builder: (context, productSnap) {
                    final reviews = reviewSnap.hasData
                        ? visibleProductReviews(reviewSnap.data)
                        : null;
                    final products = productSnap.hasData
                        ? _active(productSnap.data)
                        : null;
                    return ListView(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom + 28,
                      ),
                      children: [
                        _header(profile),
                        const SizedBox(height: 16),
                        // A thin line closes the profile header.
                        Divider(
                          key: const Key('storefrontDivider'),
                          height: 1,
                          thickness: 1,
                          indent: 16,
                          endIndent: 16,
                          color: _line,
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _reviewsSection(
                            farmerName,
                            reviews,
                            reviewSnap.hasError,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _productsSection(
                            products,
                            productSnap.hasError,
                          ),
                        ),
                      ],
                    );
                  },
                ),
          );
        },
      ),
    );
  }

  Widget _backButton() => Padding(
    padding: const EdgeInsets.only(left: 4, top: 4),
    child: IconButton(
      key: const Key('storefrontBack'),
      tooltip: tl('Back'),
      onPressed: () => Navigator.maybePop(context),
      icon: Icon(Icons.arrow_back_rounded, color: AppColors.brand, size: 24),
    ),
  );

  Color get _muted =>
      AppColors.isDark ? AppColors.textSecondary : const Color(0xFF757575);
  Color get _line =>
      AppColors.isDark ? AppColors.hairline : const Color(0xFFE8E9E3);

  // A section's title: a small dark green icon and the words.
  Widget _sectionTitle(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 18, color: AppColors.brand),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: AppColors.brand,
          ),
        ),
      ),
    ],
  );

  Widget _header(Map<String, dynamic> profile) {
    final name = (profile['name'] ?? profile['fullName'] ?? tl('Farmer'))
        .toString();
    // General area only — the public profile never holds an exact location.
    final location = [profile['barangay'], profile['municipality']]
        .map((v) => (v ?? '').toString().trim())
        .where((v) => v.isNotEmpty)
        .join(', ');
    final bio = (profile['bio'] ?? '').toString().trim();
    final verified = profile['approvalStatus'] == 'approved';

    final photoUrl = (profile['photoUrl'] ?? '').toString();
    final topInset = MediaQuery.paddingOf(context).top;
    // A compact cover; the photo stands on its lower part.
    const landscape = 118.0;
    const photo = 92.0;
    return Column(
      children: [
        // The landscape across the top, Back over it, the photo standing
        // half on it.
        SizedBox(
          height: topInset + landscape + photo / 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: topInset + landscape,
                child: ExcludeSemantics(
                  child: CustomPaint(
                    painter: ProfileLandscapePainter(
                      topInset: topInset,
                      dark: AppColors.isDark,
                    ),
                  ),
                ),
              ),
              Positioned(top: topInset, left: 0, child: _backButton()),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Center(
                  // The photo opens full screen when there is one.
                  child: GestureDetector(
                    key: const Key('storefrontPhoto'),
                    onTap: photoUrl.isEmpty
                        ? null
                        : () => openPhotoGallery(context, [photoUrl]),
                    child: _FramedPhoto(
                      photoUrl: photoUrl.isEmpty ? null : photoUrl,
                      name: name,
                      size: photo,
                      verified: verified,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 19.5,
              fontWeight: FontWeight.w700,
              color: AppColors.brand,
            ),
          ),
        ),
        if (location.isNotEmpty) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_on_outlined, size: 14, color: _muted),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: _muted),
                  ),
                ),
              ],
            ),
          ),
        ],
        // Only when the Admin has verified this farmer.
        if (verified) ...[
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.fromLTRB(9, 5, 12, 5),
            decoration: BoxDecoration(
              color: AppColors.isDark
                  ? AppColors.tint
                  : const Color(0xFFEAF2E4),
              borderRadius: BorderRadius.circular(AppTheme.pillRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, size: 14, color: AppColors.brand),
                const SizedBox(width: 5),
                Text(
                  tl('Verified Farmer'),
                  style: TextStyle(
                    color: AppColors.brand,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              bio,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, height: 1.45, color: _muted),
            ),
          ),
        ],
      ],
    );
  }

  Widget _productsSection(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? products,
    bool failed,
  ) {
    if (products == null) {
      if (failed) return _note(tl('Could not load this farmer’s products.'));
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          Icons.inventory_2_outlined,
          tl('Products ({0})', [products.length]),
        ),
        const SizedBox(height: 12),
        if (products.isEmpty)
          _note(tl('No active products right now.'))
        else
          _grid(products),
      ],
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: TextStyle(fontSize: 12, color: _muted)),
  );

  Widget _grid(List<QueryDocumentSnapshot<Map<String, dynamic>>> products) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final cardWidth = (constraints.maxWidth - spacing) / 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: ExploreProductCard.extentFor(
              cardWidth,
              MediaQuery.textScalerOf(context),
              showFarmer: false,
            ),
          ),
          itemBuilder: (context, index) {
            final doc = products[index];
            final data = doc.data();
            return ExploreProductCard(
              data: data,
              // Every card here is this farmer's — no need to repeat it.
              showFarmer: false,
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
          },
        );
      },
    );
  }

  // ---- Reviews: what buyers said about this farmer's products ----

  Widget _reviewsSection(
    String farmerName,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? reviews,
    bool failed,
  ) {
    if (reviews == null) {
      if (failed) return _note(tl('Could not load this farmer’s reviews.'));
      return const SizedBox.shrink();
    }
    void seeAll() => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductReviewsScreen(
          productId: null,
          productName: farmerName,
          farmerId: widget.farmerId,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _sectionTitle(
                Icons.rate_review_outlined,
                tl('Reviews ({0})', [reviews.length]),
              ),
            ),
            // Plain muted dark green text with a small chevron.
            if (reviews.isNotEmpty)
              InkWell(
                key: const Key('storefrontSeeAllReviews'),
                onTap: seeAll,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 0, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tl('See all'),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brand.withValues(alpha: 0.75),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 17,
                        color: AppColors.brand.withValues(alpha: 0.75),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (reviews.isNotEmpty) ...[
          const SizedBox(height: 4),
          _ratingSummary(reviews),
        ],
        const SizedBox(height: 10),
        if (reviews.isEmpty)
          _note(tl('No reviews yet.'))
        else
          // The latest two; the rest under See all.
          for (final doc in reviews.take(2)) ...[
            _reviewCard(doc.id, doc.data()),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  // The farmer's real average, gold stars and how many reviews it is from.
  Widget _ratingSummary(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> reviews,
  ) {
    final average = averageReviewRating(reviews);
    return Row(
      key: const Key('storefrontRatingSummary'),
      children: [
        Text(
          average.toStringAsFixed(1),
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.brand,
          ),
        ),
        const SizedBox(width: 6),
        ReviewStars(rating: average, size: 15),
        const SizedBox(width: 6),
        Text(
          reviews.length == 1
              ? tl('(1 review)')
              : tl('({0} reviews)', [reviews.length]),
          style: TextStyle(fontSize: 11.5, color: _muted),
        ),
      ],
    );
  }

  Widget _reviewCard(String reviewId, Map<String, dynamic> review) {
    final reviewer = (review['buyerName'] ?? tl('Buyer')).toString();
    final rating = (review['rating'] as num?)?.toDouble() ?? 0;
    final comment = (review['comment'] ?? '').toString().trim();
    final product = (review['productName'] ?? '').toString().trim();
    final created = (review['createdAt'] as Timestamp?)?.toDate();
    final single = (review['imageUrl'] ?? '').toString();
    final photos = <String>[
      if (single.isNotEmpty) single,
      if (review['imageUrls'] is List)
        for (final url in review['imageUrls'] as List)
          if ((url ?? '').toString().isNotEmpty && url.toString() != single)
            url.toString(),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The reviewer's photo (initials without one).
              ReviewerAvatar(
                buyerId: review['buyerId']?.toString(),
                name: reviewer,
                radius: 19,
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
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        ReviewStars(rating: rating, size: 13),
                        if (created != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '· ${DateFormat('MMM d, y').format(created)}',
                            style: TextStyle(fontSize: 10.5, color: _muted),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Other buyers like the review here.
              ReviewLikeButton(reviewId: reviewId, review: review),
            ],
          ),
          if (product.isNotEmpty) ...[
            const SizedBox(height: 6),
            // "Reviewed:" in grey, the product in dark green.
            Text.rich(
              TextSpan(
                text: '${tl('Reviewed:')} ',
                style: TextStyle(fontSize: 11.5, color: _muted),
                children: [
                  TextSpan(
                    text: product,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.brand,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              comment,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.grey(800),
              ),
            ),
          ],
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () =>
                      openPhotoGallery(context, photos, initialIndex: i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      photos[i],
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 56,
                        height: 56,
                        color: AppColors.accent,
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 18,
                          color: AppColors.brand,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The farmer's photo inside a full gold circle with a thin white ring, on
/// a soft shadow, and — only for a verified farmer — a small dark green
/// shield with a white check at its lower right.
class _FramedPhoto extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final double size;
  final bool verified;

  const _FramedPhoto({
    required this.photoUrl,
    required this.name,
    required this.size,
    required this.verified,
  });

  // The gold circle's width and the white gap between it and the photo.
  static const double _ring = 2.5;
  static const double _gap = 2.5;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // A full gold circle, a thin white ring inside it, then the photo.
          Container(
            key: const Key('storefrontGoldRing'),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0xFFF5BB24), width: _ring),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(_gap),
            child: ProfileAvatar(
              photoUrl: photoUrl,
              name: name,
              radius: size / 2 - _ring - _gap,
            ),
          ),
          if (verified)
            Positioned(
              right: 0,
              bottom: 2,
              child: Container(
                key: const Key('storefrontVerifiedBadge'),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B4225),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The cover of a farmer's public profile: a warm cream sky with a faint
/// gold glow high in the middle, three soft layers of rolling hills with a
/// few faint field lines following their curves, and two small sprigs of
/// leaves at the outer top corners, fading into the page at its foot.
class ProfileLandscapePainter extends CustomPainter {
  /// The status bar's height: the scene is laid out below it.
  final double topInset;

  /// The sky fades in from the page at the top, for a cover that starts
  /// under a header (the Buyer Profile) rather than at the screen's top:
  /// no edge where the header ends and the cover begins.
  final bool softTop;

  /// The Dark Mode scene: deep forest greens and a fainter glow. Callers
  /// pass [AppColors.isDark].
  final bool dark;

  const ProfileLandscapePainter({
    this.topInset = 0,
    this.softTop = false,
    this.dark = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final s = h - topInset;
    double y(double f) => topInset + s * f;
    Paint shaded(Rect rect, int from, int to) =>
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(from), Color(to)],
          ).createShader(rect);

    // A warm cream sky, a touch deeper at the top.
    final sky = Offset.zero & size;
    canvas.drawRect(
      sky,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              const Color(0xFFF5BB24).withValues(alpha: dark ? 0.03 : 0.07),
              AppColors.page,
            ),
            AppColors.page,
          ],
        ).createShader(sky),
    );

    // A very light golden glow near the top centre.
    final glowAt = Offset(w * 0.5, y(0.08));
    final glowRadius = w * 0.42;
    canvas.drawCircle(
      glowAt,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFF5BB24).withValues(alpha: dark ? 0.07 : 0.16),
            const Color(0xFFF5BB24).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: glowAt, radius: glowRadius)),
    );

    if (softTop) {
      final top = Rect.fromLTRB(0, 0, w, h * 0.45);
      canvas.drawRect(
        top,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.page, AppColors.page.withValues(alpha: 0)],
          ).createShader(top),
      );
    }

    // Far hills: the palest, highest layer.
    final far = Path()
      ..moveTo(0, y(0.60))
      ..cubicTo(w * 0.16, y(0.46), w * 0.34, y(0.47), w * 0.50, y(0.56))
      ..cubicTo(w * 0.66, y(0.64), w * 0.82, y(0.43), w, y(0.50))
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      far,
      shaded(
        Rect.fromLTRB(0, y(0.44), w, h),
        dark ? 0xFF1C3226 : 0xFFE2EDD2,
        dark ? 0xFF1F382A : 0xFFD2E5BB,
      ),
    );

    // Middle hills, with two faint field lines that follow their curve.
    Path midLine(double dy) => Path()
      ..moveTo(0, y(0.71 + dy))
      ..cubicTo(
        w * 0.20,
        y(0.60 + dy),
        w * 0.42,
        y(0.63 + dy),
        w * 0.60,
        y(0.73 + dy),
      )
      ..cubicTo(
        w * 0.76,
        y(0.81 + dy),
        w * 0.90,
        y(0.68 + dy),
        w,
        y(0.65 + dy),
      );
    final mid = midLine(0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      mid,
      shaded(
        Rect.fromLTRB(0, y(0.60), w, h),
        dark ? 0xFF22402F : 0xFFC9E1AC,
        dark ? 0xFF254532 : 0xFFB8D797,
      ),
    );
    canvas.save();
    canvas.clipPath(mid);
    final furrow = Paint()
      ..color = (dark ? const Color(0xFF34573F) : const Color(0xFFA2C985))
          .withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawPath(midLine(0.07), furrow);
    canvas.drawPath(midLine(0.14), furrow);
    canvas.restore();

    // Near hills: the deepest green, lowest layer.
    canvas.drawPath(
      Path()
        ..moveTo(0, y(0.88))
        ..cubicTo(w * 0.24, y(0.76), w * 0.48, y(0.81), w * 0.70, y(0.89))
        ..cubicTo(w * 0.86, y(0.95), w * 0.95, y(0.85), w, y(0.83))
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      shaded(
        Rect.fromLTRB(0, y(0.76), w, h),
        dark ? 0xFF2A4E36 : 0xFFADD38B,
        dark ? 0xFF2C5238 : 0xFFA2CB7E,
      ),
    );

    // A small, quiet sprig of leaves growing in from a side edge.
    final leafPaint = Paint()
      ..color = const Color(0xFF8DBF70).withValues(alpha: 0.6);
    final stemPaint = Paint()
      ..color = const Color(0xFF8DBF70).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    void leaf(double along, double length, double angle) {
      canvas.save();
      canvas.translate(along, 0);
      canvas.rotate(angle);
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(length * 0.5, -length * 0.34, length, 0)
          ..quadraticBezierTo(length * 0.5, length * 0.34, 0, 0),
        leafPaint,
      );
      canvas.restore();
    }

    void sprig(Offset base, double angle) {
      canvas.save();
      canvas.translate(base.dx, base.dy);
      canvas.rotate(angle);
      canvas.drawLine(Offset.zero, const Offset(20, 0), stemPaint);
      leaf(6, 9, -0.75);
      leaf(11, 9, 0.75);
      leaf(19, 10, -0.15);
      canvas.restore();
    }

    // Left: below Back, right: high on the other side; both at the edge.
    sprig(Offset(-2, y(0.50)), -0.45);
    sprig(Offset(w + 2, y(0.30)), math.pi + 0.45);

    // Fading into the page at the foot.
    final foot = Rect.fromLTRB(0, y(0.87), w, h);
    canvas.drawRect(
      foot,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.page.withValues(alpha: 0), AppColors.page],
        ).createShader(foot),
    );
  }

  @override
  bool shouldRepaint(ProfileLandscapePainter oldDelegate) =>
      oldDelegate.topInset != topInset ||
      oldDelegate.softTop != softTop ||
      oldDelegate.dark != dark;
}
