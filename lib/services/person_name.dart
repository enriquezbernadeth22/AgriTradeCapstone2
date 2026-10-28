/// A person's name as AgriTrade+ asks for it — First name and Last name, as
/// two fields — and as it stores it: both separately ('firstName',
/// 'lastName') and joined into the one full name every screen shows
/// ('name' / 'fullName').
library;

/// Spaces trimmed and runs of them made single.
String tidyName(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');

/// The full name shown everywhere: "Juan" + "Dela Cruz" → "Juan Dela Cruz".
String joinName(String firstName, String lastName) =>
    tidyName('${tidyName(firstName)} ${tidyName(lastName)}');

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
