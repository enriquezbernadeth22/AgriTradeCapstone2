import 'package:cloud_firestore/cloud_firestore.dart';

/// One user's activity on the platform, as the Admin sees it on their
/// account (system objectives, 2026-11-09: the Admin monitors the
/// activities of registered farmers and buyers). Counted from the portal's
/// own live lists of orders and listings; nothing is stored.
class AccountActivity {
  /// Orders this account placed (buyer) or received (farmer), every status.
  final int orders;
  final int pending;
  final int inProgress;
  final int completed;

  /// Cancelled or rejected.
  final int cancelled;

  /// The completed orders' totals: spent (buyer) or earned (farmer).
  final num completedValue;

  /// A farmer's listings: on sale, and archived or hidden.
  final int activeListings;
  final int inactiveListings;

  /// The most recent order or listing, newest first (at most [recentLimit]).
  final List<AccountActivityItem> recent;

  /// When this account last placed, received or changed an order, or
  /// posted a listing; null when it has done none of these.
  final DateTime? lastActivity;

  const AccountActivity({
    required this.orders,
    required this.pending,
    required this.inProgress,
    required this.completed,
    required this.cancelled,
    required this.completedValue,
    required this.activeListings,
    required this.inactiveListings,
    required this.recent,
    required this.lastActivity,
  });

  static const int recentLimit = 5;
}

/// One line of an account's recent activity.
class AccountActivityItem {
  final String title;
  final String detail;
  final DateTime when;
  const AccountActivityItem(this.title, this.detail, this.when);
}

DateTime? _date(Object? value) => value is Timestamp
    ? value.toDate()
    : value is DateTime
    ? value
    : null;

/// The activity of the account [uid] from [orders] (every status) and
/// [products]. [isBuyer] counts the orders it placed; otherwise the orders
/// it received as the seller and its own listings.
AccountActivity accountActivity({
  required String uid,
  required bool isBuyer,
  required Iterable<Map<String, dynamic>> orders,
  required Iterable<Map<String, dynamic>> products,
}) {
  var count = 0, pending = 0, inProgress = 0, completed = 0, cancelled = 0;
  num value = 0;
  final recent = <AccountActivityItem>[];

  for (final order in orders) {
    final mine = isBuyer
        ? order['buyerId'] == uid
        : (order['sellerId'] ?? order['farmerId']) == uid;
    if (!mine) continue;
    count++;
    final status = (order['status'] ?? '').toString().toLowerCase();
    switch (status) {
      case 'pending':
        pending++;
      case 'confirmed' || 'shipped':
        inProgress++;
      case 'completed':
        completed++;
        final total = order['total'];
        if (total is num) value += total;
      case 'cancelled' || 'rejected':
        cancelled++;
    }
    final when = _date(order['updatedAt']) ?? _date(order['createdAt']);
    if (when != null) {
      final product = (order['productName'] ?? 'Product').toString();
      recent.add(
        AccountActivityItem(
          isBuyer ? 'Ordered $product' : 'Order for $product',
          status.isEmpty
              ? 'Order'
              : '${status[0].toUpperCase()}${status.substring(1)}',
          when,
        ),
      );
    }
  }

  var active = 0, inactive = 0;
  if (!isBuyer) {
    for (final product in products) {
      if (product['farmerId'] != uid) continue;
      final off =
          product['isArchived'] == true || product['isSuspended'] == true;
      off ? inactive++ : active++;
      final when = _date(product['createdAt']);
      if (when != null) {
        recent.add(
          AccountActivityItem(
            'Posted ${(product['name'] ?? 'a listing').toString()}',
            off ? 'Archived or hidden' : 'Listing',
            when,
          ),
        );
      }
    }
  }

  recent.sort((a, b) => b.when.compareTo(a.when));
  return AccountActivity(
    orders: count,
    pending: pending,
    inProgress: inProgress,
    completed: completed,
    cancelled: cancelled,
    completedValue: value,
    activeListings: active,
    inactiveListings: inactive,
    recent: recent.take(AccountActivity.recentLimit).toList(),
    lastActivity: recent.isEmpty ? null : recent.first.when,
  );
}
