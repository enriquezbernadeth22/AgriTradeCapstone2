/// A person's name as AgriTrade+ asks for it — First name and Last name, as
/// two fields — and as it stores it: both separately ('firstName',
/// 'lastName') and joined into the one full name every screen shows
/// ('name' / 'fullName').
library;

import 'package:flutter/services.dart';

/// Spaces trimmed and runs of them made single.
String tidyName(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Each word's first letter a capital: "juan dela cruz" → "Juan Dela Cruz",
/// "maria-clara" → "Maria-Clara". Only those letters change: the rest stay as
/// typed ("McArthur" stays so), and so does the length.
String capitalizeName(String value) {
  final out = StringBuffer();
  var startOfWord = true;
  for (final char in value.split('')) {
    out.write(startOfWord ? char.toUpperCase() : char);
    startOfWord = char == ' ' || char == '-';
  }
  return out.toString();
}

/// A name as it is saved: tidied ([tidyName]) and capitalized
/// ([capitalizeName]).
String formatPersonName(String value) => capitalizeName(tidyName(value));

/// Capitalizes each word of a name field as it is typed (system testing,
/// 2026-11-09). It waits while the keyboard is still composing a word, so
/// it never fights the keyboard's own suggestions; the keyboard already
/// starts each word with a capital (TextCapitalization.words), and this
/// covers one that does not, or a name pasted in.
class NameCapitalizationFormatter extends TextInputFormatter {
  const NameCapitalizationFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final text = capitalizeName(newValue.text);
    return text == newValue.text ? newValue : newValue.copyWith(text: text);
  }
}

/// For a First name / Last name / Full name field.
const List<TextInputFormatter> kNameInputFormatters = [
  NameCapitalizationFormatter(),
];

/// The full name shown everywhere: "Juan" + "Dela Cruz" → "Juan Dela Cruz".
String joinName(String firstName, String lastName) =>
    formatPersonName('${tidyName(firstName)} ${tidyName(lastName)}');

/// A full name split back into its two fields, to fill them in from a
/// name already known (a Google account's): the last word is the last
/// name, the rest the first name.
({String first, String last}) splitName(String fullName) {
  final words = tidyName(fullName).split(' ')..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return (first: '', last: '');
  if (words.length == 1) return (first: words.single, last: '');
  return (
    first: words.sublist(0, words.length - 1).join(' '),
    last: words.last,
  );
}

/// The error under a First name or Last name field, or null. [label] is
/// the field ("First name", "Last name"). An empty field is only an error
/// once the form has been submitted ([submitted]).
String? nameFieldError(
  String value, {
  required String label,
  bool submitted = false,
}) {
  final name = tidyName(value);
  if (name.isEmpty) {
    return submitted ? 'Enter the ${label.toLowerCase()}.' : null;
  }
  if (RegExp(r'[0-9]').hasMatch(name)) return '$label cannot contain numbers.';
  if (name.length < 2 || name.length > 40) {
    return '$label must be 2–40 characters.';
  }
  return null;
}

/// Whether [value] is a complete First name or Last name.
bool isValidNamePart(String value) =>
    tidyName(value).isNotEmpty &&
    nameFieldError(value, label: 'Name', submitted: true) == null;
