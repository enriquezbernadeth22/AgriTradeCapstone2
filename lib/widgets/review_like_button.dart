import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/firebase_refs.dart';
import '../theme/app_colors.dart';
import 'app_scaffold_messenger.dart';

/// The buyers who liked a review: `likes.{uid}` = true on its
/// productReviews doc (the user's design, 2026-11-07).
Set<String> reviewLikers(Map<String, dynamic> review) {
  final likes = review['likes'];
  if (likes is! Map) return const {};
  return {
    for (final entry in likes.entries)
      if (entry.value == true) entry.key.toString(),
  };
}

/// Likes or unlikes review [reviewId] as the signed-in buyer. firestore.rules
/// lets a buyer change only their own key in `likes`, and not on their own
/// review. Returns an error to show, or null.
Future<String?> setReviewLike(String reviewId, bool liked) async {
  final uid = FirebaseRefs.auth.currentUser?.uid;
  if (uid == null) return tl('Please log in again.');
  try {
    await FirebaseRefs.firestore
        .collection('productReviews')
        .doc(reviewId)
        .update({'likes.$uid': liked ? true : FieldValue.delete()});
    return null;
  } catch (_) {
    return tl('Could not update your like. Try again.');
  }
}

/// A thumbs-up and how many buyers liked a review, at the right of the
/// review card: other buyers tap it to like the review (again to take the
/// like back). The reviewer themselves, farmers and the Admin see the count
/// only.
class ReviewLikeButton extends StatefulWidget {
  final String reviewId;
  final Map<String, dynamic> review;

  const ReviewLikeButton({
    super.key,
    required this.reviewId,
    required this.review,
  });

  @override
  State<ReviewLikeButton> createState() => _ReviewLikeButtonState();
}

class _ReviewLikeButtonState extends State<ReviewLikeButton> {
  // Whether the signed-in account is a buyer, read once per account.
  static final Map<String, Future<bool>> _isBuyer = {};

  late Set<String> _likers = reviewLikers(widget.review);
  bool _canLike = false;
  bool _saving = false;

  String? get _me => FirebaseRefs.auth.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _checkCanLike();
  }

  @override
  void didUpdateWidget(ReviewLikeButton old) {
    super.didUpdateWidget(old);
    // The live review wins, except while this phone's own like is saving.
    if (!_saving) _likers = reviewLikers(widget.review);
  }

  Future<void> _checkCanLike() async {
    final me = _me;
    if (me == null || widget.review['buyerId'] == me) return;
    final buyer = await _isBuyer.putIfAbsent(me, () async {
      try {
        final user = await FirebaseRefs.firestore
            .collection('users')
            .doc(me)
            .get();
        return user.data()?['role'] == 'buyer';
      } catch (_) {
        return false;
      }
    });
    if (mounted && buyer) setState(() => _canLike = true);
  }

  Future<void> _toggle() async {
    final me = _me;
    if (me == null || _saving) return;
    final liked = !_likers.contains(me);
    final before = _likers;
    setState(() {
      _saving = true;
      if (liked) {
        _likers = {...before, me};
      } else {
        _likers = {...before}..remove(me);
      }
    });
    final error = await setReviewLike(widget.reviewId, liked);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error != null) _likers = before;
    });
    if (error != null) {
      showAppMessage(context, error, kind: MessageKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liked = _me != null && _likers.contains(_me);
    final count = _likers.length;
    final color = liked ? AppColors.brand : AppColors.grey(600);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            liked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
            size: 17,
            color: color,
          ),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
    if (!_canLike) {
      // The count only; nothing to show when no one has liked it yet.
      if (count == 0) return const SizedBox.shrink();
      return Semantics(
        label: tl('{0} likes', [count]),
        child: ExcludeSemantics(child: content),
      );
    }
    return Tooltip(
      message: liked ? tl('Unlike review') : tl('Like review'),
      child: InkWell(
        key: Key('reviewLike_${widget.reviewId}'),
        customBorder: const StadiumBorder(),
        onTap: _toggle,
        child: content,
      ),
    );
  }
}
