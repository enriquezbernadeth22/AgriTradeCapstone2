import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Where the app's services reach Firebase: the real Firestore and Auth in
/// the app, stand-ins in tests ([useForTests]), so the screens that read
/// orders or sign people in can be tested whole, not only their parts.
///
/// Services use these getters instead of `FirebaseFirestore.instance` and
/// `FirebaseAuth.instance`.
class FirebaseRefs {
  FirebaseRefs._();

  static FirebaseFirestore? _firestore;
  static FirebaseAuth? _auth;

  static FirebaseFirestore get firestore =>
      _firestore ?? FirebaseFirestore.instance;
  static FirebaseAuth get auth => _auth ?? FirebaseAuth.instance;

  /// Puts in a test's stand-ins (fake_cloud_firestore, firebase_auth_mocks);
  /// [reset] in its tear-down.
  @visibleForTesting
  static void useForTests({FirebaseFirestore? firestore, FirebaseAuth? auth}) {
    _firestore = firestore;
    _auth = auth;
  }

  @visibleForTesting
  static void reset() {
    _firestore = null;
    _auth = null;
  }
}
