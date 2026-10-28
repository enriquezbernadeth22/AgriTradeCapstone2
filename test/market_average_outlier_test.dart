import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/services/market_price_helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: subtype_of_sealed_class

// The Current Market Average leaves out an unusually high or low asking
// price before averaging, by the suggested selling price's own rule.
class _Doc extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic> _data;
  _Doc(this.id, this._data);

  @override
  Map<String, dynamic> data() => _data;
}

void main() {
  final unit = unitForCommodity('Tomato');

  _Doc listing(String id, num price) => _Doc(id, {
    'name': 'Tomato',
    'commodity': 'Tomato',
    'category': 'Vegetables',
    'unit': unit,
    'quantity': 10,
    'retailPrice': price,
  });

  test('one far-off asking price does not pull the average', () {
    final products = [
      listing('a', 60),
      listing('b', 62),
      listing('c', 58),
      listing('d', 60),
      listing('e', 500),
    ];

    expect(computeLiveAverage(products, 'Tomato'), 60);
  });

  test('with fewer than 4 listings every price counts', () {
    final products = [listing('a', 60), listing('b', 500)];

    expect(computeLiveAverage(products, 'Tomato'), 280);
  });

  test('ordinary spread is averaged as is', () {
    final products = [
      listing('a', 50),
      listing('b', 60),
      listing('c', 70),
      listing('d', 80),
    ];

    expect(computeLiveAverage(products, 'Tomato'), 65);
  });
}
