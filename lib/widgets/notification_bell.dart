import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// The notification bell icon plus a small unread-count badge in its corner,
/// reused by Farmer Home and Buyer Marketplace so the badge logic lives in
/// exactly one place. Reads notifications/{uid}/items where read == false;
/// never a hardcoded count.
class NotificationBell extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? color;

  const NotificationBell({super.key, required this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return NotificationBellButton(onPressed: onPressed, color: color);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
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

/// What [NotificationBell] draws: the bell, with [unread] in a badge on its
/// top right corner when there is any.
class NotificationBellButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? color;
  final int unread;

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
            size: 22,
          ),
        ),
        if (unread > 0)
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
