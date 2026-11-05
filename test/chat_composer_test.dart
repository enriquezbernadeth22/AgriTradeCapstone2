// The chat's message box and + menu: the menu lists photos and videos, then
// Share Location under a line; a photo or video shows how far it has gone
// up; and a message may be up to 1,000 characters, with a count near the
// limit and Send off over it.
import 'package:agritrade/screen/chat_attachments.dart';
import 'package:agritrade/services/cloudinary_service.dart';
import 'package:agritrade/services/message_service.dart';
import 'package:agritrade/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the + menu: photos, videos, then Share Location under a line', (
    tester,
  ) async {
    late BuildContext plus;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: Builder(
              builder: (context) {
                plus = context;
                return const SizedBox(width: 40, height: 40);
              },
            ),
          ),
        ),
      ),
    );
    showChatAttachmentMenu(plus);
    await tester.pumpAndSettle();

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    final order = [
      'Take Photo',
      'Choose Photo',
      'Record Video (30 sec max)',
      'Choose Video (100 MB max)',
      'Share Location',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(top(order[i - 1]), lessThan(top(order[i])), reason: order[i]);
    }
    expect(find.text('Camera'), findsNothing);
    expect(find.text('PHOTO'), findsNothing);
    expect(find.text('VIDEO'), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
    // A line sets Share Location apart.
    final line = tester.getTopLeft(find.byType(Divider)).dy;
    expect(line, greaterThan(top('Choose Video (100 MB max)')));
    expect(line, lessThan(top('Share Location')));
  });

  testWidgets('a photo or video shows how far it has gone up', (tester) async {
    Future<void> show(bool video, double progress) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatUploadProgress(video: video, progress: progress),
        ),
      ),
    );

    await show(true, 0.45);
    expect(find.text('Sending video… 45%'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.45,
    );

    await show(false, 0.2);
    expect(find.text('Sending photo… 20%'), findsOneWidget);

    // Up, and the message itself being saved.
    await show(true, 1);
    expect(find.text('Finishing…'), findsOneWidget);
  });

  test('upload progress is the share of the file sent so far', () {
    final seen = <double>[];
    final report = CloudinaryService.uploadProgress(seen.add)!;
    report(0, 200);
    report(50, 200);
    report(200, 200);
    report(10, 0); // No size known yet: nothing to tell.
    expect(seen, [0, 0.25, 1]);
    expect(CloudinaryService.uploadProgress(null), isNull);
  });

  group('the 1,000-character limit', () {
    late TextEditingController controller;
    late int sent;

    Future<void> pumpComposer(WidgetTester tester) async {
      controller = TextEditingController();
      addTearDown(controller.dispose);
      sent = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatComposerBar(
                controller: controller,
                hintText: 'Message',
                sending: false,
                onSend: () => sent++,
                onAttach: (_) {},
              ),
            ),
          ),
        ),
      );
    }

    Finder count() => find.byKey(const Key('chatCharacterCount'));

    test('is 1,000, counted from 900', () {
      expect(MessageService.maxTextLength, 1000);
      expect(kChatCounterFrom, 900);
    });

    testWidgets('no count until the message is near the limit', (tester) async {
      await pumpComposer(tester);
      controller.text = 'a' * 899;
      await tester.pump();
      expect(count(), findsNothing);

      controller.text = 'a' * 900;
      await tester.pump();
      expect(find.text('900/1000'), findsOneWidget);
    });

    testWidgets('over the limit the count is red and Send is off', (
      tester,
    ) async {
      await pumpComposer(tester);
      controller.text = 'a' * 1001;
      await tester.pump();
      expect(find.text('1001/1000'), findsOneWidget);
      expect(
        tester.widget<Text>(count()).style!.color,
        AppColors.tone(Colors.red, 700),
      );
      await tester.tap(find.byKey(const Key('chatSend')));
      await tester.pump();
      expect(sent, 0);

      // Back to 1,000: Send works again.
      controller.text = 'a' * 1000;
      await tester.pump();
      await tester.tap(find.byKey(const Key('chatSend')));
      await tester.pump();
      expect(sent, 1);
    });

    testWidgets('spaces at the start and end are not counted', (tester) async {
      await pumpComposer(tester);
      controller.text = '   ${'a' * 1000}   ';
      await tester.pump();
      expect(find.text('1000/1000'), findsOneWidget);
      await tester.tap(find.byKey(const Key('chatSend')));
      await tester.pump();
      expect(sent, 1);
    });
  });

  group('a health-certificate request, on the farmer\'s side', () {
    Future<List<BuildContext>> pumpRow(
      WidgetTester tester, {
      bool enabled = true,
    }) async {
      final taps = <BuildContext>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CertificateRequestRow(onAttach: enabled ? taps.add : null),
            ),
          ),
        ),
      );
      return taps;
    }

    testWidgets('a compact row: icon, the request, and Attach', (tester) async {
      await pumpRow(tester);
      expect(find.text('Health certificate requested'), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Attach'), findsOneWidget);
      // White with a thin grey border: no green fill, not a bubble.
      final row = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Health certificate requested'),
              matching: find.byType(Container),
            )
            .first,
      );
      final box = row.decoration! as BoxDecoration;
      expect(box.color, AppColors.surface);
      expect(box.border!.top.color, AppColors.grey(300));
      expect(
        tester.getSize(find.byType(CertificateRequestRow)).height,
        lessThan(44),
      );
    });

    testWidgets('Attach offers Take Photo and Choose Photo only', (
      tester,
    ) async {
      final taps = await pumpRow(tester);
      await tester.tap(find.text('Attach'));
      expect(taps, hasLength(1));

      showChatPhotoMenu(taps.single);
      await tester.pumpAndSettle();
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Choose Photo'), findsOneWidget);
      for (final other in ['Record Video', 'Choose Video', 'Share Location']) {
        expect(find.text(other), findsNothing);
      }
    });

    testWidgets('Attach is off while something is sending', (tester) async {
      await pumpRow(tester, enabled: false);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    });
  });

  testWidgets('the + steps aside while a message is typed, and comes back '
      'when the box is empty', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposerBar(
              controller: controller,
              hintText: 'Message',
              sending: false,
              onSend: () {},
              onAttach: (_) {},
            ),
          ),
        ),
      ),
    );
    Finder plus() => find.byIcon(Icons.add_circle_outline_rounded);
    expect(plus(), findsOneWidget);
    final emptyWidth = tester.getSize(find.byType(TextField)).width;

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'jANA');
    await tester.pumpAndSettle();
    expect(plus(), findsNothing);
    // The box takes the room, and the keyboard stays with it.
    expect(
      tester.getSize(find.byType(TextField)).width,
      greaterThan(emptyWidth),
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(plus(), findsOneWidget);
  });
}
