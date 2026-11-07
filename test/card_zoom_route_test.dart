// Opening a product from its card: the page grows out of the tapped card
// (not a sideways slide), keeps its state once open, and Back shrinks it
// into the card again.
import 'package:agritrade/widgets/card_zoom_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _pageStarts = 0;

class _Page extends StatefulWidget {
  const _Page();
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    _pageStarts++;
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Product page')));
}

void main() {
  testWidgets('grows from the tapped card, keeps its state, and goes back', (
    tester,
  ) async {
    _pageStarts = 0;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: Builder(
              builder: (cardContext) => GestureDetector(
                onTap: () => openFromCard(cardContext, const _Page()),
                child: const SizedBox(
                  key: Key('card'),
                  width: 160,
                  height: 200,
                  child: ColoredBox(color: Colors.green),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Early on, the page is about the card's size and where the card is.
    final early = tester.getRect(find.byType(FittedBox));
    expect(early.width, lessThan(260));
    expect(early.center.dx, greaterThan(200));
    expect(early.center.dy, greaterThan(400));

    await tester.pumpAndSettle();
    expect(find.text('Product page'), findsOneWidget);
    expect(tester.getRect(find.byType(FittedBox)).size, const Size(400, 800));
    // Opened once: the end of the animation did not build it anew.
    expect(_pageStarts, 1);

    Navigator.of(tester.element(find.text('Product page'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Product page'), findsNothing);
    expect(find.byKey(const Key('card')), findsOneWidget);
  });
}
