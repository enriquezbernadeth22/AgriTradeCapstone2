import 'package:agritrade/services/registration_guard.dart';
import 'package:agritrade/widgets/existing_account_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an email is compared trimmed and lowercased', () {
    expect(
      normalizeEmail('  Juan.DelaCruz@Gmail.com '),
      'juan.delacruz@gmail.com',
    );
  });

  test('the server\'s answer becomes what already exists', () {
    expect(existingAccountFromStatus('none'), ExistingAccount.none);
    expect(
      existingAccountFromStatus('farmer_pending'),
      ExistingAccount.farmerPending,
    );
    expect(
      existingAccountFromStatus('farmer_approved'),
      ExistingAccount.farmerApproved,
    );
    expect(
      existingAccountFromStatus('farmer_rejected'),
      ExistingAccount.farmerRejected,
    );
    expect(existingAccountFromStatus('registered'), ExistingAccount.registered);
    // Never blocks a registration on an answer it does not understand.
    expect(existingAccountFromStatus(null), ExistingAccount.none);
    expect(existingAccountFromStatus('something else'), ExistingAccount.none);
  });

  test('every case is "Account Already Exists", with its own message', () {
    for (final account in ExistingAccount.values) {
      expect(existingAccountCopy(account).title, 'Account Already Exists');
    }
    expect(
      existingAccountCopy(ExistingAccount.registered).message,
      'An account with this email address is already registered with '
      'AgriTrade+. Please log in to continue.',
    );
    expect(
      existingAccountCopy(ExistingAccount.farmerPending).message,
      contains('under review'),
    );
    expect(
      existingAccountCopy(ExistingAccount.farmerRejected).message,
      contains('not approved'),
    );
  });

  Future<ExistingAccountChoice?> open(
    WidgetTester tester,
    ExistingAccount account, {
    required String tap,
    bool offerDifferentEmail = false,
  }) async {
    ExistingAccountChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showExistingAccountDialog(
              context,
              account,
              offerDifferentEmail: offerDifferentEmail,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tap));
    await tester.pumpAndSettle();
    return choice;
  }

  testWidgets('the registration form offers Cancel and Log In', (tester) async {
    for (final account in [
      ExistingAccount.registered,
      ExistingAccount.farmerApproved,
      ExistingAccount.farmerPending,
    ]) {
      expect(
        await open(tester, account, tap: 'Cancel'),
        ExistingAccountChoice.cancel,
      );
      expect(
        await open(tester, account, tap: 'Log In'),
        ExistingAccountChoice.login,
      );
    }
  });

  testWidgets('someone else on the same phone can still register', (
    tester,
  ) async {
    expect(
      await open(
        tester,
        ExistingAccount.farmerPending,
        tap: 'Register a different email',
        offerDifferentEmail: true,
      ),
      ExistingAccountChoice.differentEmail,
    );
  });

  testWidgets('from Create account: Log In and Register a different '
      'email, no Cancel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showExistingAccountDialog(
              context,
              ExistingAccount.registered,
              offerDifferentEmail: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Account Already Exists'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Register a different email'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    // Log In on top.
    expect(
      tester.getTopLeft(find.text('Log In')).dy,
      lessThan(tester.getTopLeft(find.text('Register a different email')).dy),
    );
  });
}
