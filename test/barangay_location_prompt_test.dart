// Tapping the farmer's barangay field the first time asks for location
// first, on its own: the barangay list opens only once location is allowed,
// never behind the question. After Not Now, the next tap opens the list,
// since a barangay can always be picked by hand.
import 'dart:async';

import 'package:agritrade/widgets/barangay_location_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  late Completer<bool> answer;
  late int asked;

  Future<void> open(WidgetTester tester) async {
    answer = Completer<bool>();
    asked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarangayLocationField(
            value: null,
            onChanged: (_) {},
            askLocation: (_) {
              asked++;
              return answer.future;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Select your barangay'));
    await tester.pumpAndSettle();
  }

  testWidgets('the barangay list waits until location is allowed', (
    tester,
  ) async {
    await open(tester);
    expect(asked, 1);
    expect(find.text('Select Barangay'), findsNothing);

    answer.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Select Barangay'), findsOneWidget);
  });

  testWidgets('after Not Now, the list stays closed until the next tap, which '
      'opens it without asking again', (tester) async {
    await open(tester);
    answer.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Select Barangay'), findsNothing);

    await tester.tap(find.text('Select your barangay'));
    await tester.pumpAndSettle();
    expect(find.text('Select Barangay'), findsOneWidget);
    expect(asked, 1);
  });
}
