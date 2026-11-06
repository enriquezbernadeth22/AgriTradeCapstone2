// A dropdown's open list is as wide as its longest option, not the whole
// field: short options open as a small panel.
import 'package:agritrade/data/account_types.dart';
import 'package:agritrade/widgets/fitted_menu_width.dart';
import 'package:agritrade/widgets/registration_role_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('short options open a list narrower than the field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: RegistrationRoleDetails(
              isFarmer: true,
              value: null,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final field = tester.getSize(find.byType(DropdownButton<String>));
    final menuWidth = tester
        .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .menuWidth!;
    expect(menuWidth, lessThan(field.width));

    // Still room for every option, on one line.
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    for (final option in kFarmerTypes) {
      final text = find.text(option).last;
      expect(tester.getSize(text).width, lessThanOrEqualTo(menuWidth - 32));
      expect(tester.getSize(text).height, lessThan(30), reason: option);
    }
  });

  testWidgets('a long option gets the room it needs, up to the screen', (
    tester,
  ) async {
    late double short;
    late double long;
    late double tooLong;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            const style = TextStyle(fontSize: 14);
            short = fittedMenuWidth(context, ['Yes', 'No'], style: style);
            long = fittedMenuWidth(context, [
              'Yes',
              'A much longer option',
            ], style: style);
            tooLong = fittedMenuWidth(context, ['x' * 400], style: style);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(short, 120); // never narrower than the minimum
    expect(long, greaterThan(short));
    expect(tooLong, 800 - 32); // the test screen is 800 wide
  });
}
