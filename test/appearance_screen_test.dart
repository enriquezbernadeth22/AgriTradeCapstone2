// Appearance, from the Buyer Profile: the Dark Mode switch, the same
// setting as the farmer's Settings sheet; no language (English only).
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/appearance_screen.dart';
import 'package:agritrade/theme/app_colors.dart';
import 'package:agritrade/theme/app_theme.dart';
import 'package:agritrade/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    ThemeController.instance.value = AppearanceMode.light;
    AppColors.isDark = false;
  });

  testWidgets('Dark Mode turns on and off from Appearance', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AppearanceScreen(),
      ),
    );
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Language'), findsNothing);
    expect(AppColors.isDark, isFalse);

    await tester.tap(find.byKey(const Key('darkModeSwitch')));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('darkModeSwitch')));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isFalse);
  });
}
