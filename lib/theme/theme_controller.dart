import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

/// The app's appearance is light by default and changes only when the person
/// chooses Dark Mode.
enum AppearanceMode { light, dark }

/// Keeps the Dark Mode choice (on this phone) and applies it: sets
/// [AppColors] and redraws every screen, so the whole app changes at once
/// without leaving the screen the person is on. The phone's appearance is
/// never read.
///
/// The Admin Portal (the website) has its own switch, kept per browser
/// (adminDarkMode in admin_dashboard_screen.dart), which sets [AppColors]
/// too: dialogs and queues shared with the app read their colours from it.
class ThemeController extends ValueNotifier<AppearanceMode> {
  ThemeController._() : super(AppearanceMode.light);
  static final ThemeController instance = ThemeController._();

  static const _key = 'appearance_mode';

  /// Called once from main(), before the first frame: the saved choice is
  /// in place before anything is drawn, so the app never flashes light.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      value = AppearanceMode.values.firstWhere(
        (mode) => mode.name == saved,
        // An older saved "system" choice now resolves to the light default.
        orElse: () => AppearanceMode.light,
      );
    } catch (_) {}
    _apply(redraw: false);
  }

  /// Chooses [mode], keeps it and redraws the app in it.
  Future<void> choose(AppearanceMode mode) async {
    value = mode;
    _apply();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }

  /// The Dark Mode switch. The explicit choice is saved on this phone.
  Future<void> setDark(bool dark) {
    return choose(dark ? AppearanceMode.dark : AppearanceMode.light);
  }

  /// What MaterialApp uses: always the one the colours were set for.
  ThemeMode get themeMode =>
      AppColors.isDark ? ThemeMode.dark : ThemeMode.light;

  /// Whether [mode] is the explicitly selected dark appearance.
  static bool resolvesDark(AppearanceMode mode) => mode == AppearanceMode.dark;

  void _apply({bool redraw = true}) {
    final dark = resolvesDark(value);
    if (dark == AppColors.isDark) return;
    AppColors.isDark = dark;
    notifyListeners();
    if (redraw) redrawAll();
  }

  // Every screen reads AppColors as it builds, so every one is built again
  // — including those already open underneath.
  static void redrawAll() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void mark(Element element) {
      element.markNeedsBuild();
      element.visitChildren(mark);
    }

    root.visitChildren(mark);
  }
}
