// "What best describes you": saved with the account, and used to show bulk
// buyers the wholesale price first, to suggest a farmer's kind of product
// first, and in the Export Report.
import 'package:agritrade/data/account_types.dart';
import 'package:agritrade/services/auth_service.dart';
import 'package:agritrade/services/buyer_type_watcher.dart';
import 'package:agritrade/services/market_report_sections.dart';
import 'package:agritrade/widgets/explore_product_card.dart';
import 'package:agritrade/widgets/registration_role_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the answer goes in the field of the role', () {
    expect(accountTypeField('farmer'), 'farmerType');
    expect(accountTypeField('buyer'), 'buyerType');
    expect(
      accountTypeOf({'role': 'farmer', 'farmerType': 'Crop Farmer'}),
      'Crop Farmer',
    );
    expect(accountTypeOf({'role': 'buyer'}), isNull);
  });

  test('the answer survives the wait for email verification', () {
    const profile = PendingRegistrationProfile(
      role: 'buyer',
      fullName: 'Ana Go',
      accountType: 'Market Vendor',
    );
    expect(
      PendingRegistrationProfile.fromJson(profile.toJson()).accountType,
      'Market Vendor',
    );
  });

  test('only buyers who order in bulk see wholesale first', () {
    bool first(Map<String, dynamic> profile) =>
        BuyerTypeWatcher.isWholesaleBuyer(profile);

    for (final type in kWholesaleBuyerTypes) {
      expect(first({'role': 'buyer', 'buyerType': type}), isTrue);
    }
    expect(
      first({'role': 'buyer', 'buyerType': 'Individual Consumer'}),
      isFalse,
    );
    expect(first({'role': 'buyer', 'buyerType': 'Other'}), isFalse);
    expect(first({'role': 'buyer'}), isFalse);
    expect(first({'role': 'farmer', 'farmerType': 'Crop Farmer'}), isFalse);
  });

  group('the suggestions in Add Product', () {
    const names = ['Corn', 'Cattle', 'Eggplant', 'Chicken'];
    String? categoryOf(String name) =>
        const {'Cattle', 'Chicken'}.contains(name) ? 'Livestock' : 'Vegetables';
    List<String> order(String? type) =>
        orderForFarmerType(names, farmerType: type, categoryOf: categoryOf);

    test('a Livestock Farmer sees animals first', () {
      expect(order('Livestock Farmer'), [
        'Cattle',
        'Chicken',
        'Corn',
        'Eggplant',
      ]);
    });

    test('a Crop Farmer sees crops first', () {
      expect(order('Crop Farmer'), ['Corn', 'Eggplant', 'Cattle', 'Chicken']);
    });

    test('nobody loses a product, and the rest keep the usual order', () {
      expect(order('Both Crop and Livestock'), names);
      expect(order(null), names);
      expect(order('Livestock Farmer').toSet(), names.toSet());
    });
  });

  testWidgets('the registration question says when it is still needed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RegistrationRoleDetails(
            isFarmer: false,
            value: null,
            showRequired: true,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Please choose what best describes you.'), findsOneWidget);
  });

  group('the Explore card', () {
    const product = {
      'name': 'Corn',
      'category': 'Vegetables',
      'farmerName': 'Juan',
      'retailPrice': 50,
      'wholesalePrice': 40,
      'wholesaleEnabled': true,
      'wholesaleMinimumQuantity': 10,
      'quantity': 100,
      'unit': 'kg',
    };
    tearDown(() => BuyerTypeWatcher.instance.debugSet(false));

    Future<void> pumpCard(WidgetTester tester) => tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 320,
            child: ExploreProductCard(data: product),
          ),
        ),
      ),
    );

    testWidgets('shows retail first to most people', (tester) async {
      await pumpCard(tester);
      expect(find.textContaining('50.00'), findsOneWidget);
      expect(find.text('Wholesale'), findsOneWidget);
      expect(find.text('Min 10 kg'), findsOneWidget);
    });

    testWidgets('shows wholesale first to a bulk buyer', (tester) async {
      BuyerTypeWatcher.instance.debugSet(true);
      await pumpCard(tester);
      expect(find.textContaining('40.00'), findsOneWidget);
      expect(find.text('Wholesale'), findsOneWidget);
      expect(find.text('Min 10 kg'), findsOneWidget);
    });
  });

  group('Buyers by Type in the report', () {
    test('counts every buyer, older accounts as not specified', () {
      final section = MarketReportSections.buyersByType([
        {'role': 'buyer', 'buyerType': 'Market Vendor'},
        {'role': 'buyer', 'buyerType': 'Market Vendor'},
        {'role': 'buyer', 'buyerType': 'Individual Consumer'},
        {'role': 'buyer'},
        {'role': 'farmer', 'farmerType': 'Crop Farmer'},
      ]);

      expect(section.rows, [
        ['Market Vendor', 2, '50.0%'],
        ['Individual Consumer', 1, '25.0%'],
        ['Not specified', 1, '25.0%'],
        ['Total', 4, '100%'],
      ]);
    });

    test('with no buyers there are no rows', () {
      expect(MarketReportSections.buyersByType(const []).rows, isEmpty);
    });
  });
}
