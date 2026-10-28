import '../widgets/agri_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/review_stats.dart';
import '../widgets/profile_avatar.dart';
import '../theme/app_colors.dart';

/// Five stars for [rating], with half stars.
class RatingStars extends StatelessWidget {
  final double rating;
  final double size;

  const RatingStars(this.rating, {super.key, this.size = 16});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 5; i++)
        Icon(
          rating >= i + 1
              ? Icons.star_rounded
              : rating >= i + 0.5
              ? Icons.star_half_rounded
              : Icons.star_border_rounded,
          size: size,
          color: rating >= i + 0.5 ? Colors.amber : AppColors.grey(400),
        ),
    ],
  );
}

/// A farmer's buyer reviews: every product's ([productId] null — "View All
/// Reviews" on the Profile), or one product's ("View Reviews" on a product).
/// Shows the rating worked out from the valid reviews, each review, and the
/// farmer's reply under it; the farmer can reply to (or edit their reply
/// to) each review.
class FarmerReviewsScreen extends StatefulWidget {
  final String? productId;
  final String? productName;

  const FarmerReviewsScreen({super.key, this.productId, this.productName});

  @override
  State<FarmerReviewsScreen> createState() => _FarmerReviewsScreenState();
}

class _FarmerReviewsScreenState extends State<FarmerReviewsScreen> {
  final String? _sellerId = FirebaseAuth.instance.currentUser?.uid;
  bool get _forProduct => (widget.productId ?? '').isNotEmpty;

  // Created once — not on every rebuild.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _reviews = _forProduct
      ? FirebaseFirestore.instance
            .collection('productReviews')
            .where('productId', isEqualTo: widget.productId)
            .snapshots()
      : FirebaseFirestore.instance
            .collection('productReviews')
            .where('sellerId', isEqualTo: _sellerId)
            .snapshots();

  // Buyers' public photos, looked up once per buyer.
  final Map<String, Future<String?>> _buyerPhotos = {};

  Future<String?> _buyerPhoto(String buyerId) =>
      _buyerPhotos.putIfAbsent(buyerId, () async {
        if (buyerId.isEmpty) return null;
        try {
          final profile = await FirebaseFirestore.instance
              .collection('publicProfiles')
              .doc(buyerId)
              .get();
          return profile.data()?['photoUrl']?.toString();
        } catch (_) {
          return null;
        }
      });

  @override
  Widget build(BuildContext context) {
    if (_sellerId == null || _sellerId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Log in to view your reviews.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      appBar: AgriAppBar(
        title: _forProduct ? 'Product Reviews' : 'Buyer Reviews',
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _reviews,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.brand,
                ),
              ),
            );
          }
          if (snapshot.hasError && !snapshot.hasData) {
            return const Center(child: Text('Could not load your reviews.'));
          }
          final reviews =
              (snapshot.data?.docs ?? const [])
                  .where((doc) => isValidReview(doc.data()))
                  .toList()
                ..sort((a, b) {
                  final aDate = a.data()['createdAt'] as Timestamp?;
                  final bDate = b.data()['createdAt'] as Timestamp?;
                  return (bDate?.millisecondsSinceEpoch ?? 0).compareTo(
                    aDate?.millisecondsSinceEpoch ?? 0,
                  );
                });
          final summary = summarizeReviews(reviews.map((doc) => doc.data()));
          final productName =
              widget.productName ??
              (reviews.isEmpty
                  ? 'Product'
                  : (reviews.first.data()['productName'] ?? 'Product')
                        .toString());

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              _summaryCard(
                _forProduct ? productName : 'Overall Product Rating',
                summary,
              ),
              const SizedBox(height: 10),
              for (final review in reviews) _reviewCard(review),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryCard(String title, RatingSummary summary) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.grey(200)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.montserrat(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        if (summary.count == 0)
          Text(
            'No reviews yet',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              color: AppColors.grey(600),
            ),
          )
        else ...[
          Row(
            children: [
              Text(
                formatRating(summary.average),
                style: GoogleFonts.montserrat(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: 10),
              RatingStars(summary.average, size: 20),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Based on ${reviewCountLabel(summary.count)}',
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: AppColors.grey(600),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _reviewCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final review = doc.data();
    final rating = (review['rating'] as num).toDouble();
    final buyerName = (review['buyerName'] ?? 'Buyer').toString();
    final buyerId = (review['buyerId'] ?? '').toString();
    final comment = (review['comment'] ?? '').toString();
    final imageUrl = (review['imageUrl'] ?? '').toString();
    final createdAt = review['createdAt'];
    final reply = (review['sellerReply'] ?? '').toString();
    final repliedAt = review['sellerReplyAt'];
    final farmerName =
        FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty ==
            true
        ? FirebaseAuth.instance.currentUser!.displayName!.trim()
        : 'You';
    String date(dynamic value) =>
        value is Timestamp ? DateFormat('MMM d, y').format(value.toDate()) : '';
    final muted = GoogleFonts.montserrat(
      fontSize: 11,
      color: AppColors.grey(600),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.grey(200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_forProduct)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                (review['productName'] ?? 'Product').toString(),
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand,
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<String?>(
                future: _buyerPhoto(buyerId),
                builder: (context, photo) => ProfileAvatar(
                  photoUrl: photo.data,
                  name: buyerName,
                  radius: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      buyerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.montserrat(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        RatingStars(rating, size: 15),
                        if (date(createdAt).isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(date(createdAt), style: muted),
                        ],
                      ],
                    ),
                    // Tied to the buyer's own completed order.
                    if ((review['orderId'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            Icon(
                              Icons.verified_outlined,
                              size: 13,
                              color: AppColors.brand,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Verified Purchase',
                              style: GoogleFonts.montserrat(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.brand,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              comment,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                color: AppColors.text,
                height: 1.4,
              ),
            ),
          ],
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                imageUrl,
                height: 170,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
          if (reply.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.tint,
                border: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$farmerName (Farmer)',
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brand,
                          ),
                        ),
                      ),
                      if (date(repliedAt).isNotEmpty)
                        Text(date(repliedAt), style: muted),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    reply,
                    style: GoogleFonts.montserrat(
                      fontSize: 12.5,
                      color: AppColors.text,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Write the reply right here — no popup to open first.
          ReviewReplyBox(
            key: ValueKey('reply-${doc.id}'),
            existing: reply,
            // One reply per review: saving again replaces it.
            onSend: (text) => doc.reference.update({
              'sellerReply': text,
              'sellerReplyAt': FieldValue.serverTimestamp(),
            }),
          ),
        ],
      ),
    );
  }
}

/// The farmer's reply box under a review: a pill-shaped "Write a reply…"
/// field with a send button, right on the card. Once a reply is saved it
/// shows above, and "Edit reply" opens this box again with it filled in.
/// One reply per review — saving again replaces it. The box owns its text
/// field, so nothing is used after it is gone.
class ReviewReplyBox extends StatefulWidget {
  /// The reply already saved, or empty.
  final String existing;

  /// Saves the (trimmed) reply.
  final Future<void> Function(String reply) onSend;

  const ReviewReplyBox({
    super.key,
    required this.existing,
    required this.onSend,
  });

  /// The most a reply may be (firestore.rules).
  static const int maxLength = 500;

  @override
  State<ReviewReplyBox> createState() => _ReviewReplyBoxState();
}

class _ReviewReplyBoxState extends State<ReviewReplyBox> {
  final _controller = TextEditingController();
  late bool _editing = widget.existing.isEmpty;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(ReviewReplyBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A reply just saved (here or elsewhere): show it, not the box.
    if (widget.existing != oldWidget.existing && widget.existing.isNotEmpty) {
      _editing = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSend {
    final text = _controller.text.trim();
    return !_sending && text.isNotEmpty && text != widget.existing;
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final reply = _controller.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await widget.onSend(reply);

      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() {
        _sending = false;
        _editing = false;
        _controller.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not send your reply. Please try again.'),
        ),
      );
    }
  }

  void _edit() {
    _controller.text = widget.existing;
    setState(() => _editing = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _edit,
          icon: const Icon(Icons.edit_outlined, size: 15),
          label: const Text('Edit reply'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.brand,
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: GoogleFonts.montserrat(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: ReviewReplyBox.maxLength,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.montserrat(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: widget.existing.isEmpty
                        ? 'Write a reply to the buyer…'
                        : 'Edit your reply…',
                    hintStyle: GoogleFonts.montserrat(
                      fontSize: 13,
                      color: AppColors.grey(500),
                    ),
                    // Kept clean: the limit still applies.
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.adapt(const Color(0xFFF4F6F3)),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: AppColors.mid, width: 1.2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                height: 40,
                child: IconButton.filled(
                  tooltip: 'Send reply',
                  onPressed: _canSend ? _send : null,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.brandFill,
                    disabledBackgroundColor: AppColors.brandFill.withValues(
                      alpha: 0.3,
                    ),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                ),
              ),
            ],
          ),
          if (widget.existing.isNotEmpty)
            TextButton(
              onPressed: _sending
                  ? null
                  : () => setState(() {
                      _editing = false;
                      _controller.clear();
                    }),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.grey(700),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Cancel'),
            ),
        ],
      ),
    );
  }
}
