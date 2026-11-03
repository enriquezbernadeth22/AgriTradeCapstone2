// English stays the default; the app can switch to Tagalog, and a text with
// no translation falls back to English rather than showing nothing.
import 'package:agritrade/l10n/app_language.dart';
import 'package:agritrade/l10n/tagalog_strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LanguageController.instance.value = AppLanguage.english;
  });
  tearDown(() => LanguageController.instance.value = AppLanguage.english);

  test('English is the default and is left as written', () {
    expect(tl('Change your password'), 'Change your password');
    expect(tl('Order #{0}', ['A12']), 'Order #A12');
  });

  test('Tagalog shows the translation, with its values put in', () {
    LanguageController.instance.value = AppLanguage.tagalog;
    expect(tl('Change your password'), 'Palitan ang iyong password');
    expect(
      tl('Only {0} available right now. Lower your quantity.', ['3 kg']),
      '3 kg lang ang available ngayon. Bawasan ang dami.',
    );
  });

  test('a text with no translation stays in English', () {
    LanguageController.instance.value = AppLanguage.tagalog;
    expect(tl('Not in the list at all'), 'Not in the list at all');
  });

  test('the app is English only: a phone that chose Tagalog before opens in '
      'English', () async {
    SharedPreferences.setMockInitialValues({'app_language': 'tl'});
    LanguageController.instance.value = AppLanguage.tagalog;
    await LanguageController.instance.load();
    expect(LanguageController.instance.value, AppLanguage.english);
  });

  test('every translation keeps the values of its English text', () {
    final value = RegExp(r'\{\d+\}');
    // These drop an English plural ending, which Tagalog does not have.
    const pluralEnding = {'{0} star{1}'};
    for (final entry in kTagalogStrings.entries) {
      if (pluralEnding.contains(entry.key)) continue;
      if (entry.key.startsWith('Review your completed orders')) continue;
      for (final match in value.allMatches(entry.key)) {
        expect(entry.value, contains(match[0]!), reason: entry.key);
      }
    }
  });
}
