import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The mobile app's colours, light or dark (Settings → Appearance; see
/// ThemeController). Screens use these instead of fixed colours, so one
/// switch turns the whole app dark:
///
///   page / surface / surfaceAlt / field   backgrounds, darkest to lightest
///   text / grey(…)                        text, icons, lines and fills
///   brand / brandFill / onBrand           the dark green: as text and
///                                         icons, as a button's fill, and
///                                         what sits on that fill
///   tint / accent                         the pale greens
///
/// They are read when a screen builds; ThemeController rebuilds every
/// screen when the choice changes. The Admin Portal (the website) is
/// always light and has its own palette (AdminPalette).
class AppColors {
  AppColors._();

  /// Whether the dark colours are in use. Set by ThemeController only.
  static bool isDark = false;

  static Color _pick(Color light, Color dark) => isDark ? dark : light;

  // ---- Backgrounds ----

  /// The page behind everything (Scaffold).
  static Color get page => _pick(Colors.white, const Color(0xFF040604));

  /// Cards, sheets, dialogs, headers, the nav bar, menus.
  static Color get surface => _pick(Colors.white, const Color(0xFF0E1C11));

  /// The off-white page under cards on inner screens (AppTheme.surface).
  static Color get surfaceAlt =>
      _pick(AppTheme.surface, const Color(0xFF070C08));

  /// A text field's fill (AppTheme.fieldFill).
  static Color get field => _pick(AppTheme.fieldFill, const Color(0xFF13261A));

  /// Dark mode's outline: a faint white line around cards, fields and
  /// panels that would otherwise melt into the black page. None in light.
  static Color get outline =>
      _pick(Colors.transparent, Colors.white.withValues(alpha: 0.18));

  /// [outline] as a card's border; null (no border) in light mode.
  static Border? get cardBorder => isDark ? Border.all(color: outline) : null;

  /// [outline] as a side for shapes (menus, sheets); none in light mode.
  static BorderSide get outlineSide =>
      isDark ? BorderSide(color: outline) : BorderSide.none;

  // ---- Text ----

  /// Main text (Colors.black87).
  static Color get text => _pick(Colors.black87, const Color(0xFFE6E9E4));

  /// Strong text (Colors.black).
  static Color get textStrong => _pick(Colors.black, Colors.white);

  /// Secondary text (Colors.black54).
  static Color get textSecondary =>
      _pick(Colors.black54, const Color(0xFFADB3AA));

  /// Muted text (Colors.black45 / black38).
  static Color get textMuted => _pick(Colors.black45, const Color(0xFF8E948B));

  /// Faint lines, handles and borders (Colors.black12).
  static Color get hairline => _pick(Colors.black12, Colors.white12);

  /// Colors.grey's shades, matched for dark: a light grey background stays
  /// a quiet background, grey text stays readable, a border stays a border.
  static Color grey([int shade = 500]) {
    if (!isDark) return Colors.grey[shade] ?? Colors.grey;
    return switch (shade) {
      50 => const Color(0xFF0D1A10),
      100 => const Color(0xFF122216),
      200 => const Color(0xFF223527),
      300 => const Color(0xFF34493A),
      350 => const Color(0xFF4A5048),
      400 => const Color(0xFF5E645C),
      500 => const Color(0xFF80867E),
      600 => const Color(0xFF9EA49B),
      700 => const Color(0xFFB9BEB6),
      800 => const Color(0xFFD3D7D0),
      _ => const Color(0xFFE6E9E4),
    };
  }

  // ---- The brand greens ----

  /// The dark green as text, icons and outlines (AppTheme.dark). A light
  /// green in dark mode, where the dark one could not be seen.
  static Color get brand => _pick(AppTheme.dark, const Color(0xFF9CD69A));

  /// The dark green as a fill: buttons, selected chips, badges.
  static Color get brandFill => _pick(AppTheme.dark, const Color(0xFF1B5E20));

  /// What sits on [brandFill].
  static Color get onBrand => Colors.white;

  /// The brand green (AppTheme.mid), for accents.
  static Color get mid => _pick(AppTheme.mid, const Color(0xFF6BBF6E));

  /// The pale green for highlight boxes, banners, selected rows
  /// (AppTheme.tint).
  static Color get tint => _pick(AppTheme.tint, const Color(0xFF0F2914));

  /// The stronger pale green for chips and badges (AppTheme.accent).
  static Color get accent => _pick(AppTheme.accent, const Color(0xFF1A3D20));

  /// A shade of one of Flutter's colour swatches (Colors.red.shade700,
  /// Colors.orange.shade50, …), matched for dark: pale backgrounds become a
  /// dark tint of the colour, dark text and icons a light shade of it.
  static Color tone(MaterialColor color, int shade) {
    if (!isDark) return color[shade] ?? color;
    if (shade <= 100) {
      return Color.alphaBlend(color[800]!.withValues(alpha: 0.28), surface);
    }
    return switch (shade) {
      200 => color[700]!,
      300 => color[600]!,
      700 || 800 => color[300]!,
      900 => color[200]!,
      _ => color[shade] ?? color,
    };
  }

  /// Any other fixed colour, matched for dark: the same hue with its
  /// lightness turned around, so a pale background becomes a dark one and
  /// dark text becomes light. Unchanged in light mode.
  static Color adapt(Color light) {
    if (!isDark) return light;
    final hsl = HSLColor.fromColor(light);
    final lightness = (1 - hsl.lightness).clamp(0.1, 0.9);
    return hsl.withLightness(lightness).toColor();
  }
}
