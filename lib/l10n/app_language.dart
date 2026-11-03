import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_controller.dart';
import 'tagalog_strings.dart';

/// The languages of the mobile app. The Admin Portal is in English.
enum AppLanguage {
  english('en', 'English'),
  tagalog('tl', 'Tagalog');

  final String code;
  final String label;
  const AppLanguage(this.code, this.label);
}

/// Keeps the language choice (on this phone) and applies it: the whole app
/// changes at once, without leaving the screen the person is on, the same
/// way Dark Mode does.
class LanguageController extends ValueNotifier<AppLanguage> {
  LanguageController._() : super(AppLanguage.english);
  static final LanguageController instance = LanguageController._();

  static const _key = 'app_language';

  /// What MaterialApp uses.
  Locale get locale => Locale(value.code);

  /// Called once from main(), before the first frame. The app is English
  /// only (the user's decision, 2026-11-04): there is no language choice
  /// in Settings, and a phone that had chosen Tagalog before opens in
  /// English. The Tagalog texts (tagalog_strings.dart) and [choose] are
  /// kept, for a language choice later.
  Future<void> load() async {
    value = AppLanguage.english;
  }

  /// Chooses [language], keeps it and redraws the app in it.
  Future<void> choose(AppLanguage language) async {
    if (language == value) return;
    value = language;
    ThemeController.redrawAll();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, language.code);
    } catch (_) {}
  }
}

/// [english] in the app's language. The English text is the key, so a text
/// with no translation yet simply stays in English. {0}, {1}… in it stand for
/// [values], whichever order the translation puts them in.
String tl(String english, [List<Object?> values = const []]) {
  final text = LanguageController.instance.value == AppLanguage.tagalog
      ? kTagalogStrings[english] ?? english
      : english;
  if (values.isEmpty) return text;
  return text.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
    final index = int.parse(match[1]!);
    return index < values.length ? '${values[index]}' : match[0]!;
  });
}
