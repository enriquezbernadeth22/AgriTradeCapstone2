import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'delivery_coverage.dart';
import 'firebase_refs.dart';

/// The signed-in buyer's saved area (barangay, municipality, province on
/// users/{uid}, set at sign-up or in Delivery & Pickup), for the product
/// feeds: listings that deliver there come first ([deliveringFirst]) and
/// say so on their card. One subscription for the whole app, started by the
/// first feed or card that asks, like BuyerTypeWatcher. Unknown until the
/// buyer has a location; then nothing is reordered.
class BuyerAreaWatcher extends ChangeNotifier {
  BuyerAreaWatcher._();
  static final BuyerAreaWatcher instance = BuyerAreaWatcher._();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  String? _uid;
  BuyerArea _area = const BuyerArea();

  BuyerArea get area {
    _listen();
    return _area;
  }

  void _listen() {
    String? uid;
    try {
      uid = FirebaseRefs.auth.currentUser?.uid;
    } catch (_) {
      return; // Firebase not set up (e.g. in tests).
    }
    if (uid == _uid) return;
    _uid = uid;
    _sub?.cancel();
    _sub = null;
    _area = const BuyerArea();
    if (uid == null) return;
    _sub = FirebaseRefs.firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
          final next = areaOf(snap.data() ?? const {});
          if (next.label == _area.label) return;
          _area = next;
          notifyListeners();
        }, onError: (_) {});
  }

  /// A buyer's area from their users/{uid} profile; unknown for anyone else.
  static BuyerArea areaOf(Map<String, dynamic> profile) {
    if (profile['role'] != 'buyer') return const BuyerArea();
    String text(String key) => (profile[key] ?? '').toString().trim();
    return BuyerArea(
      barangay: text('barangay'),
      city: text('municipality'),
      province: text('province'),
    );
  }

  /// Uses [area] without Firestore.
  @visibleForTesting
  void debugSet(BuyerArea area) {
    _area = area;
    notifyListeners();
  }
}
