// The main tabs' header is a plain rectangular bar: logo and name on the
// left, the notification bell and Settings gear on the right.
import 'package:agritrade/widgets/agritrade_text.dart';
import 'package:agritrade/widgets/notification_bell.dart';
import 'package:agritrade/widgets/page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the band is rectangular, with no rounded corners', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PageHeader(
            title: 'Market',
            trailing: Icon(Icons.notifications),
          ),
        ),
      ),
    );

    final band = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(PageHeader),
            matching: find.byWidgetPredicate(
              (widget) => widget is Container && widget.decoration != null,
            ),
          )
          .first,
    );
    final look = band.decoration! as BoxDecoration;
    expect(look.borderRadius, isNull);
    expect(look.boxShadow, isNotEmpty);
  });

  // The real bell, without the unread count it reads from Firebase.
  Widget shell({
    VoidCallback? onSettings,
    VoidCallback? onBell,
    int unread = 0,
  }) => MediaQuery(
    data: const MediaQueryData(size: Size(360, 640)),
    child: MaterialApp(
      home: Scaffold(
        body: HomeLogoAction(
          onTap: () {},
          onSettings: onSettings,
          child: PageHeader(
            title: 'Market',
            trailing: NotificationBellButton(
              onPressed: onBell ?? () {},
              unread: unread,
            ),
          ),
        ),
      ),
    ),
  );

  final bell = find.byIcon(Icons.notifications_none_rounded);
  final gear = find.byIcon(Icons.settings_outlined);

  void phoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the gear sits beside the bell, and the logo stays on the left', (
    tester,
  ) async {
    await tester.pumpWidget(shell(onSettings: () {}));

    expect(
      tester.getTopLeft(find.byType(AgriTradeText)).dx,
      lessThan(tester.getTopLeft(bell).dx),
    );
    expect(tester.getTopLeft(bell).dx, lessThan(tester.getTopLeft(gear).dx));
  });

  testWidgets('bell and gear are 26px apart, 21px from the screen edge', (
    tester,
  ) async {
    phoneScreen(tester);
    await tester.pumpWidget(shell(onSettings: () {}));

    expect(tester.getTopLeft(gear).dx - tester.getTopRight(bell).dx, 26);
    expect(360 - tester.getTopRight(gear).dx, 21);
  });

  testWidgets('both icons are the same size, on the same line', (tester) async {
    phoneScreen(tester);
    await tester.pumpWidget(shell(onSettings: () {}));

    expect(tester.getSize(bell), tester.getSize(gear));
    expect(tester.getCenter(bell).dy, tester.getCenter(gear).dy);
  });

  testWidgets('the header stays 56 tall, with a full tap area on each', (
    tester,
  ) async {
    phoneScreen(tester);
    await tester.pumpWidget(shell(onSettings: () {}));

    final band = find.ancestor(of: bell, matching: find.byType(Container));
    expect(tester.getSize(band.first).height, 56);
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(tester.getSize(find.byWidget(button)), const Size(48, 48));
    }
  });

  testWidgets('the unread badge stays on the bell, clear of the gear', (
    tester,
  ) async {
    phoneScreen(tester);
    await tester.pumpWidget(shell(onSettings: () {}, unread: 3));

    final badge = tester.getRect(
      find.ancestor(of: find.text('3'), matching: find.byType(Container)).first,
    );
    final icon = tester.getRect(bell);
    expect(badge.overlaps(icon), isTrue);
    expect(badge.top, lessThan(icon.top));
    expect(badge.right, greaterThan(icon.right));
    expect(badge.right, lessThan(tester.getRect(gear).left));
  });

  testWidgets('a large unread count stops at 99+, and none hides the badge', (
    tester,
  ) async {
    await tester.pumpWidget(shell(unread: 120));
    expect(find.text('99+'), findsOneWidget);

    await tester.pumpWidget(shell());
    expect(find.text('99+'), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('the bell and the gear each do their own job', (tester) async {
    phoneScreen(tester);
    var bellTaps = 0;
    var gearTaps = 0;
    await tester.pumpWidget(
      shell(onBell: () => bellTaps++, onSettings: () => gearTaps++),
    );

    await tester.tap(bell);
    expect((bellTaps, gearTaps), (1, 0));
    await tester.tap(find.byTooltip('Settings'));
    expect((bellTaps, gearTaps), (1, 1));
  });

  testWidgets('with no role shell around it there is no gear', (tester) async {
    await tester.pumpWidget(shell());
    expect(gear, findsNothing);
  });
}
