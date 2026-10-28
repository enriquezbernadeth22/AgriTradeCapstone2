import 'dart:async';
import 'dart:math';

import 'package:agritrade/screen/admin_add_farmer_dialog.dart';
import 'package:agritrade/screen/admin_dashboard_screen.dart';
import 'package:agritrade/widgets/password_requirements.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(WidgetTester tester, {AddFarmerBackend? backend}) async {
  tester.view.physicalSize = const Size(1200, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: AdminThemeScope(
        palette: AdminPalette.light,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddFarmerDialog(context, backend: backend),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('the generated password', () {
    test('is made from the first and last name, exactly 12 characters', () {
      String gen(String first, String last) => memorableFarmerPassword(
        firstName: first,
        lastName: last,
        random: Random(1),
      )!;
      // Both names when they fit…
      expect(gen('Ana', 'Go'), matches(RegExp(r'^AnaGo@\d{6}$')));
      // …else the first initial and the last name.
      expect(gen('juan', 'dela cruz'), matches(RegExp(r'^JDelaCruz@\d{2}$')));
      expect(gen('Maria', 'Santos'), matches(RegExp(r'^MSantos@\d{4}$')));
      for (final password in [
        gen('Ana', 'Go'),
        gen('juan', 'dela cruz'),
        gen('Maria', 'Santos'),
      ]) {
        expect(password, hasLength(12));
        expect(PasswordRules.meetsAll(password), isTrue, reason: password);
      }
    });

    test('meets the rules for long and odd names', () {
      for (final (first, last) in [
        ('Ma. Teresa', 'Villanueva-Macaraeg'),
        ('A.', 'B.'),
        ('JOSE', 'NG'),
        ("D'Angelo", "O'Neil"),
      ]) {
        final password = memorableFarmerPassword(
          firstName: first,
          lastName: last,
        )!;
        expect(password, hasLength(12), reason: password);
        expect(PasswordRules.meetsAll(password), isTrue, reason: password);
      }
    });

    test('needs both names', () {
      expect(memorableFarmerPassword(firstName: '', lastName: 'Cruz'), isNull);
      expect(memorableFarmerPassword(firstName: 'Juan', lastName: ''), isNull);
    });
  });

  testWidgets('Add Farmer asks for every detail, a password and the '
      'farmer\'s agreement before anything is sent', (tester) async {
    await _open(tester);

    expect(find.text('First name'), findsOneWidget);
    expect(find.text('Last name'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Send confirmation'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Enter the first name.'), findsOneWidget);
    expect(find.text('Enter the last name.'), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(
      find.text('Enter a valid mobile number (9XX XXX XXXX).'),
      findsOneWidget,
    );
    expect(find.text("Choose the farmer's barangay."), findsOneWidget);
    expect(find.textContaining('Enter the RSBSA number'), findsOneWidget);
    expect(find.textContaining('The password needs 12+'), findsOneWidget);
    expect(
      find.textContaining('Confirm that the farmer agreed'),
      findsOneWidget,
    );
  });

  testWidgets('Generate asks for the first and last name first', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Fill in the First name and Last name first'),
      findsOneWidget,
    );
  });

  testWidgets('the Terms of Service opens from the agreement line, the '
      'same text as the app', (tester) async {
    await _open(tester);
    await tester.tapOnText(find.textRange.ofSubstring('Terms of Service'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('AgriTrade+ Terms of Service'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('AgriTrade+ Terms of Service'), findsNothing);
  });

  testWidgets('the mobile number keeps only the 10 digits after +63', (
    tester,
  ) async {
    await _open(tester);
    final mobile = find.byType(TextField).at(3);
    await tester.enterText(mobile, '9123456789555885');
    expect(tester.widget<TextField>(mobile).controller!.text, '9123456789');
    await tester.enterText(mobile, '+63 917 123 4567');
    expect(tester.widget<TextField>(mobile).controller!.text, '9171234567');
  });

  group('the farmer confirms by email before the account is added', () {
    late StreamController<String> status;
    late List<Map<String, Object?>> sent;
    late List<String> cancelled;

    AddFarmerBackend backend() => AddFarmerBackend(
      sendInvite: (details) async {
        sent.add(details);
        return 'invite1';
      },
      watchInvite: (id) => status.stream,
      cancelInvite: (id) async => cancelled.add(id),
    );

    setUp(() {
      status = StreamController<String>();
      sent = [];
      cancelled = [];
    });
    tearDown(() => status.close());

    Future<void> fillAndSend(WidgetTester tester) async {
      await _open(tester, backend: backend());
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Juan');
      await tester.enterText(fields.at(1), 'Dela Cruz');
      await tester.enterText(fields.at(2), 'juan@gmail.com');
      await tester.enterText(fields.at(3), '09171234567');
      await tester.enterText(fields.at(4), '041234567890123');
      await tester.enterText(fields.at(5), 'JDelaCruz@47');
      await tester.enterText(fields.at(6), 'JDelaCruz@47');
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gulod').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Send confirmation'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('it waits, then shows the login once confirmed', (
      tester,
    ) async {
      await fillAndSend(tester);
      expect(tester.takeException(), isNull);
      expect(sent, hasLength(1));
      expect(sent.single['mobileNumber'], '+639171234567');
      expect(sent.single['barangay'], 'Gulod');

      expect(find.text('Waiting for the farmer'), findsOneWidget);
      expect(
        find.text('Waiting for Juan Dela Cruz to confirm…'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('JDelaCruz@47'), findsOneWidget);

      status.add('pending');
      await tester.pump();
      expect(find.text('Waiting for the farmer'), findsOneWidget);

      status.add('confirmed');
      await tester.pump();
      expect(find.text('Farmer account added'), findsOneWidget);
      expect(find.textContaining('confirmed by email'), findsOneWidget);
      expect(find.text('JDelaCruz@47'), findsOneWidget);
    });

    testWidgets('"No, it\'s not me" adds nothing', (tester) async {
      await fillAndSend(tester);
      status.add('declined');
      await tester.pump();
      expect(find.text('Farmer not added'), findsOneWidget);
      expect(find.textContaining("No, it's not me"), findsOneWidget);
    });

    testWidgets('the Admin can cancel the request', (tester) async {
      await fillAndSend(tester);
      await tester.tap(find.text('Cancel request'));
      await tester.pumpAndSettle();
      expect(cancelled, ['invite1']);
      expect(find.text('Waiting for the farmer'), findsNothing);
    });
  });
}
