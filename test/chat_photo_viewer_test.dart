// A photo or video sent in a chat opens full screen, where Save puts a copy
// in the phone's gallery and says how it went: saved, not allowed, or failed.
import 'package:agritrade/services/gallery_saver.dart';
import 'package:agritrade/theme/app_colors.dart';
import 'package:agritrade/widgets/app_scaffold_messenger.dart';
import 'package:agritrade/widgets/chat_photo_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  const url = 'https://res.cloudinary.com/gxir71bo/image/upload/v1/a.jpg';

  Future<List<String>> pumpViewer(
    WidgetTester tester,
    SaveResult result,
  ) async {
    final saved = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScaffoldMessenger(child: child!),
        home: ChatPhotoViewer(
          url: url,
          caption: 'Junior · Nov 3',
          save: (u) async {
            saved.add(u);
            return result;
          },
        ),
      ),
    );
    await tester.pump();
    return saved;
  }

  testWidgets('the photo can be zoomed, and Save saves that photo', (
    tester,
  ) async {
    final saved = await pumpViewer(tester, SaveResult.saved);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Junior · Nov 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('saveToGallery')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(saved, [url]);
    expect(find.text('Photo saved to your gallery.'), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
      messageColor(MessageKind.success),
    );
  });

  testWidgets('not allowed to save: says how to allow it', (tester) async {
    await pumpViewer(tester, SaveResult.accessDenied);
    await tester.tap(find.byKey(const Key('saveToGallery')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Allow it in your phone settings'), findsOne);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
      messageColor(MessageKind.warning),
    );
  });

  testWidgets('a failed save is an error', (tester) async {
    await pumpViewer(tester, SaveResult.failed);
    await tester.tap(find.byKey(const Key('saveToGallery')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Could not save the photo'), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
      messageColor(MessageKind.error),
    );
    // The viewer stays black, whatever the app's theme.
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      isNot(AppColors.page),
    );
  });

  testWidgets('a video can be saved too, and says so', (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScaffoldMessenger(child: child!),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              SaveToGalleryButton(
                url: 'https://res.cloudinary.com/x/video/upload/v1/a.mp4',
                video: true,
                save: (u) async {
                  saved.add(u);
                  return SaveResult.saved;
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('saveToGallery')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(saved, hasLength(1));
    expect(find.text('Video saved to your gallery.'), findsOneWidget);
  });
}
