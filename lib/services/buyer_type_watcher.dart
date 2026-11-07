import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/account_types.dart';
import 'firebase_refs.dart';

/// Whether the signed-in account is a buyer who usually orders in bulk, for
/// the product cards and pages: those show the wholesale price first. One
/// subscription for the whole app, started by the first card that asks.
/// Anyone else, and an older account never asked what
/// describes it, sees the retail price first as before.
class BuyerTypeWatcher extends ChangeNotifier {
  BuyerTypeWatcher._();
  static final BuyerTypeWatcher instance = BuyerTypeWatcher._();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  String? _uid;
  bool _wholesaleFirst = false;

  bool get wholesaleFirst {
    _listen();
    return _wholesaleFirst;
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
    _wholesaleFirst = false;
    if (uid == null) return;
    _sub = FirebaseRefs.firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
          final next = isWholesaleBuyer(snap.data() ?? const {});
          if (next == _wholesaleFirst) return;
          _wholesaleFirst = next;
          notifyListeners();
        }, onError: (_) {});
  }

  /// Whether the account [profile] is a buyer who usually orders in bulk.
  static bool isWholesaleBuyer(Map<String, dynamic> profile) =>
      profile['role'] == 'buyer' &&
      kWholesaleBuyerTypes.contains(accountTypeOf(profile));

  /// Uses [wholesaleFirst] without Firestore.
  @visibleForTesting
  void debugSet(bool wholesaleFirst) {
    _wholesaleFirst = wholesaleFirst;
    notifyListeners();
  }
}
