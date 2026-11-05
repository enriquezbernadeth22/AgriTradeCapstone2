// The Admin Portal's pop-up notices: when something happens on the
// marketplace while the portal is open, a card pops up at the top right
// for a few seconds — only for what is new, once each, and never for what
// the Admin did themselves.
import 'package:agritrade/screen/admin_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

final opened = DateTime(2026, 11, 5, 9);

AdminNotificationItem item(
  String title,
  int minutesAfterOpen, {
  bool popsUp = true,
  AdminNotificationTarget? target,
}) => AdminNotificationItem(
  icon: Icons.shopping_bag_outlined,
  title: title,
  detail: 'Ana ordered Rice from Ben',
  at: opened.add(Duration(minutes: minutesAfterOpen)),
  target: target,
  popsUp: popsUp,
);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  test('only what happened after the portal opened pops up, once', () {
    final items = [
      item('Before', -5),
      item('New order', 2),
      item('Order completed', 3),
    ];
    final shown = <String>{};
    final first = adminAlertsToPopUp(items, since: opened, shown: shown);
    expect(first.map((i) => i.title), ['New order', 'Order completed']);

    shown.addAll(first.map((i) => i.key));
    expect(adminAlertsToPopUp(items, since: opened, shown: shown), isEmpty);
  });

  test('many at once: only the newest three, oldest first', () {
    final items = [for (var m = 1; m <= 5; m++) item('Update $m', m)];
    final shown = adminAlertsToPopUp(items, since: opened, shown: {});
    expect(shown.map((i) => i.title), ['Update 3', 'Update 4', 'Update 5']);
  });

  test('the Admin\'s own announcements and sign-ins do not pop up', () {
    final now = opened.add(const Duration(minutes: 10));
    final at = Timestamp.fromDate(opened.add(const Duration(minutes: 1)));
    final items = buildAdminNotifications(
      orders: [
        (
          id: 'o1',
          data: {
            'buyerName': 'Ana',
            'sellerName': 'Ben',
            'productName': 'Rice',
            'createdAt': at,
          },
        ),
      ],
      users: const [],
      reports: const [],
      announcements: [
        (id: 'a1', data: {'title': 'Holiday', 'createdAt': at}),
      ],
      signIns: [
        (id: 's1', data: {'startedAt': at, 'deviceName': 'Chrome'}),
      ],
      now: now,
    );
    expect(items, hasLength(3));
    final popping = adminAlertsToPopUp(items, since: opened, shown: {});
    expect(popping.map((i) => i.title), ['New order']);
  });

  group('the cards', () {
    late AdminAlertToasts toasts;
    late BuildContext hostContext;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      toasts = AdminAlertToasts();
      addTearDown(toasts.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );
    }

    testWidgets('one pops up at the top right and goes by itself', (
      tester,
    ) async {
      await pump(tester);
      toasts.show(hostContext, item('New order', 1));
      await tester.pumpAndSettle();
      expect(find.text('New order'), findsOneWidget);
      expect(find.text('Ana ordered Rice from Ben'), findsOneWidget);
      final card = tester.getRect(find.text('New order'));
      expect(card.left, greaterThan(800)); // on the right
      expect(card.top, lessThan(200)); // near the top

      await tester.pump(AdminAlertToasts.shownFor);
      await tester.pumpAndSettle();
      expect(find.text('New order'), findsNothing);
    });

    testWidgets('the pointer resting on it keeps it up', (tester) async {
      await pump(tester);
      toasts.show(hostContext, item('New order', 1));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('New order')));
      await tester.pump(AdminAlertToasts.shownFor * 2);
      expect(find.text('New order'), findsOneWidget);

      await mouse.moveTo(Offset.zero);
      await tester.pump(AdminAlertToasts.shownFor);
      await tester.pumpAndSettle();
      expect(find.text('New order'), findsNothing);
    });

    testWidgets('× closes it, newest is on top, never more than three', (
      tester,
    ) async {
      await pump(tester);
      for (var i = 1; i <= 4; i++) {
        toasts.show(hostContext, item('Update $i', i));
      }
      await tester.pumpAndSettle();
      expect(toasts.showing.map((i) => i.title), [
        'Update 4',
        'Update 3',
        'Update 2',
      ]);
      expect(
        tester.getTopLeft(find.text('Update 4')).dy,
        lessThan(tester.getTopLeft(find.text('Update 3')).dy),
      );

      await tester.tap(find.byTooltip('Close').first);
      await tester.pumpAndSettle();
      expect(find.text('Update 4'), findsNothing);
      expect(find.text('Update 3'), findsOneWidget);
      await tester.pump(AdminAlertToasts.shownFor);
      await tester.pumpAndSettle();
    });

    testWidgets('clicking one opens its page', (tester) async {
      await pump(tester);
      addTearDown(() => adminOpenPageRequest.value = null);
      toasts.show(
        hostContext,
        item('New report', 1, target: AdminNotificationTarget.moderation),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New report'));
      await tester.pumpAndSettle();
      expect(adminOpenPageRequest.value, AdminNotificationTarget.moderation);
      expect(find.text('New report'), findsNothing);
    });
  });
}
