import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'ph_mobile.dart';

/// The mobile numbers a buyer and a farmer may use to reach each other
/// about one order.
///
/// They are kept off the order document itself, in two private documents
/// under it, so firestore.rules can decide who reads which and when:
///
///   orders/{orderId}/private/buyer    { contact, updatedAt }
///   orders/{orderId}/private/farmer   { contact, updatedAt }
///
/// Each side can always read its own. The other side can read it only
/// while the order is confirmed or on its way ([isShared]) — not while it
/// is still pending, and not once it is completed, rejected or cancelled.
/// In-app Messages stays the main way to talk; these numbers are a
/// fallback for an order that is actually going ahead.
///
/// Orders placed before this existed carry the buyer's number on the order
/// document itself (`buyerContact`); [otherPartyContact] falls back to it.
class OrderContactService {
  OrderContactService._();
  static final OrderContactService instance = OrderContactService._();

  static const String buyerSide = 'buyer';
  static const String farmerSide = 'farmer';

  /// Whether an order in [status] is one whose two sides may see each
  /// other's number. Mirrors contactShared() in firestore.rules.
  static bool isShared(String status) =>
      status == 'confirmed' || status == 'shipped';

  /// A number as it is stored and shown, or '' if [raw] is not a valid
  /// Philippine mobile number in any of the forms the app has ever saved.
  static String normalized(String? raw) {
    final digits = phMobileLocalDigits(raw);
    return isValidPhMobile(digits) ? phMobileE164(digits) : '';
  }

  DocumentReference<Map<String, dynamic>> _doc(String orderId, String side) =>
      FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .collection('private')
          .doc(side);

  /// Saves the number the buyer confirmed on Place Order, for that order
  /// only. The order itself is already placed by the time this runs, so a
  /// failure here never undoes it — the two sides can still use Messages.
  Future<void> saveBuyerContact(String orderId, String contact) =>
      _save(orderId, buyerSide, contact);

  /// Called when the farmer confirms an order: puts the number from the
  /// farmer's own profile on that order for the buyer — and, for a pick-up
  /// order, where to pick it up: the farm's address from the profile and
  /// the farm's pin (Set Farm Location), so the buyer gets a map and
  /// directions. Readable by the buyer only while the order is going ahead
  /// (see [isShared]). Nothing is written if there is nothing to share.
  Future<void> shareFarmerContact(String orderId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final db = FirebaseFirestore.instance;
      final order = (await db.collection('orders').doc(orderId).get()).data();
      final pickup = order?['deliveryMethod'] == 'pickup';
      final data = (await db.collection('users').doc(uid).get()).data();
      final contact = normalized(
        (data?['mobileNumber'] ?? data?['phone'])?.toString(),
      );

      final shared = <String, dynamic>{
        if (contact.isNotEmpty) 'contact': contact,
      };
      if (pickup) {
        final address = pickupAddressOf(data ?? const {});
        if (address.isNotEmpty) shared['pickupAddress'] = address;
        try {
          final geo =
              (await db
                      .collection('users')
                      .doc(uid)
                      .collection('private')
                      .doc('geo')
                      .get())
                  .data();
          final lat = (geo?['latitude'] as num?)?.toDouble();
          final lng = (geo?['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            shared['pickupLat'] = lat;
            shared['pickupLng'] = lng;
          }
        } catch (_) {
          // No pin: the address alone still helps.
        }
      }
      if (shared.isEmpty) return;
      shared['updatedAt'] = FieldValue.serverTimestamp();
      await _doc(orderId, farmerSide).set(shared);
    } catch (e) {
      // Never the number or address itself — only that it was not shared.
      debugPrint('[OrderContact] farmer details not shared: $e');
    }
  }

  /// The farm's address as a pick-up address: the full address the farmer
  /// saved on their profile, else their barangay, town and province.
  static String pickupAddressOf(Map<String, dynamic> profile) {
    final full = (profile['location'] ?? profile['address'] ?? '')
        .toString()
        .trim();
    if (full.isNotEmpty) {
      return full.length > 300 ? full.substring(0, 300) : full;
    }
    return [profile['barangay'], profile['municipality'], profile['province']]
        .map((part) => (part ?? '').toString().trim())
        .where((part) => part.isNotEmpty)
        .join(', ');
  }

  /// Where to pick up a confirmed pick-up order, as the farmer shared it:
  /// null when there is nothing (yet), or it may not be read.
  Future<PickupPlace?> pickupPlace(String orderId) async {
    try {
      final data = (await _doc(orderId, farmerSide).get()).data();
      if (data == null) return null;
      final address = (data['pickupAddress'] ?? '').toString().trim();
      final lat = (data['pickupLat'] as num?)?.toDouble();
      final lng = (data['pickupLng'] as num?)?.toDouble();
      if (address.isEmpty && (lat == null || lng == null)) return null;
      return PickupPlace(address: address, latitude: lat, longitude: lng);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(String orderId, String side, String contact) async {
    final value = normalized(contact);
    if (value.isEmpty) return;
    try {
      await _doc(
        orderId,
        side,
      ).set({'contact': value, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      // Never the number itself — only that it could not be saved.
      debugPrint('[OrderContact] $side number not saved: $e');
    }
  }

  /// The other side's number for this order, or '' if there is none or it
  /// may not be read yet. [viewerIsFarmer] says which side is asking.
  Future<String> otherPartyContact({
    required String orderId,
    required bool viewerIsFarmer,
    String? legacyBuyerContact,
  }) async {
    try {
      final snap = await _doc(
        orderId,
        viewerIsFarmer ? buyerSide : farmerSide,
      ).get();
      final contact = normalized(snap.data()?['contact']?.toString());
      if (contact.isNotEmpty) return contact;
    } catch (_) {
      // Not readable (yet) — fall through.
    }
    return viewerIsFarmer ? normalized(legacyBuyerContact) : '';
  }
}

/// Where a buyer picks up a confirmed order: the farm's address and, when
/// the farmer has set it, the farm's pin.
class PickupPlace {
  final String address;
  final double? latitude;
  final double? longitude;

  const PickupPlace({required this.address, this.latitude, this.longitude});

  bool get hasPin => latitude != null && longitude != null;

  /// Google Maps directions to it: to the pin, else to the address.
  Uri get directionsUri => Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': hasPin ? '$latitude,$longitude' : address,
  });
}
