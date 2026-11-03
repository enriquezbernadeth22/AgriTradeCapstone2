// Someone who registers with Google is asked for a photo once, on coming
// into the app, instead of in the registration form.
import 'package:agritrade/widgets/profile_photo_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a Google account with no photo is asked', () {
    expect(
      ProfilePhotoPrompt.shouldAsk(
        providers: const ['google.com'],
        savedPhoto: null,
        alreadyAsked: false,
      ),
      isTrue,
    );
    expect(
      ProfilePhotoPrompt.shouldAsk(
        providers: const ['password', 'google.com'],
        savedPhoto: '  ',
        alreadyAsked: false,
      ),
      isTrue,
    );
  });

  test('nobody else is asked, and nobody is asked twice', () {
    expect(
      ProfilePhotoPrompt.shouldAsk(
        providers: const ['google.com'],
        savedPhoto: 'https://example.com/me.jpg',
        alreadyAsked: false,
      ),
      isFalse,
    );
    expect(
      ProfilePhotoPrompt.shouldAsk(
        providers: const ['password'],
        savedPhoto: null,
        alreadyAsked: false,
      ),
      isFalse,
    );
    expect(
      ProfilePhotoPrompt.shouldAsk(
        providers: const ['google.com'],
        savedPhoto: null,
        alreadyAsked: true,
      ),
      isFalse,
    );
  });

  Future<ProfilePhotoChoice?> answer(
    WidgetTester tester,
    String button, {
    String? googlePhotoUrl,
  }) async {
    ProfilePhotoChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await showDialog<ProfilePhotoChoice>(
                context: context,
                builder: (_) =>
                    ProfilePhotoDialog(googlePhotoUrl: googlePhotoUrl),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
    return choice;
  }

  testWidgets('with no Google photo the choice is to upload or wait', (
    tester,
  ) async {
    expect(await answer(tester, 'Upload a photo'), ProfilePhotoChoice.upload);
    expect(find.text('Use Google photo'), findsNothing);
  });

  testWidgets('"Not now" saves nothing', (tester) async {
    expect(await answer(tester, 'Not now'), isNull);
  });
}
