// A chat message slides sideways to reply; held, everything else blurs
// and a menu shows (Reply, Copy, Pin, Unsend for yours, Report for
// theirs) with the reactions above. And tapping outside a text field puts
// the keyboard away.
import 'package:agritrade/services/auth_service.dart';
import 'package:agritrade/widgets/message_actions.dart';
import 'package:agritrade/widgets/tap_outside_to_unfocus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<int> pumpSwipe(WidgetTester tester, {required bool mine}) async {
    var replies = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: SwipeToReply(
              mine: mine,
              onReply: () => replies++,
              child: Container(
                key: const Key('bubble'),
                width: 200,
                height: 48,
                color: Colors.green,
              ),
            ),
          ),
        ),
      ),
    );
    return replies;
  }

  testWidgets('a received message slides right to reply, and follows the '
      'finger', (tester) async {
    var replies = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: SwipeToReply(
              mine: false,
              onReply: () => replies++,
              child: Container(
                key: const Key('bubble'),
                width: 200,
                height: 48,
                color: Colors.green,
              ),
            ),
          ),
        ),
      ),
    );
    final start = tester.getTopLeft(find.byKey(const Key('bubble'))).dx;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('bubble'))),
    );
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    // It moves with the finger, and the reply arrow shows behind it.
    expect(
      tester.getTopLeft(find.byKey(const Key('bubble'))).dx,
      greaterThan(start + 40),
    );
    expect(find.byKey(const Key('swipeReplyIcon')), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(replies, 1);
    // And it slides back.
    expect(tester.getTopLeft(find.byKey(const Key('bubble'))).dx, start);
  });

  testWidgets('your own message slides left to reply; a short slide does '
      'nothing', (tester) async {
    await pumpSwipe(tester, mine: true);
    var replies = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SwipeToReply(
              mine: true,
              onReply: () => replies++,
              child: Container(
                key: const Key('bubble'),
                width: 200,
                height: 48,
                color: Colors.green,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byKey(const Key('bubble')), const Offset(-20, 0));
    await tester.pumpAndSettle();
    expect(replies, 0);
    await tester.drag(find.byKey(const Key('bubble')), const Offset(-90, 0));
    await tester.pumpAndSettle();
    expect(replies, 1);
  });

  Future<MessageActionChoice?> hold(
    WidgetTester tester, {
    required bool mine,
    bool canCopy = true,
    bool pinned = false,
    required Future<void> Function() choose,
  }) async {
    MessageActionChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showMessageActions(
                    context,
                    rect: const Rect.fromLTWH(40, 300, 200, 48),
                    message: const SizedBox(width: 200, height: 48),
                    mine: mine,
                    canCopy: canCopy,
                    pinned: pinned,
                  );
                },
                child: const Text('hold'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('hold'));
    await tester.pumpAndSettle();
    await choose();
    await tester.pumpAndSettle();
    return result;
  }

  Finder action(MessageAction a) => find.byKey(Key('messageAction-${a.name}'));

  testWidgets('your message: Reply, Copy, Pin and Unsend — no Report', (
    tester,
  ) async {
    final choice = await hold(
      tester,
      mine: true,
      choose: () async {
        expect(find.byType(BackdropFilter), findsOneWidget); // blurred
        expect(action(MessageAction.reply), findsOneWidget);
        expect(action(MessageAction.copy), findsOneWidget);
        expect(action(MessageAction.pin), findsOneWidget);
        expect(action(MessageAction.unsend), findsOneWidget);
        expect(action(MessageAction.report), findsNothing);
        await tester.tap(action(MessageAction.unsend));
      },
    );
    expect(choice?.action, MessageAction.unsend);
  });

  testWidgets('their message: Report, not Unsend; pinned shows Unpin', (
    tester,
  ) async {
    final choice = await hold(
      tester,
      mine: false,
      pinned: true,
      choose: () async {
        expect(action(MessageAction.report), findsOneWidget);
        expect(action(MessageAction.unsend), findsNothing);
        expect(action(MessageAction.unpin), findsOneWidget);
        expect(action(MessageAction.pin), findsNothing);
        await tester.tap(action(MessageAction.report));
      },
    );
    expect(choice?.action, MessageAction.report);
  });

  testWidgets('a reaction from the bar above, and no Copy for a photo', (
    tester,
  ) async {
    final choice = await hold(
      tester,
      mine: false,
      canCopy: false,
      choose: () async {
        expect(action(MessageAction.copy), findsNothing);
        await tester.tap(find.byKey(const Key('reaction-heart')));
      },
    );
    expect(choice?.reaction, 'heart');
    expect(choice?.action, isNull);
  });

  testWidgets('tapping outside closes it with nothing chosen', (tester) async {
    final choice = await hold(
      tester,
      mine: true,
      choose: () async {
        await tester.tapAt(const Offset(10, 10));
      },
    );
    expect(choice, isNull);
  });

  testWidgets('tapping outside a text field puts the keyboard away', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TapOutsideToUnfocus(
          child: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: focus),
                const SizedBox(height: 400, width: double.infinity),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.tapAt(const Offset(200, 500));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });

  test('logging in: plain messages for an unknown email and a Google-only '
      'account', () {
    expect(AuthService.notRegisteredMessage, contains('not registered'));
    expect(AuthService.googleOnlyMessage, contains('Continue with Google'));
  });
}
