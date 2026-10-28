import 'package:agritrade/services/feedback_service.dart';
import 'package:agritrade/widgets/feedback_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('when the app asks for feedback', () {
    test('first after the third product posted or order placed', () {
      expect(
        feedbackPromptDue(actions: 2, nextAsk: null, sent: false),
        isFalse,
      );
      expect(feedbackPromptDue(actions: 3, nextAsk: null, sent: false), isTrue);
    });

    test('after "Not now", only once ten more have gone by', () {
      expect(feedbackPromptDue(actions: 4, nextAsk: 13, sent: false), isFalse);
      expect(feedbackPromptDue(actions: 13, nextAsk: 13, sent: false), isTrue);
    });

    test('never again once feedback was sent', () {
      expect(
        feedbackPromptDue(actions: 50, nextAsk: null, sent: true),
        isFalse,
      );
    });
  });

  Future<List<Map<String, Object>>> open(
    WidgetTester tester, {
    bool prompted = false,
    Object? failWith,
  }) async {
    final sent = <Map<String, Object>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFeedbackSheet(
                context,
                prompted: prompted,
                trigger: prompted
                    ? FeedbackTrigger.orderPlaced
                    : FeedbackTrigger.menu,
                send:
                    ({
                      required int rating,
                      required String message,
                      required FeedbackTrigger trigger,
                    }) async {
                      if (failWith != null) throw failWith;
                      sent.add({
                        'rating': rating,
                        'message': message,
                        'trigger': trigger,
                      });
                    },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return sent;
  }

  testWidgets('Send waits for a rating, then sends it with the comment', (
    tester,
  ) async {
    final sent = await open(tester);
    expect(find.text('Send Feedback'), findsOneWidget);
    expect(find.text('Tap a star to rate'), findsOneWidget);

    // Nothing to send without a rating.
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);

    await tester.tap(find.byTooltip('4 stars'));
    await tester.pump();
    expect(find.text('Very good'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Madaling gamitin.');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(sent, [
      {
        'rating': 4,
        'message': 'Madaling gamitin.',
        'trigger': FeedbackTrigger.menu,
      },
    ]);
    expect(find.text('Thank you for your feedback!'), findsOneWidget);
    expect(find.text('Send Feedback'), findsNothing);
  });

  testWidgets('the prompt asks "Enjoying AgriTrade+?" and can wait', (
    tester,
  ) async {
    final sent = await open(tester, prompted: true);
    expect(find.text('Enjoying AgriTrade+?'), findsOneWidget);
    expect(find.textContaining('Give us feedback'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    expect(find.text('Enjoying AgriTrade+?'), findsNothing);
  });

  testWidgets('a failed send keeps the sheet open with the reason', (
    tester,
  ) async {
    await open(tester, failWith: Exception('offline'));
    await tester.tap(find.byTooltip('5 stars'));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be sent'), findsOneWidget);
    expect(find.text('Send Feedback'), findsOneWidget);
  });
}
