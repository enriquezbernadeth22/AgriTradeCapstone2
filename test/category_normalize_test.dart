import 'package:agritrade/data/commodity_master_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('three built-in categories', () {
    expect(kBuiltInCategories, ['Vegetables', 'Fruits', 'Livestock']);
  });

  test('root crops and spices count as Vegetables, however typed', () {
    for (final old in [
      'Root Crops',
      ' root crops ',
      'ROOT_CROPS',
      'Root crop',
      'Spices',
      'spice',
    ]) {
      expect(normalizeCategory(old), 'Vegetables', reason: old);
    }
  });

  test('built-in categories in their usual spelling; others as typed', () {
    expect(normalizeCategory('vegetables'), 'Vegetables');
    expect(normalizeCategory(' FRUITS '), 'Fruits');
    expect(normalizeCategory('livestock'), 'Livestock');
    // A category the Admin added stays as they typed it.
    expect(normalizeCategory('Grains'), 'Grains');
    expect(normalizeCategory(' Mushrooms '), 'Mushrooms');
    expect(normalizeCategory(null), '');
    expect(normalizeCategory('  '), '');
  });

  test('the commodity list shows root crops and spices under Vegetables', () {
    CommodityRegistry.instance.applyAdminRecords([
      {'name': 'Ube', 'category': 'Root Crops', 'unit': 'kg'},
      {'name': 'Ginger', 'category': 'Spices', 'unit': 'kg'},
      {'name': 'Banana', 'category': 'Fruits', 'unit': 'kg'},
      {'name': 'Rice', 'category': 'Grains', 'unit': 'kg'},
    ]);
    addTearDown(() => CommodityRegistry.instance.applyAdminRecords(const []));
    expect(categoryOfCommodity('Ube'), 'Vegetables');
    expect(categoryOfCommodity('Ginger'), 'Vegetables');
    expect(CommodityRegistry.instance.categories.toSet(), {
      'Vegetables',
      'Fruits',
      'Grains',
    });
  });
}
