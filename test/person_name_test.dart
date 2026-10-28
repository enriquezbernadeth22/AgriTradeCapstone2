import 'package:agritrade/services/person_name.dart';
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
}
