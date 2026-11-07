import '../widgets/agri_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/reviewer_avatar.dart';
import '../widgets/review_like_button.dart';
import '../widgets/app_scaffold_messenger.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/agri_empty_state.dart';
import '../widgets/chat_photo_viewer.dart' show openPhotoGallery;
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

/// The reviews of one product a buyer may see — those not removed by
/// moderation — newest first. Shared by the Product Details preview and
/// the full list below so both always count the same reviews.
List<QueryDocumentSnapshot<Map<String, dynamic>>> visibleProductReviews(
  QuerySnapshot<Map<String, dynamic>>? snapshot,
) {
  return (snapshot?.docs ?? const [])
      .where((doc) => doc.data()['moderationStatus'] != 'removed')
      .toList()
    ..sort((a, b) {
      final at = a.data()['createdAt'] as Timestamp?;
      final bt = b.data()['createdAt'] as Timestamp?;
      return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
        at?.millisecondsSinceEpoch ?? 0,
      );
    });
}

double averageReviewRating(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> reviews,
) {
  if (reviews.isEmpty) return 0;
  return reviews
          .map((d) => (d.data()['rating'] as num?)?.toDouble() ?? 0)
          .reduce((a, b) => a + b) /
      reviews.length;
}

/// Five stars filled to [rating], halves included.
class ReviewStars extends StatelessWidget {
  final double rating;
  final double size;
  const ReviewStars({super.key, required this.rating, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (index) => Icon(
          rating >= index + 1
              ? Icons.star_rounded
              : rating >= index + 0.5
              ? Icons.star_half_rounded
              : Icons.star_border_rounded,
          size: size,
          // The app's gold (2026-11-08).
          color: rating >= index + 0.5
              ? const Color(0xFFF5BB24)
              : AppColors.grey(400),
        ),
      ),
    );
  }
}

/// Every review of one product, in full: the text, the buyer's photos, the
/// Verified Purchase mark and the farmer's reply. Opened from "View All" on
/// Product Details, whose preview cards only show a short excerpt.
///
/// With no [productId] it lists every review of the farmer's products
/// instead (the storefront's "See all"), each naming its product;
/// [productName] is then the farmer's name, shown on top.
class ProductReviewsScreen extends StatefulWidget {
  final String? productId;
  final String productName;
  final String? farmerId;

  const ProductReviewsScreen({
    super.key,
    required this.productId,
    required this.productName,
    required this.farmerId,
  });

  @override
  State<ProductReviewsScreen> createState() => _ProductReviewsScreenState();
}

class _ProductReviewsScreenState extends State<ProductReviewsScreen> {
  bool get _forFarmer => widget.productId == null;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _reviews = _forFarmer
      ? FirebaseFirestore.instance
            .collection('productReviews')
            .where('sellerId', isEqualTo: widget.farmerId)
            .snapshots()
      : FirebaseFirestore.instance
            .collection('productReviews')
            .where('productId', isEqualTo: widget.productId)
            .snapshots();

  Future<void> _reportReview(
    String reviewId,
    Map<String, dynamic> review,
  ) async {
    final reporter = FirebaseAuth.instance.currentUser;
    final sellerId = widget.farmerId ?? '';
    final reviewedBuyerId = review['buyerId']?.toString() ?? '';
    if (reporter == null || sellerId.isEmpty || reviewedBuyerId.isEmpty) return;

    final controller = TextEditingController();
    final confirmed = await showAgriDialog<bool>(
      context: context,
      builder: (dialogContext) => AgriDialog(
        icon: Icons.flag_outlined,
        tone: AgriTone.warning,
        title: Text(tl('Report this review?')),
        content: TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14),
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: tl('Tell us what is wrong with this review.'),
          ),
        ),
        actions: [
          AgriDialogButton(
            label: tl('Cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AgriDialogButton(
            label: tl('Report'),
            kind: AgriButtonKind.primary,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    final description = controller.text.trim();
    controller.dispose();
    if (confirmed != true || description.isEmpty || !mounted) return;

    try {
      await FirebaseFirestore.instance.collection('reports').add({
        'issueType': 'Review Report',
        'description': description,
        'reporterId': reporter.uid,
        'reporterName': reporter.displayName ?? 'User',
        'reportedUserId': reviewedBuyerId,
        'reportedUserName': (review['buyerName'] ?? 'Buyer').toString(),
        'targetType': 'review',
        'farmerId': sellerId,
        'productId': widget.productId ?? review['productId']?.toString(),
        'productName': _forFarmer
            ? (review['productName'] ?? 'Product').toString()
            : widget.productName,
        'reviewId': reviewId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar(
          tl('Review reported for admin review.'),
          kind: MessageKind.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar(
          tl('Could not report this review.'),
          kind: MessageKind.error,
        ),
      );
    }
  }

  // The photos a buyer attached: the single `imageUrl` a review is saved
  // with, plus an `imageUrls` list where one exists.
  List<String> _photosOf(Map<String, dynamic> review) {
    final photos = <String>[];
    final single = review['imageUrl']?.toString() ?? '';
    if (single.isNotEmpty) photos.add(single);
    if (review['imageUrls'] is List) {
      for (final url in review['imageUrls'] as List) {
        final value = url?.toString() ?? '';
        if (value.isNotEmpty && !photos.contains(value)) photos.add(value);
      }
    }
    return photos;
  }

  Widget _photos(List<String> photos) {
    const size = 96.0;
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        // Full screen, to swipe through the review's photos.
        itemBuilder: (context, index) => GestureDetector(
          onTap: () => openPhotoGallery(context, photos, initialIndex: index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              photos[index],
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: size,
                height: size,
                color: AppColors.accent,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image, color: AppColors.brand),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _review(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final review = doc.data();
    final reviewer = review['buyerName']?.toString() ?? 'Buyer';
    final reviewerId = review['buyerId']?.toString() ?? '';
    final text = review['comment']?.toString() ?? '';
    final rating = (review['rating'] as num?)?.toDouble() ?? 0;
    final created = (review['createdAt'] as Timestamp?)?.toDate();
    final reply = (review['sellerReply'] ?? '').toString();
    final photos = _photosOf(review);
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final canReport = viewerId != reviewerId && viewerId != widget.farmerId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The reviewer's photo (initials without one).
            ReviewerAvatar(buyerId: reviewerId, name: reviewer, radius: 18),
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
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      ReviewStars(rating: rating, size: 13),
                      if (created != null)
                        Text(
                          DateFormat('MMM d, y').format(created),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.grey(700),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            ReviewLikeButton(reviewId: doc.id, review: review),
            if (canReport)
              IconButton(
                tooltip: tl('Report review'),
                visualDensity: VisualDensity.compact,
                onPressed: () => _reportReview(doc.id, review),
                icon: Icon(
                  Icons.flag_outlined,
                  size: 18,
                  color: AppColors.grey(600),
                ),
              ),
          ],
        ),
        // A farmer's whole list says which product each review is about.
        if (_forFarmer &&
            (review['productName'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            tl('Reviewed: {0}', [review['productName'].toString()]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.grey(700),
            ),
          ),
        ],
        // Every review is tied to the buyer's own completed order (see
        // firestore.rules).
        if ((review['orderId'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.verified_outlined, size: 13, color: AppColors.brand),
              SizedBox(width: 4),
              Text(
                tl('Verified Purchase'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand,
                ),
              ),
            ],
          ),
        ],
        if (text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
        if (photos.isNotEmpty) ...[const SizedBox(height: 10), _photos(photos)],
        if (reply.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppColors.isDark
                  ? AppColors.tint
                  : const Color(0xFFEAF2E4),
              border: AppColors.cardBorder,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tl('Reply from the farmer'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reply,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AgriAppBar(title: tl('Buyer Reviews')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _reviews,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                tl('Could not load reviews.'),
                style: TextStyle(color: AppColors.grey(700)),
              ),
            );
          }
          final docs = visibleProductReviews(snapshot.data);
          if (docs.isEmpty) {
            return Center(
              child: AgriEmptyState(
                icon: Icons.rate_review_outlined,
                title: tl('No reviews yet'),
                subtitle: _forFarmer
                    ? tl('This farmer has no reviews yet.')
                    : tl(
                        'Be the first to review this product after completing an order.',
                      ),
                padding: EdgeInsets.all(32),
              ),
            );
          }
          final average = averageReviewRating(docs);

          // A summary card, then each review on a white card of its own on
          // the cream (the user's design, 2026-11-08).
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: docs.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index > 0) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
                  decoration: AppTheme.card(),
                  child: _review(docs[index - 1]),
                );
              }
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.card(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brand,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          average.toStringAsFixed(1),
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 22,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brand,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ReviewStars(rating: average, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            docs.length == 1
                                ? '(1 review)'
                                : tl('({0} reviews)', [docs.length]),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.grey(700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
