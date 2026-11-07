import 'package:flutter/material.dart';

import '../services/firebase_refs.dart';
import 'profile_avatar.dart';

/// The photo of the buyer who wrote a review (the user's choice,
/// 2026-11-08), from their public profile — publicProfiles/{buyerId}, the
/// allow-listed projection, never their email or phone — with their
/// initials until it loads and when there is none. Each buyer is looked
/// up once per app run.
class ReviewerAvatar extends StatefulWidget {
  final String? buyerId;
  final String name;
  final double radius;

  const ReviewerAvatar({
    super.key,
    required this.buyerId,
    required this.name,
    this.radius = 18,
  });

  // A buyer's photo URL once known ('' for none), and the lookups running.
  static final Map<String, String> _known = {};
  static final Map<String, Future<String>> _asked = {};

  static Future<String> _photoOf(String buyerId) =>
      _asked.putIfAbsent(buyerId, () async {
        try {
          final profile = await FirebaseRefs.firestore
              .collection('publicProfiles')
              .doc(buyerId)
              .get();
          final url = profile.data()?['photoUrl']?.toString().trim() ?? '';
          return _known[buyerId] = url;
        } catch (_) {
          // Not kept: the next review shown asks again.
          _asked.remove(buyerId);
          return '';
        }
      });

  @override
  State<ReviewerAvatar> createState() => _ReviewerAvatarState();
}

class _ReviewerAvatarState extends State<ReviewerAvatar> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReviewerAvatar old) {
    super.didUpdateWidget(old);
    if (old.buyerId != widget.buyerId) _load();
  }

  void _load() {
    final id = widget.buyerId?.trim() ?? '';
    if (id.isEmpty) {
      _url = null;
      return;
    }
    _url = ReviewerAvatar._known[id];
    if (_url != null) return;
    ReviewerAvatar._photoOf(id).then((url) {
      if (mounted && widget.buyerId?.trim() == id) setState(() => _url = url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    return ProfileAvatar(
      photoUrl: url == null || url.isEmpty ? null : url,
      name: widget.name,
      radius: widget.radius,
    );
  }
}
