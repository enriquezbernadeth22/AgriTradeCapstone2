import 'package:agritrade/theme/app_colors.dart';
import 'package:agritrade/theme/theme_controller.dart';
import 'package:agritrade/widgets/profile_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('until switched, the app is dark exactly when the phone is', () {
    expect(
      ThemeController.resolvesDark(AppearanceMode.system, Brightness.dark),
      isTrue,
    );
    expect(
      ThemeController.resolvesDark(AppearanceMode.system, Brightness.light),
      isFalse,
    );
    // Switched against the phone, the choice sticks.
    expect(
      ThemeController.resolvesDark(AppearanceMode.dark, Brightness.light),
      isTrue,
    );
    expect(
      ThemeController.resolvesDark(AppearanceMode.light, Brightness.dark),
      isFalse,
    );
  });

  test('light mode keeps every colour exactly as it was', () {
    AppColors.isDark = false;
    expect(AppColors.surface, Colors.white);
    expect(AppColors.text, Colors.black87);
    expect(AppColors.grey(600), Colors.grey[600]);
    expect(AppColors.cardBorder, isNull);
    expect(AppColors.outlineSide, BorderSide.none);
    expect(AppColors.tone(Colors.red, 700), Colors.red.shade700);
  });

  test('dark mode is black and dark green, with a white outline', () {
    AppColors.isDark = true;
    addTearDown(() => AppColors.isDark = false);
    expect(AppColors.page.computeLuminance(), lessThan(0.01));
    final surface = AppColors.surface;
    expect(surface.g, greaterThan(surface.r));
    expect(AppColors.cardBorder, isNotNull);
    expect(AppColors.outline.a, greaterThan(0));
  });

  testWidgets('the Dark Mode row is a switch; tapping the row flips it', (
    tester,
  ) async {
    bool? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileSwitchTile(
            icon: Icons.dark_mode_outlined,
            label: 'Dark Mode',
            value: false,
            onChanged: (v) => changed = v,
          ),
        ),
      ),
    );
    expect(find.byType(Switch), findsOneWidget);
    await tester.tap(find.text('Dark Mode'));
    expect(changed, isTrue);
  });

  testWidgets('Log Out on the Profile is a button', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileLinkTile(
            icon: Icons.logout,
            label: 'Log Out',
            destructive: true,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(InkWell), findsOneWidget);
    await tester.tap(find.text('Log Out'));
    expect(tapped, isTrue);
  });
}
