// The home screens' tabs: a swipe does not move them (only the bar does),
// and each tab keeps its state.
import 'package:agritrade/widgets/swipeable_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Counter extends StatefulWidget {
  final String name;
  const _Counter(this.name);
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var taps = 0;
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => taps++),
      child: Text('${widget.name} $taps'),
    ),
  );
}

void main() {
  testWidgets(
    'no swipe between tabs; the bar moves them, each keeps its state',
    (tester) async {
      var index = 0;
      late StateSetter setIndex;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setIndex = setState;
              return Scaffold(
                body: SwipeableTabs(
                  index: index,
                  onIndexChanged: (i) => setState(() => index = i),
                  children: const [
                    _Counter('Market'),
                    _Counter('Messages'),
                    _Counter('Orders'),
                    _Counter('Profile'),
                  ],
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Market 0'));
      await tester.pump();
      expect(find.text('Market 1'), findsOneWidget);

      // A swipe does nothing: the tabs move only from the bar.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle();
      expect(index, 0);
      expect(find.text('Market 1'), findsOneWidget);

      // A tap on the bar, the next tab: it slides in.
      setIndex(() => index = 1);
      await tester.pumpAndSettle();
      expect(find.text('Messages 0'), findsOneWidget);

      // A tap on the bar, two tabs away: straight there.
      setIndex(() => index = 3);
      await tester.pumpAndSettle();
      expect(find.text('Profile 0'), findsOneWidget);

      // Back to the first tab: what was done there is still there.
      setIndex(() => index = 0);
      await tester.pumpAndSettle();
      expect(find.text('Market 1'), findsOneWidget);
    },
  );
}
