// An Admin-added farmer is asked to replace the office's default password,
// and can skip for now.
import 'package:agritrade/services/push_notification_service.dart';
import 'package:agritrade/widgets/password_change_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<bool?> answer(WidgetTester tester, String button) async {
    bool? changeNow;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              changeNow = await showDialog<bool>(
                context: context,
                builder: (_) => const PasswordChangePromptDialog(),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
    return changeNow;
  }

  testWidgets('"Change Password" goes on to change it', (tester) async {
    expect(await answer(tester, 'Change Password'), isTrue);
  });

  testWidgets('"Skip for now" lets the farmer in', (tester) async {
    expect(await answer(tester, 'Skip for now'), isFalse);
  });

  test('the reminder repeats every 10 minutes', () {
    expect(
      PushNotificationService.passwordReminderInterval,
      const Duration(minutes: 10),
    );
  });
}
