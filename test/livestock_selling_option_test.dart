// Livestock is sold live only, in the commodity's own unit (kg liveweight
// or head) — for every commodity the Admin files under Livestock. Listings
// and orders saved as slaughtered before then still read as such.
import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/services/market_price_helpers.dart';
import 'package:agritrade/services/order_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    CommodityRegistry.instance.applyAdminRecords([
      {'name': 'Swine', 'category': 'Livestock', 'unit': 'kg liveweight'},
      {'name': 'Cattle', 'category': 'Livestock', 'unit': 'head'},
      {'name': 'Goat', 'category': 'livestock', 'unit': 'head'},
      {'name': 'Okra', 'category': 'Vegetables', 'unit': 'kg'},
    ]);
  });

  test('every Admin livestock commodity counts, whatever the capitals', () {
    expect(isLivestockCategory(categoryOfCommodity('Goat')), isTrue);
    expect(isLivestockCategory(categoryOfCommodity('Swine')), isTrue);
    expect(isLivestockCategory(categoryOfCommodity('Okra')), isFalse);
  });

  test('live is the only way livestock is sold', () {
    expect(SellingOption.values, [SellingOption.live]);
    expect(sellingOptionOf({'sellingOption': 'live'}), SellingOption.live);
    expect(sellingOptionOf({}), isNull);
    expect(unitForCommodity('Swine'), 'kg liveweight');
    expect(unitForCommodity('Cattle'), 'head');
  });

  test('a live listing is named as it is, with nothing added', () {
    expect(withSellingOption('Swine', {'sellingOption': 'live'}), 'Swine');
    expect(withSellingOption('Okra', {}), 'Okra');
    expect(
      const OrderInfo('o1', {
        'productName': 'Swine',
        'sellingOption': 'live',
      }).productName,
      'Swine',
    );
  });

  test('one saved as slaughtered before still says so', () {
    expect(isSlaughtered({'sellingOption': 'slaughtered'}), isTrue);
    expect(isSlaughtered({'sellingOption': 'live'}), isFalse);
    expect(
      withSellingOption('Cattle', {'sellingOption': 'slaughtered'}),
      'Cattle (Slaughtered)',
    );
    expect(
      const OrderInfo('o2', {
        'productName': 'Swine',
        'sellingOption': 'slaughtered',
      }).productName,
      'Swine (Slaughtered)',
    );
  });

  test('an old slaughtered listing never counts in the live average', () {
    final listings = [
      {
        'name': 'Swine',
        'commodity': 'swine',
        'unit': 'kg liveweight',
        'retailPrice': 180,
        'quantity': 5,
        'sellingOption': 'live',
      },
      {
        'name': 'Swine',
        'commodity': 'swine',
        'unit': 'kg liveweight',
        'retailPrice': 400,
        'quantity': 5,
        'sellingOption': 'slaughtered',
      },
    ];
    expect(liveAverageOfListings(listings, 'Swine'), 180);
  });
}
