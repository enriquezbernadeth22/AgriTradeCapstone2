// After a wrong password, "You have N attempts left." shows under the
// Password field on a single line, even on a narrow phone.
import 'package:agritrade/widgets/login_form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('the attempts warning fits on one line on a narrow phone', (
    tester,
  ) async {
    const message = 'Incorrect email or password. You have 2 attempts left.';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              // A small phone's field, between the page margins.
              width: 280,
              child: LoginAttemptsWarning(message: message),
            ),
          ),
        ),
      ),
    );
    final text = find.text(message);
    final box = tester.getRect(find.byType(LoginAttemptsWarning));
    final line = tester.getRect(text);
    expect(line.right, lessThanOrEqualTo(box.right));
    // One line: no taller than the 11-point text and its icon.
    expect(box.height, lessThan(8 + 20));
    expect(tester.widget<Text>(text).maxLines, 1);
  });
}
