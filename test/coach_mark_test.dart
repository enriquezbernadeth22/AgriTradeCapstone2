// The first-time tour: a bouncing arrow and a short label at each button,
// moved along by the user's own taps, never blocking them, and waiting
// while a popup is in front.
import 'package:agritrade/theme/app_colors.dart';
import 'package:agritrade/widgets/coach_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final addKey = GlobalKey();
  final ordersKey = GlobalKey();
  final steps = [
    CoachMarkStep(
      targetKey: addKey,
      title: 'List your first product',
      message: 'Tap here anytime to post crops.',
    ),
    CoachMarkStep(
      targetKey: ordersKey,
      title: 'Track incoming orders',
      message: 'Orders from buyers show up here.',
    ),
  ];

  Future<BuildContext> pumpHome(
    WidgetTester tester, {
    required VoidCallback onAdd,
  }) async {
    late BuildContext home;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            home = context;
            return Scaffold(
              body: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(height: 40),
                  TextButton(
                    key: ordersKey,
                    onPressed: () {},
                    child: const Text('Orders'),
                  ),
                  TextButton(
                    key: addKey,
                    onPressed: onAdd,
                    child: const Text('Add'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    return home;
  }

  testWidgets('taps move the tour along and still work', (tester) async {
    var added = 0;
    final home = await pumpHome(tester, onAdd: () => added++);
    var finished = false;
    showCoachMarksOnce(
      context: home,
      prefsKey: 'walkthrough_seen_test',
      steps: steps,
    ).then((_) => finished = true);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('List your first product'), findsOneWidget);
    // The page dims around the highlighted target, and the hint stays light.
    expect(find.byType(CustomPaint), findsWidgets);
    final hintCard = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('List your first product'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((hintCard.decoration! as BoxDecoration).color, AppColors.surface);

    // Tapping the button itself works, and brings up the next hint.
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(added, 1);
    expect(find.text('List your first product'), findsNothing);
    expect(find.text('Track incoming orders'), findsOneWidget);

    // Any tap, anywhere, ends it.
    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    await tester.pump();
    expect(find.text('Track incoming orders'), findsNothing);
    expect(finished, isTrue);
  });

  testWidgets('waits while a popup is in front', (tester) async {
    final home = await pumpHome(tester, onAdd: () {});
    showDialog<void>(
      context: home,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your Market tab'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
    showCoachMarksOnce(
      context: home,
      prefsKey: 'walkthrough_seen_popup_test',
      steps: steps,
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('List your first product'), findsNothing);

    // Closing the popup does not count as a step.
    await tester.tap(find.text('Got it'));
    // (The arrow keeps bouncing, so the page never "settles".)
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('List your first product'), findsOneWidget);

    // Finish the tour so nothing is left running.
    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    await tester.pump();
  });

  testWidgets('shown once per device', (tester) async {
    SharedPreferences.setMockInitialValues({'walkthrough_seen_test': true});
    final home = await pumpHome(tester, onAdd: () {});
    await showCoachMarksOnce(
      context: home,
      prefsKey: 'walkthrough_seen_test',
      steps: steps,
    );
    await tester.pump();
    expect(find.text('List your first product'), findsNothing);
  });

  testWidgets('Skip ends the tour and turns every other tip off', (
    tester,
  ) async {
    var added = 0;
    final home = await pumpHome(tester, onAdd: () => added++);
    var finished = false;
    showCoachMarksOnce(
      context: home,
      prefsKey: '${TutorialTips.tourKeyPrefix}skip_test',
      steps: steps,
    ).then((_) => finished = true);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('List your first product'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump();
    expect(find.text('List your first product'), findsNothing);
    expect(find.text('Track incoming orders'), findsNothing);
    expect(finished, isTrue);
    expect(added, 0);
    expect(await TutorialTips.isOff(), isTrue);

    // Another screen's tour does not show now.
    await showCoachMarksOnce(
      context: home,
      prefsKey: '${TutorialTips.tourKeyPrefix}another_screen',
      steps: steps,
    );
    await tester.pump();
    expect(find.text('List your first product'), findsNothing);
  });

  test(
    '"Show tips again" turns them back on and forgets what was seen',
    () async {
      SharedPreferences.setMockInitialValues({
        TutorialTips.offKey: true,
        '${TutorialTips.tourKeyPrefix}chat': true,
        'walkthrough_seen_buyer': true,
        'market_tab_hints_next_uid1': 2,
        'orders_swipe_tutorial_seen_uid1': true,
        'notification_permission_asked': true,
      });
      await TutorialTips.showAgain();
      final prefs = await SharedPreferences.getInstance();
      expect(await TutorialTips.isOff(), isFalse);
      expect(prefs.getBool('${TutorialTips.tourKeyPrefix}chat'), isNull);
      expect(prefs.getBool('walkthrough_seen_buyer'), isNull);
      expect(prefs.getInt('market_tab_hints_next_uid1'), isNull);
      expect(prefs.getBool('orders_swipe_tutorial_seen_uid1'), isNull);
      // Nothing else is touched.
      expect(prefs.getBool('notification_permission_asked'), isTrue);
    },
  );

  testWidgets('a button not on screen is left out of the tour', (tester) async {
    final home = await pumpHome(tester, onAdd: () {});
    final offScreen = GlobalKey();
    // A button far below the bottom of the screen.
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: 5000,
        child: SizedBox(key: offScreen, width: 40, height: 40),
      ),
    );
    Overlay.of(home).insert(entry);
    await tester.pump();

    showCoachMarksOnce(
      context: home,
      prefsKey: '${TutorialTips.tourKeyPrefix}offscreen_test',
      steps: [
        CoachMarkStep(
          targetKey: offScreen,
          title: 'Below the fold',
          message: 'Not shown.',
        ),
        steps.last,
      ],
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Below the fold'), findsNothing);
    expect(find.text('Track incoming orders'), findsOneWidget);
    // One step only, so no "1/2".
    expect(find.text('1/2'), findsNothing);

    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    await tester.pump();
    entry.remove();
  });

  testWidgets('one tour at a time: the next waits for the first to end', (
    tester,
  ) async {
    final home = await pumpHome(tester, onAdd: () {});
    showCoachMarksOnce(
      context: home,
      prefsKey: '${TutorialTips.tourKeyPrefix}first',
      steps: [steps.first],
    );
    showCoachMarksOnce(
      context: home,
      prefsKey: '${TutorialTips.tourKeyPrefix}second',
      steps: [steps.last],
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('List your first product'), findsOneWidget);
    expect(find.text('Track incoming orders'), findsNothing);

    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('List your first product'), findsNothing);
    expect(find.text('Track incoming orders'), findsOneWidget);

    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    await tester.pump();
  });
}
