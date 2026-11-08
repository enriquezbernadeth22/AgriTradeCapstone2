// The heart over a product photo: a 36 circle, an 18 heart, a 44 tap area,
// red and filled once liked. The product cards keep their own heart.
import 'package:agritrade/widgets/save_product_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<int> show(WidgetTester tester, {required bool liked}) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LikeHeart(
              liked: liked,
              size: SaveProductButton.size,
              iconSize: SaveProductButton.iconSize,
              tapTarget: SaveProductButton.tapTarget,
              background: Colors.white.withValues(alpha: 0.95),
              elevation: 1,
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    final area = tester.getRect(find.byType(GestureDetector).first);
    expect(area.size, const Size.square(44));
    expect(tester.getSize(find.byType(Material).last), const Size.square(36));
    // A tap near the corner of the 44 area, outside the circle, counts.
    await tester.tapAt(area.topLeft + const Offset(2, 2));
    await tester.pump(const Duration(milliseconds: 300));
    return taps;
  }

  testWidgets('the photo heart: 36 to see, 44 to tap, 18 heart', (
    tester,
  ) async {
    expect(await show(tester, liked: false), 1);
    final heart = tester.widget<Icon>(
      find.byIcon(Icons.favorite_border_rounded),
    );
    expect(heart.size, 18);
  });

  testWidgets('liked: the heart is filled red', (tester) async {
    await show(tester, liked: true);
    final heart = tester.widget<Icon>(find.byIcon(Icons.favorite_rounded));
    expect(heart.color, LikeHeart.likedColor);
  });

  testWidgets('a product card heart is unchanged: the circle is the tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: LikeHeart(liked: false, onTap: () {})),
        ),
      ),
    );
    expect(tester.getSize(find.byType(LikeHeart)), const Size.square(34));
    expect(tester.getSize(find.byType(Material).last), const Size.square(34));
  });
}
