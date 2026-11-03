// The Supported Products list: from Add Product a product can be tapped,
// and it becomes the Product Name; elsewhere (registration) it is a list to
// read only.
import 'package:agritrade/screen/supported_products_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<Future<String?>> openList(
    WidgetTester tester, {
    required bool pickable,
  }) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final picked = Navigator.push<String>(
      ctx,
      MaterialPageRoute(
        builder: (_) => SupportedProductsScreen(pickable: pickable),
      ),
    );
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('from Add Product, a tapped product comes back as the name', (
    tester,
  ) async {
    final picked = await openList(tester, pickable: true);
    expect(find.textContaining('Tap a product'), findsOneWidget);

    await tester.tap(find.text('Corn'));
    await tester.pumpAndSettle();
    expect(await picked, 'Corn');
    expect(find.byType(SupportedProductsScreen), findsNothing);
  });

  testWidgets('elsewhere it is a list to read, nothing to tap', (tester) async {
    await openList(tester, pickable: false);
    expect(find.textContaining('Tap a product'), findsNothing);
    expect(
      find.ancestor(of: find.text('Corn'), matching: find.byType(InkWell)),
      findsNothing,
    );
  });
}
