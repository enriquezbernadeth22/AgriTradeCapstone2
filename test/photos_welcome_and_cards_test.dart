// Photos open full screen and can be swiped through; the welcome popup
// greets a new user before Help & Support; and the buyer's product grids
// show the product alone, without the farmer line.
import 'package:agritrade/services/notification_navigation_service.dart';
import 'package:agritrade/widgets/chat_photo_viewer.dart';
import 'package:agritrade/widgets/explore_product_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('a photo opens full screen at the one tapped, and the rest '
      'are a swipe away', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openPhotoGallery(context, const [
                'https://example.com/1.jpg',
                'https://example.com/2.jpg',
                'https://example.com/3.jpg',
              ], initialIndex: 1),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byKey(const Key('saveToGallery')), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets('one photo shows no counter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PhotoGalleryViewer(urls: ['https://example.com/1.jpg']),
      ),
    );
    await tester.pump();
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('the welcome popup greets the user by first name and closes '
      'only with Get Started', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await showWelcomeDialog(
                  context,
                  name: 'Ana Cruz',
                  farmer: false,
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to AgriTrade+, Ana!'), findsOneWidget);
    expect(find.textContaining('connect with farmers'), findsOneWidget);

    // A tap outside does not close it.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to AgriTrade+, Ana!'), findsOneWidget);

    await tester.tap(find.byKey(const Key('welcomeGetStarted')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to AgriTrade+, Ana!'), findsNothing);
    expect(closed, isTrue);
  });

  testWidgets('a farmer is welcomed with what the app does for farmers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showWelcomeDialog(context, farmer: true),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to AgriTrade+!'), findsOneWidget);
    expect(find.textContaining('manage your products'), findsOneWidget);
  });

  testWidgets('a product card in the buyer\'s grid has no farmer line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 170,
            height: ExploreProductCard.extentFor(170, TextScaler.noScaling),
            child: const ExploreProductCard(
              data: {
                'name': 'Eggplant',
                'category': 'Vegetables',
                'retailPrice': 60,
                'unit': 'kg',
                'quantity': 20,
                'farmerName': 'Juan dela Cruz',
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Eggplant'), findsOneWidget);
    expect(find.text('Juan dela Cruz'), findsNothing);
  });
}
