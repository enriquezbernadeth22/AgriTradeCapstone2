// The farmer's location question is short enough to read at a glance: one
// sentence on why, two points on who sees what, and no stretched-out
// (justified) lines.
import 'package:agritrade/services/location_permission_prompt.dart';
import 'package:agritrade/widgets/permission_rationale_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPermissionRationale(
                context,
                icon: Icons.location_on_outlined,
                title: 'Set Your Farm Location',
                message: kFarmerLocationMessage,
                bullets: kFarmerLocationPoints,
                denyLabel: 'Not Now',
                allowLabel: 'Allow Location',
              ),
              child: const Text('Ask'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
  }

  testWidgets('it says why in one sentence and who sees what in two points', (
    tester,
  ) async {
    await open(tester);
    expect(find.text(kFarmerLocationMessage), findsOneWidget);
    expect(kFarmerLocationPoints, hasLength(2));
    expect(
      find.text('Buyers see only your barangay, town and province.'),
      findsOneWidget,
    );
    expect(
      find.text('Your exact location stays private unless an order needs it.'),
      findsOneWidget,
    );
  });

  testWidgets('no line is justified', (tester) async {
    await open(tester);
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.textAlign, isNot(TextAlign.justify), reason: text.data);
    }
  });

  testWidgets('it fits a small phone with both buttons', (tester) async {
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Allow Location'), findsOneWidget);
    expect(find.text('Not Now'), findsOneWidget);
  });
}
