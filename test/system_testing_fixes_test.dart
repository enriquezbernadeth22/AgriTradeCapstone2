// The panel's system-testing findings (2026-11-09): livestock sold by the
// animal, newest posts first, Luzon-only delivery areas and the bottom bar
// coming back on a page that no longer scrolls.
import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/data/ph_locations_service.dart';
import 'package:agritrade/services/delivery_coverage.dart';
import 'package:agritrade/services/filters_on_scroll.dart';
import 'package:agritrade/services/market_price_helpers.dart';
import 'package:agritrade/services/newest_first.dart';
import 'package:agritrade/services/pricing_tier_service.dart';
import 'package:agritrade/services/product_share_service.dart';
import 'package:agritrade/widgets/delivery_area_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('livestock sold per head or piece', () {
    final pigPerHead = <String, dynamic>{
      'name': 'Swine',
      'commodity': 'Swine',
      'category': 'Livestock',
      'unit': 'head',
      'quantity': 4,
      'wholesaleEnabled': true,
      'wholesalePrice': 9000,
      'wholesaleMinimumQuantity': 2,
    };
    final pigByWeight = <String, dynamic>{
      ...pigPerHead,
      'unit': 'kg liveweight',
    };
    final eggplant = <String, dynamic>{
      'name': 'Eggplant',
      'category': 'Vegetables',
      'unit': 'kg',
      'wholesaleEnabled': true,
      'wholesalePrice': 40,
      'wholesaleMinimumQuantity': 10,
    };

    test('Head and Piece are offered, with the weight unit kept', () {
      expect(livestockUnitChoices('kg liveweight'), [
        'head',
        'piece',
        'kg liveweight',
      ]);
      expect(livestockUnitChoices('head'), ['head', 'piece']);
      expect(defaultLivestockUnit('kg liveweight'), 'head');
      expect(defaultLivestockUnit('head'), 'head');
      expect(unitChoiceLabel('piece'), 'Piece');
    });

    test('only livestock counted by the animal is sold per animal', () {
      expect(isSoldPerAnimal(pigPerHead), isTrue);
      expect(isSoldPerAnimal({...pigPerHead, 'unit': 'piece'}), isTrue);
      expect(isSoldPerAnimal(pigByWeight), isFalse);
      expect(isSoldPerAnimal(eggplant), isFalse);
      // Coconut is counted by the piece, but it is not livestock.
      expect(
        isSoldPerAnimal({
          'name': 'Coconut',
          'category': 'Fruits',
          'unit': 'piece',
        }),
        isFalse,
      );
      // An order (productName) or a chat card with no category.
      expect(
        isSoldPerAnimal({'productName': 'Cattle', 'unit': 'head'}),
        isTrue,
      );
    });

    test('buyers see "Available", not how many are left', () {
      expect(buyerStockLabel(pigPerHead, 4, 'head'), 'Available');
      expect(
        buyerStockLabel(pigByWeight, 120, 'kg liveweight'),
        '120 kg liveweight',
      );
      expect(
        productShareText(
          name: 'Swine',
          price: 12000,
          unit: 'head',
          quantity: 4,
          location: '',
          link: Uri.parse('https://example.com/p/1'),
          soldPerAnimal: true,
        ),
        allOf(contains('Available'), isNot(contains('4 heads'))),
      );
    });

    test('no wholesale, even for a listing saved with one before', () {
      expect(PricingTierService.wholesaleAvailable(pigPerHead), isFalse);
      expect(listingHasWholesale(pigPerHead), isFalse);
      expect(PricingTierService.wholesaleAvailable(pigByWeight), isTrue);
      expect(listingHasWholesale(eggplant), isTrue);
    });
  });

  test('Explore lists the newest post first', () {
    Map<String, dynamic> posted(int day) => {
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, day)),
    };
    final feed = newestFirst([
      ('old', posted(1)),
      ('newest', posted(9)),
      ('middle', posted(5)),
      // Just posted: the server's time is not back yet.
      ('pending', <String, dynamic>{}),
    ], (item) => item.$2);
    expect(
      [for (final f in feed) f.$1],
      ['pending', 'newest', 'middle', 'old'],
    );
  });

  group('delivery areas are Luzon only', () {
    test('Luzon is regions 01-05, NCR, CAR and MIMAROPA', () {
      for (final code in [
        '010000000',
        '040000000',
        '130000000',
        '140000000',
        '170000000',
      ]) {
        expect(isLuzonRegionCode(code), isTrue, reason: code);
      }
      // Visayas and Mindanao.
      for (final code in ['070000000', '110000000', '160000000']) {
        expect(isLuzonRegionCode(code), isFalse, reason: code);
      }
    });

    const places = [
      LuzonPlace(name: 'Tagaytay City', province: 'Cavite', group: 'Cavite'),
      LuzonPlace(name: 'Talisay', province: 'Batangas', group: 'Batangas'),
      LuzonPlace(name: 'Laurel', province: 'Batangas', group: 'Batangas'),
      LuzonPlace(name: 'Alaminos', province: 'Laguna', group: 'Laguna'),
    ];

    test('towns are listed under their provinces, the farm\'s first', () {
      final groups = groupDeliveryAreas(places, originProvince: 'Laguna');
      expect(
        [for (final g in groups) g.name],
        ['Laguna', 'Batangas', 'Cavite'],
      );
      expect([for (final a in groups[1].areas) a.name], ['Laurel', 'Talisay']);
    });

    test('searching finds a town or a whole province', () {
      final groups = groupDeliveryAreas(places);
      final town = searchDeliveryAreas(groups, 'tali');
      expect(town.single.name, 'Batangas');
      expect(town.single.areas.single.name, 'Talisay');
      final province = searchDeliveryAreas(groups, 'batan');
      expect(province.single.areas.length, 2);
    });

    testWidgets('ticking a province chooses all of its towns', (tester) async {
      List<DeliveryArea>? done;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                done = await Navigator.of(context).push<List<DeliveryArea>>(
                  MaterialPageRoute(
                    builder: (_) => const Scaffold(
                      body: DeliveryAreaPicker(
                        initial: [],
                        originProvince: 'Batangas',
                        places: places,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Luzon only'), findsOneWidget);
      await tester.tap(find.byKey(const Key('deliveryGroupAll_Batangas')));
      await tester.pump();
      expect(find.text('2 towns/cities in 1 provinces'), findsOneWidget);
      // Cavite starts closed: open it and add Tagaytay.
      await tester.tap(find.byKey(const Key('deliveryGroup_Cavite')));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('deliveryTown_Tagaytay City, Cavite')),
      );
      await tester.pump();
      expect(find.text('3 towns/cities in 2 provinces'), findsOneWidget);
      await tester.tap(find.text('Done (3 selected)'));
      await tester.pumpAndSettle();
      expect(done?.map((a) => a.label).toSet(), {
        'Laurel, Batangas',
        'Talisay, Batangas',
        'Tagaytay City, Cavite',
      });
    });

    test('a coverage is shown under its provinces', () {
      final grouped = areasByProvince(const [
        DeliveryArea('Tagaytay City', 'Cavite'),
        DeliveryArea('Talisay', 'Batangas'),
        DeliveryArea('Laurel', 'Batangas'),
      ]);
      expect(grouped.map((g) => g.province), ['Batangas', 'Cavite']);
      expect(grouped.first.towns, ['Laurel', 'Talisay']);
    });
  });

  group('the bottom bar on a page that changed size', () {
    ScrollMetrics metrics({required double max, required double pixels}) =>
        FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: max,
          pixels: pixels,
          viewportDimension: 600,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 2,
        );

    test('comes back when the page no longer scrolls', () {
      final onScroll = FiltersOnScroll(showAfterUp: 24);
      // Scrolled down: hidden.
      expect(onScroll.update(delta: 80, pixels: 300, dragging: true), isTrue);
      // Buyer Areas is shorter: the page now fits on the screen.
      expect(onScroll.metricsChanged(metrics(max: 0, pixels: 0)), isFalse);
    });

    test('stays as it is while the page still scrolls', () {
      final onScroll = FiltersOnScroll(showAfterUp: 24);
      expect(onScroll.metricsChanged(metrics(max: 900, pixels: 300)), isNull);
      expect(onScroll.metricsChanged(metrics(max: 900, pixels: 0)), isFalse);
    });
  });
}
