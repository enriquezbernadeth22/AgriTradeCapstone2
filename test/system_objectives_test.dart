// Fixes so the system matches its stated objectives (2026-11-09): the
// farmer's total orders (1.4), several review photos (2.5), and each
// account's activity for the Admin (3.1).
import 'package:agritrade/screen/market_tab.dart';
import 'package:agritrade/services/account_activity.dart';
import 'package:agritrade/services/review_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Total Orders counts the farmer\'s completed orders, all time', () {
    expect(
      totalOrdersCount([
        {'status': 'completed'},
        {'status': 'Completed'},
        {'status': 'pending'},
        {'status': 'cancelled'},
      ]),
      2,
    );
    expect(totalOrdersCount(const []), 0);
  });

  test('a review keeps up to three photos, and older single ones', () {
    expect(ReviewService.maxPhotos, 3);
    expect(
      reviewPhotos({
        'imageUrl': 'a.jpg',
        'imageUrls': ['a.jpg', 'b.jpg', 'c.jpg'],
      }),
      ['a.jpg', 'b.jpg', 'c.jpg'],
    );
    expect(reviewPhotos({'imageUrl': 'old.jpg'}), ['old.jpg']);
    expect(reviewPhotos({'imageUrl': ''}), isEmpty);
  });

  group('an account\'s activity', () {
    Timestamp day(int d) => Timestamp.fromDate(DateTime(2026, 11, d));
    final orders = [
      {
        'buyerId': 'b1',
        'sellerId': 'f1',
        'status': 'completed',
        'total': 500,
        'productName': 'Corn',
        'createdAt': day(1),
      },
      {
        'buyerId': 'b1',
        'sellerId': 'f1',
        'status': 'pending',
        'total': 200,
        'productName': 'Okra',
        'createdAt': day(5),
      },
      {
        'buyerId': 'b2',
        'sellerId': 'f1',
        'status': 'rejected',
        'total': 90,
        'productName': 'Ube',
        'createdAt': day(3),
      },
      {
        'buyerId': 'b1',
        'sellerId': 'f2',
        'status': 'shipped',
        'total': 70,
        'productName': 'Rice',
        'createdAt': day(4),
      },
    ];
    final products = [
      {'farmerId': 'f1', 'name': 'Corn', 'createdAt': day(8)},
      {'farmerId': 'f1', 'name': 'Okra', 'isArchived': true},
      {'farmerId': 'f2', 'name': 'Rice'},
    ];

    test('a buyer: the orders they placed', () {
      final a = accountActivity(
        uid: 'b1',
        isBuyer: true,
        orders: orders,
        products: products,
      );
      expect(a.orders, 3);
      expect([a.pending, a.inProgress, a.completed, a.cancelled], [1, 1, 1, 0]);
      expect(a.completedValue, 500);
      expect(a.activeListings, 0);
      expect(a.recent.first.title, 'Ordered Okra');
      expect(a.lastActivity, DateTime(2026, 11, 5));
    });

    test('a farmer: the orders they received and their listings', () {
      final a = accountActivity(
        uid: 'f1',
        isBuyer: false,
        orders: orders,
        products: products,
      );
      expect(a.orders, 3);
      expect(a.cancelled, 1);
      expect(a.completedValue, 500);
      expect([a.activeListings, a.inactiveListings], [1, 1]);
      // The newest first: the listing posted on the 8th.
      expect(a.recent.first.title, 'Posted Corn');
      expect(a.recent.length, lessThanOrEqualTo(AccountActivity.recentLimit));
    });

    test('nothing yet', () {
      final a = accountActivity(
        uid: 'new',
        isBuyer: true,
        orders: orders,
        products: products,
      );
      expect(a.orders, 0);
      expect(a.lastActivity, isNull);
    });
  });
}
