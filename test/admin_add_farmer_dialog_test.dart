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
  group('the default password', () {
    test('is exactly 12 random characters that meet the password rules', () {
      final rng = Random(1);
      final passwords = {
        for (var i = 0; i < 300; i++) generateFarmerPassword(random: rng),
      };
      expect(passwords, hasLength(300));
      for (final password in passwords) {
        expect(password, hasLength(12), reason: password);
        expect(PasswordRules.meetsAll(password), isTrue, reason: password);
      }
    });

    test('leaves out characters that look alike', () {
      final rng = Random(2);
      for (var i = 0; i < 300; i++) {
        expect(
          generateFarmerPassword(random: rng),
          isNot(matches(RegExp(r'[0O1lI]'))),
        );
      }
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
    expect(find.text('Choose what best describes the farmer.'), findsOneWidget);
    expect(find.textContaining('Enter the RSBSA number'), findsOneWidget);
    // The password is already filled in with the default one.
    expect(find.textContaining('The password needs 12+'), findsNothing);
    expect(
      find.textContaining('Confirm that the farmer agreed'),
      findsOneWidget,
    );
  });

  testWidgets('the dialog opens with a default password, and Generate '
      'makes a new one', (tester) async {
    await _open(tester);
    String password() => tester
        .widgetList<TextField>(find.byType(TextField))
        .map((field) => field.controller?.text ?? '')
        .firstWhere(PasswordRules.meetsAll);

    final first = password();
    expect(first, hasLength(12));

    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(password(), isNot(first));
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
      final dropdowns = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdowns.first);
      await tester.pumpAndSettle();
      await tester.tap(dropdowns.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gulod').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(dropdowns.last);
      await tester.pumpAndSettle();
      await tester.tap(dropdowns.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crop Farmer').last);
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
