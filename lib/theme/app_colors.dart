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

  /// The page behind everything (Scaffold): the warm cream of Explore, for
  /// every buyer and farmer screen (the user's design, 2026-11-08); cards,
  /// fields, sheets and dialogs stay white ([surface]).
  // Dark: the forest-green Dark Mode (the user, 2026-11-08): a deep
  // charcoal green rather than black (#101C17), cards one step lighter
  // (#1B2B24), fields and secondary surfaces (#24382E) and a quiet border
  // (#34483D), so the layers read without shadows.
  static Color get page =>
      _pick(const Color(0xFFFEF7EE), const Color(0xFF101C17));

  /// The white of every sign-in screen (the user, 2026-11-08): Log In and
  /// the first screen, Choose Role and registration, the Google profile
  /// form, Forgot Password, email verification and waiting for approval;
  /// and of the splash (the loading and no-internet screens), white like
  /// the phone's launch screen. Once signed in, every screen is on [page].
  static Color get authPage => _pick(Colors.white, const Color(0xFF101C17));

  /// Cards, sheets, dialogs, headers, the nav bar, menus.
  static Color get surface => _pick(Colors.white, const Color(0xFF1B2B24));

  /// The off-white page under cards on inner screens (AppTheme.surface).
  static Color get surfaceAlt =>
      _pick(AppTheme.surface, const Color(0xFF101C17));

  /// A text field's fill (AppTheme.fieldFill).
  static Color get field => _pick(AppTheme.fieldFill, const Color(0xFF24382E));

  /// Dark mode's outline: a quiet grey line around cards, fields and
  /// panels, so they stand apart from the page. None in light.
  static Color get outline =>
      _pick(Colors.transparent, const Color(0xFF34483D));

  /// [outline] as a card's border; null (no border) in light mode.
  static Border? get cardBorder => isDark ? Border.all(color: outline) : null;

  /// [outline] as a side for shapes (menus, sheets); none in light mode.
  static BorderSide get outlineSide =>
      isDark ? BorderSide(color: outline) : BorderSide.none;

  // ---- Text ----

  /// Main text (Colors.black87).
  static Color get text => _pick(Colors.black87, const Color(0xFFF4F6F2));

  /// Strong text (Colors.black).
  static Color get textStrong => _pick(Colors.black, Colors.white);

  /// Secondary text (Colors.black54).
  static Color get textSecondary =>
      _pick(Colors.black54, const Color(0xFFB6C2B8));

  /// Muted text (Colors.black45 / black38).
  static Color get textMuted => _pick(Colors.black45, const Color(0xFF86978C));

  /// Faint lines, handles and borders (Colors.black12).
  static Color get hairline => _pick(Colors.black12, const Color(0xFF34483D));

  /// Colors.grey's shades, matched for dark: a light grey background stays
  /// a quiet background, grey text stays readable, a border stays a border.
  static Color grey([int shade = 500]) {
    if (!isDark) return Colors.grey[shade] ?? Colors.grey;
    return switch (shade) {
      // Charcoal greens in step with page / surface / outline above;
      // text shades from 500 up stay readable on a card.
      50 => const Color(0xFF15231D),
      100 => const Color(0xFF1F3029),
      200 => const Color(0xFF24382E),
      300 => const Color(0xFF34483D),
      350 => const Color(0xFF3F5447),
      400 => const Color(0xFF5B6F63),
      500 => const Color(0xFF86978C),
      600 => const Color(0xFFB6C2B8),
      700 => const Color(0xFFCBD4CD),
      800 => const Color(0xFFE2E8E3),
      _ => const Color(0xFFF4F6F2),
    };
  }

  /// A page or card's own title (Market, Sales Performance…): the dark
  /// green in light, soft white in dark (the user, 2026-11-08).
  static Color get heading => _pick(AppTheme.dark, const Color(0xFFF4F6F2));

  /// The gold of selected things (the nav's pill, a selected segment), and
  /// in dark a figure to stand out (the month's sales).
  static const Color gold = Color(0xFFF5BB24);

  // ---- The brand greens ----

  /// The brand green as text and icons (links, prices, active tabs,
  /// selected items): dark green in light mode, a soft readable green in
  /// dark mode.
  // Dark: the soft green of the charts (#A7D88A).
  static Color get brand => _pick(AppTheme.dark, const Color(0xFFA7D88A));

  /// The dark green as a fill: buttons, selected chips, badges.
  // Dark: a dark forest green that still stands out from the cards, white
  // text on it clear.
  static Color get brandFill => _pick(AppTheme.dark, const Color(0xFF1F5C38));

  /// What sits on [brandFill].
  static Color get onBrand => Colors.white;

  /// The brand green (AppTheme.mid), for accents.
  static Color get mid => _pick(AppTheme.mid, const Color(0xFF6FBF7C));

  /// The pale green for highlight boxes, banners, selected rows
  /// (AppTheme.tint).
  // Dark: charcoal with only a hint of green, never a green slab.
  static Color get tint => _pick(AppTheme.tint, const Color(0xFF1F3029));

  /// The stronger pale green for chips and badges (AppTheme.accent).
  static Color get accent => _pick(AppTheme.accent, const Color(0xFF2B4135));

  /// The faintest green, almost off-white, for a section on a white page
  /// (Farm Location). Neutral in dark like [tint]; [adapt] would keep it green.
  static Color get softTint =>
      _pick(const Color(0xFFF5FAF1), const Color(0xFF1F3029));

  /// The edge of a [softTint] section.
  static Color get softTintBorder =>
      _pick(const Color(0xFFE5F0DD), const Color(0xFF34483D));

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
  /// lightness turned around, so dark text becomes light. A pale background
  /// becomes a charcoal one step above the cards (with only a hint of its
  /// hue), never a near-black hole in them. Unchanged in light mode.
  static Color adapt(Color light) {
    if (!isDark) return light;
    final hsl = HSLColor.fromColor(light);
    if (hsl.lightness >= 0.8) {
      return hsl
          .withSaturation(hsl.saturation * 0.3)
          .withLightness(0.15)
          .toColor();
    }
    final lightness = (1 - hsl.lightness).clamp(0.1, 0.9);
    return hsl.withLightness(lightness).toColor();
  }
}
