// Explore's "new posts" pill: a buyer sees that farmers have posted since
// the feed was loaded, and one tap brings those posts in.
import 'package:agritrade/widgets/new_posts_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, int count, VoidCallback onTap) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NewPostsPill(count: count, onTap: onTap),
            ),
          ),
        ),
      );

  test('the label counts the posts, singular for one', () {
    expect(NewPostsPill.label(1), '1 new post');
    expect(NewPostsPill.label(3), '3 new posts');
  });

  testWidgets('new posts show the pill, and tapping it brings them in', (
    tester,
  ) async {
    var taps = 0;
    await pump(tester, 2, () => taps++);
    await tester.pumpAndSettle();
    expect(find.text('2 new posts'), findsOneWidget);
    await tester.tap(find.text('2 new posts'));
    expect(taps, 1);
  });

  testWidgets('with no new posts the pill is hidden and cannot be tapped', (
    tester,
  ) async {
    var taps = 0;
    await pump(tester, 2, () => taps++);
    await tester.pumpAndSettle();
    await pump(tester, 0, () => taps++);
    await tester.pumpAndSettle();
    // Faded out, still showing the last count rather than "0 new posts".
    final opacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    );
    expect(opacity.opacity, 0);
    expect(find.text('0 new posts'), findsNothing);
    await tester.tap(find.byType(NewPostsPill), warnIfMissed: false);
    expect(taps, 0);
  });
}
