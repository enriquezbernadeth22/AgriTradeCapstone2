import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

/// Dark Mode: follows the phone until the person switches it themselves.
enum AppearanceMode { light, dark, system }

/// Keeps the Dark Mode choice (on this phone) and applies it: sets
/// [AppColors] and redraws every screen, so the whole app changes at once
/// without leaving the screen the person is on. Until the person flips the
/// switch, the app is dark exactly when the phone is ([AppearanceMode.system]).
///
/// The Admin Portal (the website) is always light.
class ThemeController extends ValueNotifier<AppearanceMode>
    with WidgetsBindingObserver {
  ThemeController._() : super(AppearanceMode.system);
  static final ThemeController instance = ThemeController._();

  static const _key = 'appearance_mode';

  /// Called once from main(), before the first frame: the saved choice is
  /// in place before anything is drawn, so the app never flashes light.
  Future<void> load() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      value = AppearanceMode.values.firstWhere(
        (mode) => mode.name == saved,
        orElse: () => AppearanceMode.system,
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

  /// The Dark Mode switch. Switched to match the phone, the app goes back
  /// to following it; switched against it, the choice sticks.
  Future<void> setDark(bool dark) {
    final phoneDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    return choose(
      dark == phoneDark
          ? AppearanceMode.system
          : (dark ? AppearanceMode.dark : AppearanceMode.light),
    );
  }

  /// What MaterialApp uses: always the one the colours were set for.
  ThemeMode get themeMode =>
      AppColors.isDark ? ThemeMode.dark : ThemeMode.light;

  /// Whether [mode] comes out dark here and now.
  static bool resolvesDark(AppearanceMode mode, Brightness phone) {
    if (kIsWeb) return false;
    return switch (mode) {
      AppearanceMode.light => false,
      AppearanceMode.dark => true,
      AppearanceMode.system => phone == Brightness.dark,
    };
  }

  // "Same as phone": follows the phone when it switches.
  @override
  void didChangePlatformBrightness() {
    if (value == AppearanceMode.system) _apply();
  }

  void _apply({bool redraw = true}) {
    final dark = resolvesDark(
      value,
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    if (dark == AppColors.isDark) return;
    AppColors.isDark = dark;
    notifyListeners();
    if (redraw) _redrawAll();
  }

  // Every screen reads AppColors as it builds, so every one is built again
  // — including those already open underneath.
  static void _redrawAll() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void mark(Element element) {
      element.markNeedsBuild();
      element.visitChildren(mark);
    }

    root.visitChildren(mark);
  }
}
