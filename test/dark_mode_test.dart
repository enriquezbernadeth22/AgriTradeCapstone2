import 'dart:math' as math;

import 'package:agritrade/theme/app_colors.dart';
import 'package:agritrade/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'appearance uses the saved choice, independent of system brightness',
    () {
      expect(ThemeController.resolvesDark(AppearanceMode.light), isFalse);
      expect(ThemeController.resolvesDark(AppearanceMode.dark), isTrue);
    },
  );

  test('light mode keeps every colour exactly as it was', () {
    AppColors.isDark = false;
    expect(AppColors.surface, Colors.white);
    expect(AppColors.text, Colors.black87);
    expect(AppColors.grey(600), Colors.grey[600]);
    expect(AppColors.cardBorder, isNull);
    expect(AppColors.outlineSide, BorderSide.none);
    expect(AppColors.tone(Colors.red, 700), Colors.red.shade700);
  });

  test('the soft section tint is a faint green, almost off-white', () {
    AppColors.isDark = false;
    final hsl = HSLColor.fromColor(AppColors.softTint);
    expect(hsl.lightness, greaterThan(0.96));
    expect(hsl.hue, inInclusiveRange(80, 140));
    expect(
      AppColors.softTint.computeLuminance(),
      greaterThan(AppColors.tint.computeLuminance()),
    );
    expect(
      AppColors.softTintBorder.computeLuminance(),
      greaterThan(AppColors.accent.computeLuminance()),
    );
  });

  test(
    'dark mode: forest-green page, cards one step lighter, quiet borders',
    () {
      AppColors.isDark = true;
      addTearDown(() => AppColors.isDark = false);
      expect(AppColors.page, const Color(0xFF101C17));
      expect(AppColors.surface, const Color(0xFF1B2B24));
      expect(AppColors.field, const Color(0xFF24382E));
      expect(AppColors.outline, const Color(0xFF34483D));
      expect(AppColors.cardBorder, isNotNull);
      expect(
        AppColors.surface.computeLuminance(),
        greaterThan(AppColors.page.computeLuminance()),
      );
      // Not pure black.
      expect(AppColors.page, isNot(Colors.black));
    },
  );

  test('dark mode text: soft off-white, readable muted grey', () {
    AppColors.isDark = true;
    addTearDown(() => AppColors.isDark = false);
    expect(AppColors.text, const Color(0xFFF4F6F2));
    expect(AppColors.textSecondary, const Color(0xFFB6C2B8));
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    // Secondary and muted text stay readable on a card (WCAG AA, 4.5:1).
    for (final text in [AppColors.textSecondary, AppColors.textMuted]) {
      expect(contrast(text, AppColors.surface), greaterThanOrEqualTo(4.5));
    }
    // White on a green button reads too.
    expect(
      contrast(Colors.white, AppColors.brandFill),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('dark mode keeps the green for actions, and only a hint of it on '
      'highlights', () {
    AppColors.isDark = true;
    addTearDown(() => AppColors.isDark = false);
    final brand = HSLColor.fromColor(AppColors.brand);
    expect(brand.hue, inInclusiveRange(90, 150));
    for (final quiet in [AppColors.tint, AppColors.softTint]) {
      final hsl = HSLColor.fromColor(quiet);
      expect(hsl.saturation, lessThan(0.25));
      expect(hsl.lightness, lessThan(0.2));
    }
  });

  test('a pale background is charcoal in dark mode, never darker than a '
      'card', () {
    AppColors.isDark = true;
    addTearDown(() => AppColors.isDark = false);
    final pale = AppColors.adapt(const Color(0xFFE8F3E3));
    expect(
      pale.computeLuminance(),
      greaterThan(AppColors.surface.computeLuminance()),
    );
    expect(HSLColor.fromColor(pale).lightness, lessThan(0.2));
    // Dark text still turns light.
    expect(
      HSLColor.fromColor(AppColors.adapt(const Color(0xFF1B5E20))).lightness,
      greaterThan(0.6),
    );
  });
}
