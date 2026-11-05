import '../widgets/agri_app_bar.dart';
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
      FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(widget.farmerId)
          .snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _products =
      FirebaseFirestore.instance
          .collection('products')
          .where('farmerId', isEqualTo: widget.farmerId)
          .snapshots();
  // Every review of this farmer's products (reviews are open to read).
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _reviews =
      FirebaseFirestore.instance
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: const AgriAppBar(),
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
            return Center(child: Text(tl('Farmer profile is unavailable.')));
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            children: [
              _header(profile),
              const SizedBox(height: 20),
              Divider(height: 1, color: AppColors.grey(200)),
              const SizedBox(height: 16),
              _reviewsSection(
                (profile['name'] ?? profile['fullName'] ?? tl('Farmer'))
                    .toString(),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: AppColors.grey(200)),
              const SizedBox(height: 16),
              _productsSection(),
            ],
          );
        },
      ),
    );
  }

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

    return Column(
      children: [
        // The photo opens full screen when there is one.
        GestureDetector(
          key: const Key('storefrontPhoto'),
          onTap: (profile['photoUrl'] ?? '').toString().isEmpty
              ? null
              : () =>
                    openPhotoGallery(context, [profile['photoUrl'].toString()]),
          child: ProfileAvatar(
            photoUrl: profile['photoUrl']?.toString(),
            name: name,
            radius: 46,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.heading(22),
        ),
        if (location.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.place_outlined, size: 15, color: AppColors.grey(600)),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.grey(700),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (verified) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.tint,
              border: AppColors.cardBorder,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, size: 15, color: AppColors.brand),
                SizedBox(width: 5),
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
          const SizedBox(height: 12),
          Text(
            bio,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.grey(700),
            ),
          ),
        ],
      ],
    );
  }

  Widget _productsSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _products,
      builder: (context, productSnap) {
        if (productSnap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            ),
          );
        }
        if (productSnap.hasError) {
          return _note(tl('Could not load this farmer’s products.'));
        }
        final products = (productSnap.data?.docs ?? const [])
            .where(
              (doc) =>
                  doc.data()['isArchived'] != true &&
                  doc.data()['isSuspended'] != true,
            )
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tl('Products ({0})', [products.length]),
              style: AppTheme.heading(17),
            ),
            const SizedBox(height: 12),
            if (products.isEmpty)
              _note(tl('No active products right now.'))
            else
              _grid(products),
          ],
        );
      },
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, color: AppColors.grey(600)),
    ),
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

  Widget _reviewsSection(String farmerName) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reviews,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError && !snapshot.hasData) {
          return _note(tl('Could not load this farmer’s reviews.'));
        }
        final reviews = visibleProductReviews(snapshot.data);
        final average = averageReviewRating(reviews);
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
                  child: Text(
                    tl('Reviews ({0})', [reviews.length]),
                    style: AppTheme.heading(17),
                  ),
                ),
                if (reviews.isNotEmpty)
                  TextButton(
                    key: const Key('storefrontSeeAllReviews'),
                    onPressed: seeAll,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brand,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(tl('See all')),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (reviews.isEmpty)
              _note(tl('No reviews yet.'))
            else ...[
              Row(
                children: [
                  Text(
                    average.toStringAsFixed(1),
                    style: AppTheme.heading(26).copyWith(height: 1),
                  ),
                  const SizedBox(width: 10),
                  ReviewStars(rating: average, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reviews.length == 1
                          ? tl('(1 review)')
                          : tl('({0} reviews)', [reviews.length]),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.grey(700),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // The latest two; the rest under See all.
              for (final doc in reviews.take(2)) ...[
                _reviewCard(doc.data()),
                const SizedBox(height: 10),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _reviewCard(Map<String, dynamic> review) {
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.grey(200)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Initials only — a review shows the buyer's name, not their
              // profile.
              ProfileAvatar(photoUrl: null, name: reviewer, radius: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reviewer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
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
                            DateFormat('MMM d, y').format(created),
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.grey(600),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (product.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              tl('Reviewed: {0}', [product]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.grey(700),
              ),
            ),
          ],
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              comment,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.text,
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
