import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_refs.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// The notification bell icon plus a small gold dot in its corner while
/// anything is unread (the user's design, 2026-11-08, in place of a red
/// count),
/// reused by Farmer Home and Buyer Marketplace so the badge logic lives in
/// exactly one place. Reads notifications/{uid}/items where read == false;
/// never a hardcoded count.
class NotificationBell extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? color;

  const NotificationBell({super.key, required this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseRefs.auth.currentUser?.uid;
    if (uid == null) {
      return NotificationBellButton(onPressed: onPressed, color: color);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseRefs.firestore
          .collection('notifications')
          .doc(uid)
          .collection('items')
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) => NotificationBellButton(
        onPressed: onPressed,
        color: color,
        unread: snapshot.data?.docs.length ?? 0,
      ),
    );
  }
}

/// What [NotificationBell] draws: the bell, with a gold dot on its top right
/// corner while [unread] is above zero.
class NotificationBellButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? color;
  final int unread;

  /// The unread dot's gold, ringed in the header's dark green.
  static const Color dotColor = Color(0xFFF2B630);
  static const Color dotRing = Color(0xFF1F4B2C);

  const NotificationBellButton({
    super.key,
    required this.onPressed,
    this.color,
    this.unread = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(
            Icons.notifications_none_rounded,
            color: color ?? AppColors.brand,
            size: 24,
          ),
        ),
        if (unread > 0)
          Positioned(
            right: 10,
            top: 10,
            child: IgnorePointer(
              child: Semantics(
                label: unread == 1
                    ? '1 unread notification'
                    : '$unread unread notifications',
                child: Container(
                  key: const Key('notificationDot'),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: dotRing, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
