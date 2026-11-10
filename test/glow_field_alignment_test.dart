// A password typed into a field with an eye button sits in the middle of
// the field, like the email above it (the Admin login's password sat high,
// 2026-11-09).
import 'package:agritrade/widgets/glow_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the text is centred in a field with an eye button', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Bernadeth@123');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              // The Admin login's field height.
              height: 46,
              child: GlowField(
                key: const Key('password'),
                controller: controller,
                hint: 'Password',
                icon: Icons.lock_outline,
                compact: true,
                suffix: IconButton(
                  icon: const Icon(Icons.visibility),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final field = tester.getRect(find.byKey(const Key('password')));
    final text = tester.getRect(find.byType(EditableText));
    expect((text.center.dy - field.center.dy).abs(), lessThan(1.5));
  });
}
