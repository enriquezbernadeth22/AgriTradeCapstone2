// Videos in a chat: Record Video and Choose Video in the + menu, at most
// 20 MB, shown as their first frame with a play button. And the message box
// looks like the Log In field: a grey outline at rest, the soft green glow
// with no outline while typing.
import 'package:agritrade/screen/chat_attachments.dart';
import 'package:agritrade/services/cloudinary_service.dart';
import 'package:agritrade/widgets/chat_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('a chat video may be up to 20 MB', () {
    expect(kChatVideoMaxBytes, 20 * 1024 * 1024);
    expect(chatVideoFits(20 * 1024 * 1024), isTrue);
    expect(chatVideoFits(20 * 1024 * 1024 + 1), isFalse);
    expect(kChatVideoMaxDuration, const Duration(minutes: 1));
  });

  test('a video is shown by its first frame, from Cloudinary', () {
    expect(
      CloudinaryService.videoThumbnail(
        'https://res.cloudinary.com/gxir71bo/video/upload/v1730000000/agritrade/chat/abc123.mp4',
      ),
      'https://res.cloudinary.com/gxir71bo/video/upload/so_0/v1730000000/agritrade/chat/abc123.jpg',
    );
    expect(CloudinaryService.videoThumbnail('https://example.com/a.mp4'), null);
  });

  testWidgets('the + menu offers Record Video and Choose Video', (
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
    final choice = showChatAttachmentMenu(plus);
    await tester.pumpAndSettle();
    expect(find.text('Record Video'), findsOneWidget);
    expect(find.text('Choose Video'), findsOneWidget);
    await tester.tap(find.text('Choose Video'));
    await tester.pumpAndSettle();
    expect(await choice, ChatAttachment.chooseVideo);
  });

  testWidgets('a video message shows a play button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatVideoBubble(
            videoUrl:
                'https://res.cloudinary.com/gxir71bo/video/upload/v1/agritrade/chat/abc.mp4',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('the message box glows green with no outline while typing, '
      'like Log In', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposerBar(
              controller: controller,
              hintText: 'Message Junior Pesigan...',
              sending: false,
              onSend: () {},
              onAttach: (_) {},
            ),
          ),
        ),
      ),
    );

    InputDecoration decoration() =>
        tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;
    bool glows() {
      final plate = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(ChatComposerBar),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (plate.decoration! as BoxDecoration).boxShadow?.any(
            (shadow) => shadow.color.g > shadow.color.r,
          ) ??
          false;
    }

    // At rest: a thin grey outline, no glow.
    expect(glows(), isFalse);
    expect(
      decoration().enabledBorder!.borderSide.color,
      isNot(Colors.transparent),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(glows(), isTrue);
    expect(decoration().focusedBorder!.borderSide.color, Colors.transparent);
  });
}
