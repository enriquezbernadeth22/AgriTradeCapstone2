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
    // landscape, the photo, name, place and badge, a card of the farmer's
    // numbers, then the reviews and the products. The products and the
    // reviews are each read once, for the numbers and the lists alike.
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
                        _stats(reviews, products),
                        const SizedBox(height: 18),
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

  // Rating | Reviews | Products: the farmer's real numbers ("–" until
  // there is a rating), on one white card.
  Widget _stats(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? reviews,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? products,
  ) {
    final count = reviews?.length;
    final rating = reviews == null || reviews.isEmpty
        ? '–'
        : averageReviewRating(reviews).toStringAsFixed(1);
    Widget stat(Widget icon, String value, String label) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 5),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11.5, color: _muted)),
        ],
      ),
    );
    Widget line() => Container(width: 1, height: 34, color: _line);
    return Container(
      key: const Key('storefrontStats'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: AppTheme.card(),
      child: Row(
        children: [
          stat(
            const Icon(Icons.star_rounded, size: 19, color: Color(0xFFF5BB24)),
            rating,
            tl('Rating'),
          ),
          line(),
          stat(
            Icon(Icons.rate_review_outlined, size: 18, color: AppColors.brand),
            count == null ? '–' : '$count',
            count == 1 ? tl('Review') : tl('Reviews'),
          ),
          line(),
          stat(
            Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.brand),
            products == null ? '–' : '${products.length}',
            products?.length == 1 ? tl('Product') : tl('Products'),
          ),
        ],
      ),
    );
  }

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
    const landscape = 132.0;
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
                child: const ExcludeSemantics(
                  child: CustomPaint(painter: ProfileLandscapePainter()),
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
        const SizedBox(height: 10),
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
          const SizedBox(height: 3),
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
          const SizedBox(height: 9),
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
            // A small outlined pill.
            if (reviews.isNotEmpty)
              OutlinedButton(
                key: const Key('storefrontSeeAllReviews'),
                onPressed: seeAll,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  side: BorderSide(
                    color: AppColors.brand.withValues(alpha: 0.5),
                  ),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tl('See all'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 16),
                  ],
                ),
              ),
          ],
        ),
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

/// The farmer's photo in a white ring with a gold arc along part of it, on
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(3.5),
            child: ProfileAvatar(
              photoUrl: photoUrl,
              name: name,
              radius: size / 2 - 3.5,
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _GoldArc())),
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

// A gold arc along the upper right of the photo's white ring.
class _GoldArc extends CustomPainter {
  const _GoldArc();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF5BB24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      (Offset.zero & size).deflate(1.25),
      -math.pi * 0.62,
      math.pi * 0.7,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_GoldArc oldDelegate) => false;
}

/// The top of a farmer's public profile: a pale cream sky with a faint
/// gold sun, soft rolling hills, curved field rows and small leaves at the
/// edges, fading into the page at its foot.
class ProfileLandscapePainter extends CustomPainter {
  const ProfileLandscapePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Paint fill(int color) => Paint()..color = Color(color);

    // A faint gold sun, high on the right.
    canvas.drawCircle(
      Offset(w * 0.78, h * 0.32),
      h * 0.42,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFFF5BB24).withValues(alpha: 0.22),
                const Color(0xFFF5BB24).withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: Offset(w * 0.78, h * 0.32),
                radius: h * 0.42,
              ),
            ),
    );

    // Far hills.
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.62)
        ..quadraticBezierTo(w * 0.22, h * 0.40, w * 0.48, h * 0.56)
        ..quadraticBezierTo(w * 0.74, h * 0.36, w, h * 0.52)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      fill(0xFFDDEBCB),
    );
    // Near hills.
    final near = Path()
      ..moveTo(0, h * 0.80)
      ..quadraticBezierTo(w * 0.30, h * 0.60, w * 0.58, h * 0.74)
      ..quadraticBezierTo(w * 0.82, h * 0.84, w, h * 0.66)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(near, fill(0xFFB9DA98));
    // Curved field rows across them.
    canvas.save();
    canvas.clipPath(near);
    final row = Paint()
      ..color = const Color(0xFF9CCB7C).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (var i = 0; i < 6; i++) {
      final y = h * (0.74 + i * 0.06);
      canvas.drawPath(
        Path()
          ..moveTo(-10, y + 6)
          ..quadraticBezierTo(w * 0.45, y - h * 0.08, w + 10, y),
        row,
      );
    }
    canvas.restore();

    // Small leaves at the edges.
    void leaf(Offset at, double length, double angle, int color) {
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle);
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(length * 0.5, -length * 0.32, length, 0)
          ..quadraticBezierTo(length * 0.5, length * 0.32, 0, 0),
        fill(color),
      );
      canvas.restore();
    }

    leaf(Offset(w * 0.02, h * 0.50), h * 0.26, -0.5, 0xFF8BC06A);
    leaf(Offset(w * 0.03, h * 0.62), h * 0.20, -1.1, 0xFFA6CF86);
    leaf(Offset(w * 0.98, h * 0.48), h * 0.26, math.pi + 0.5, 0xFF8BC06A);
    leaf(Offset(w * 0.97, h * 0.60), h * 0.20, math.pi + 1.1, 0xFFA6CF86);

    // Fading into the page at the foot.
    canvas.drawRect(
      Rect.fromLTRB(0, h * 0.78, w, h),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.page.withValues(alpha: 0), AppColors.page],
        ).createShader(Rect.fromLTRB(0, h * 0.78, w, h)),
    );
  }

  @override
  bool shouldRepaint(ProfileLandscapePainter oldDelegate) => false;
}
