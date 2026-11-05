// Stock comes off a listing when the farmer confirms the order, not when it
// is placed; and a confirmed order's buttons on Order Details are balanced,
// with Cancel Order a quieter text button under the two that move it on.
import 'package:agritrade/screen/order_details_screen.dart';
import 'package:agritrade/services/order_service.dart';
import 'package:agritrade/widgets/order_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  test('a pending order has taken no stock; a confirmed one has', () {
    expect(
      orderTookStock({'stockOnConfirm': true, 'status': 'pending'}),
      isFalse,
    );
    expect(
      orderTookStock({
        'stockOnConfirm': true,
        'status': 'confirmed',
        'stockDeductedAt': DateTime(2026, 11, 5),
      }),
      isTrue,
    );
  });

  test('an order placed before the rule took its stock when placed', () {
    expect(orderTookStock({'status': 'pending'}), isTrue);
  });

  Future<List<String>> pumpBar(
    WidgetTester tester,
    List<OrderCardAction> actions,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: OrderActionBar(
            actions: [
              for (final a in actions)
                OrderCardAction(
                  a.label,
                  () => tapped.add(a.label),
                  kind: a.kind,
                ),
            ],
          ),
        ),
      ),
    );
    return tapped;
  }

  testWidgets('a confirmed order: Report Delay and Ready for Pick-up side by '
      'side, the same size, Cancel Order centred under them', (tester) async {
    final tapped = await pumpBar(tester, [
      OrderCardAction('Cancel Order', () {}, kind: OrderActionKind.destructive),
      OrderCardAction('Report Delay', () {}),
      OrderCardAction(
        'Ready for Pick-up',
        () {},
        kind: OrderActionKind.primary,
      ),
    ]);
    expect(tester.takeException(), isNull);
    final delay = tester.getRect(
      find.ancestor(
        of: find.text('Report Delay'),
        matching: find.byType(OrderActionButton),
      ),
    );
    final ready = tester.getRect(
      find.ancestor(
        of: find.text('Ready for Pick-up'),
        matching: find.byType(OrderActionButton),
      ),
    );
    expect(delay.top, ready.top);
    expect(delay.width, closeTo(ready.width, 0.5));

    // Cancel Order: a text button under them, in the middle.
    final cancel = find.byKey(const Key('quietAction-Cancel Order'));
    expect(cancel, findsOneWidget);
    expect(tester.getTopLeft(cancel).dy, greaterThanOrEqualTo(delay.bottom));
    expect(
      tester.getCenter(cancel).dx,
      closeTo((delay.left + ready.right) / 2, 1),
    );
    await tester.tap(cancel);
    expect(tapped, ['Cancel Order']);
  });

  testWidgets('two buttons stay side by side, with no text button', (
    tester,
  ) async {
    await pumpBar(tester, [
      OrderCardAction('Reject', () {}, kind: OrderActionKind.destructive),
      OrderCardAction('Accept', () {}, kind: OrderActionKind.primary),
    ]);
    expect(
      tester.getTopLeft(find.text('Reject')).dy,
      closeTo(tester.getTopLeft(find.text('Accept')).dy, 1),
    );
    expect(find.byKey(const Key('quietAction-Reject')), findsNothing);
  });
}
