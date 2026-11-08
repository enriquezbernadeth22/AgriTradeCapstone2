import 'package:agritrade/widgets/explore_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the farm scene sits at the right even under loose constraints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Explore holds the hero in an AnimatedSize, which loosens its width.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: const ExploreHero(
                  title: 'Explore',
                  subtitle: 'Discover quality crops.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final scene = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is FarmScenePainter,
    );
    expect(tester.getRect(scene).right, moreOrLessEquals(390));
  });
}
