// A little more life in the mobile app: a farmland banner on top of the
// Explore feed, and a picture of fresh produce on the empty pages buyers
// see most (no products, no liked products, no orders).
import 'package:agritrade/widgets/agri_empty_state.dart';
import 'package:agritrade/widgets/explore_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the Explore banner: farmland, and words only', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExploreBanner())),
    );
    expect(find.text('Fresh from Laurel farms'), findsOneWidget);
    expect(
      find.text('Buy straight from the farmers who grow it.'),
      findsOneWidget,
    );
    expect(find.image(const AssetImage(ExploreBanner.art)), findsOneWidget);
  });

  testWidgets('an empty page can show the produce picture instead of the '
      'icon', (tester) async {
    Future<void> empty({String? art}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgriEmptyState(
            icon: Icons.favorite_border_rounded,
            art: art,
            title: 'No liked products yet',
          ),
        ),
      ),
    );

    await empty(art: kEmptyProduceArt);
    expect(find.image(const AssetImage(kEmptyProduceArt)), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);

    await empty();
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
  });
}
