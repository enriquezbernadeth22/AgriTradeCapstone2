import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/services/harvest_info.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('six built-in categories, Root Crops and Spices among them', () {
    expect(kBuiltInCategories, [
      'Grains',
      'Root Crops',
      'Vegetables',
      'Spices',
      'Fruits',
      'Livestock',
    ]);
  });

  test('root crops and spices are their own categories, however typed', () {
    for (final typed in [
      'Root Crops',
      ' root crops ',
      'ROOT_CROPS',
      'Root crop',
    ]) {
      expect(normalizeCategory(typed), 'Root Crops', reason: typed);
    }
    for (final typed in ['Spices', 'spice', ' SPICES ']) {
      expect(normalizeCategory(typed), 'Spices', reason: typed);
    }
  });

  test('built-in categories in their usual spelling; others as typed', () {
    expect(normalizeCategory('vegetables'), 'Vegetables');
    expect(normalizeCategory(' FRUITS '), 'Fruits');
    expect(normalizeCategory('livestock'), 'Livestock');
    expect(normalizeCategory('grains'), 'Grains');
    // A category the Admin added stays as they typed it.
    expect(normalizeCategory(' Mushrooms '), 'Mushrooms');
    expect(normalizeCategory(null), '');
    expect(normalizeCategory('  '), '');
  });

  test('built-in root crops and spices the Admin saved as Vegetables while '
      'they were merged go back; an Admin vegetable stays', () {
    CommodityRegistry.instance.applyAdminRecords([
      {'name': 'Sweet Potato', 'category': 'Vegetables', 'unit': 'kg'},
      {'name': 'Turmeric', 'category': 'Vegetables', 'unit': 'kg'},
      {'name': 'Pechay', 'category': 'Vegetables', 'unit': 'kg'},
    ]);
    addTearDown(() => CommodityRegistry.instance.applyAdminRecords(const []));
    expect(categoryOfCommodity('Sweet Potato'), 'Root Crops');
    expect(categoryOfCommodity('Turmeric'), 'Spices');
    expect(categoryOfCommodity('Pechay'), 'Vegetables');
  });

  group('with the Admin\'s commodity list', () {
    setUp(
      () => CommodityRegistry.instance.applyAdminRecords([
        {'name': 'Banana', 'category': 'Fruits', 'unit': 'kg'},
        {'name': 'Ginger', 'category': 'Spices', 'unit': 'kg'},
        {'name': 'Eggplant', 'category': 'Vegetables', 'unit': 'kg'},
        {'name': 'Ube', 'category': 'root crops', 'unit': 'kg'},
        {'name': 'Rice', 'category': 'Grains', 'unit': 'kg'},
        {'name': 'Kabute', 'category': 'Mushrooms', 'unit': 'kg'},
      ]),
    );
    tearDown(() => CommodityRegistry.instance.applyAdminRecords(const []));

    test('root crops and spices show under their own categories', () {
      expect(categoryOfCommodity('Ube'), 'Root Crops');
      expect(categoryOfCommodity('Ginger'), 'Spices');
    });

    test('categories are listed in the built-in order, then the rest', () {
      expect(CommodityRegistry.instance.categories, [
        'Grains',
        'Root Crops',
        'Vegetables',
        'Spices',
        'Fruits',
        'Mushrooms',
      ]);
      expect(CommodityRegistry.instance.activeByCategory.keys, [
        'Grains',
        'Root Crops',
        'Vegetables',
        'Spices',
        'Fruits',
        'Mushrooms',
      ]);
    });

    test('a root crop or spice saved as Vegetables while they were merged '
        'counts under its own category again', () {
      expect(
        listingCategory({'commodity': 'Ube', 'category': 'Vegetables'}),
        'Root Crops',
      );
      expect(
        listingCategory({
          'productName': 'Fresh Ginger',
          'category': 'Vegetables',
        }),
        'Spices',
      );
      // Real vegetables, and other categories, stay as saved.
      expect(
        listingCategory({'commodity': 'Eggplant', 'category': 'Vegetables'}),
        'Vegetables',
      );
      expect(
        listingCategory({'commodity': 'Ube', 'category': 'Fruits'}),
        'Fruits',
      );
      expect(
        listingCategory({'name': 'Mystery', 'category': 'vegetables'}),
        'Vegetables',
      );
      expect(listingCategory(null), '');
    });

    test('root crops and spices keep their harvest date', () {
      final harvested = Timestamp.fromDate(DateTime(2026, 11, 1));
      expect(
        harvestDateOf({'category': 'Root Crops', 'harvestDate': harvested}),
        DateTime(2026, 11, 1),
      );
      expect(
        harvestDateOf({'category': 'Spices', 'harvestDate': harvested}),
        DateTime(2026, 11, 1),
      );
      expect(
        harvestDateOf({'category': 'Livestock', 'harvestDate': harvested}),
        isNull,
      );
    });
  });
}
