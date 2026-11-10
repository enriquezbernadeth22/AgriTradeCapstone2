import 'package:agritrade/services/person_name.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('First name and Last name join into the full name', () {
    expect(joinName('  Juan ', ' Dela   Cruz '), 'Juan Dela Cruz');
    expect(joinName('Maria Clara', 'Santos'), 'Maria Clara Santos');
  });

  test('a known full name splits into the two fields', () {
    expect(splitName('Juan Dela Cruz'), (first: 'Juan Dela', last: 'Cruz'));
    expect(splitName('Santos'), (first: 'Santos', last: ''));
    expect(splitName('  '), (first: '', last: ''));
  });

  test('each name field is checked', () {
    expect(nameFieldError('', label: 'First name'), isNull);
    expect(
      nameFieldError('', label: 'First name', submitted: true),
      'Enter the first name.',
    );
    expect(
      nameFieldError('Juan2', label: 'First name'),
      'First name cannot contain numbers.',
    );
    expect(
      nameFieldError('J', label: 'Last name'),
      'Last name must be 2–40 characters.',
    );
    expect(isValidNamePart('Dela Cruz'), isTrue);
    expect(isValidNamePart(''), isFalse);
  });

  // System testing, 2026-11-09: names start each word with a capital.
  test('each word of a name gets a capital first letter', () {
    expect(capitalizeName('juan dela cruz'), 'Juan Dela Cruz');
    expect(capitalizeName('maria-clara'), 'Maria-Clara');
    // Only first letters change; the rest stay as typed.
    expect(capitalizeName('mcArthur'), 'McArthur');
    expect(formatPersonName('  ana   reyes '), 'Ana Reyes');
    expect(joinName('juan', 'dela cruz'), 'Juan Dela Cruz');
  });

  test('typing a name capitalizes it, but not mid-word while composing', () {
    const formatter = NameCapitalizationFormatter();
    TextEditingValue typed(String text, {TextRange? composing}) =>
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: composing ?? TextRange.empty,
        );
    final done = formatter.formatEditUpdate(
      TextEditingValue.empty,
      typed('juan d'),
    );
    expect(done.text, 'Juan D');
    expect(done.selection.baseOffset, 6);
    final composing = formatter.formatEditUpdate(
      TextEditingValue.empty,
      typed('juan', composing: const TextRange(start: 0, end: 4)),
    );
    expect(composing.text, 'juan');
  });
}
