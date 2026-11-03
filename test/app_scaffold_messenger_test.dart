// System messages: 2 seconds each, and a new one replaces the one showing
// instead of waiting behind it; a message with a button keeps its time.
import 'package:agritrade/widgets/app_scaffold_messenger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('2 seconds, newest replaces the one showing', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScaffoldMessenger(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('A')));
    await tester.pump();
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('B')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('B'), findsNothing);
  });

  test('a message with a button keeps its own time', () {
    final withAction = SnackBar(
      content: const Text('x'),
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
    );
    expect(identical(shortenedSnackBar(withAction), withAction), isTrue);
    expect(
      shortenedSnackBar(const SnackBar(content: Text('x'))).duration,
      AppScaffoldMessenger.shortDuration,
    );
  });

  testWidgets('a message is coloured by what it says: red for an error, '
      'green for success, amber for a warning, blue-grey for a heads-up', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScaffoldMessenger(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    const expected = {
      MessageKind.error: (Color(0xFFC62828), Icons.error_outline_rounded),
      MessageKind.success: (
        Color.fromARGB(255, 14, 50, 16),
        Icons.check_circle_outline_rounded,
      ),
      MessageKind.warning: (Color(0xFFB45309), Icons.warning_amber_rounded),
      MessageKind.info: (Color(0xFF455A64), Icons.info_outline_rounded),
    };
    for (final MapEntry(key: kind, value: (color, icon)) in expected.entries) {
      showAppMessage(ctx, 'Incorrect email or password.', kind: kind);
      await tester.pumpAndSettle();
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.backgroundColor, color, reason: '$kind');
      expect(find.byIcon(icon), findsOneWidget, reason: '$kind');
      expect(find.text('Incorrect email or password.'), findsOneWidget);
    }
  });

  test(
    'a button on a coloured message is white, so it reads on any colour',
    () {
      final bar = appSnackBar(
        'Location permission is needed.',
        kind: MessageKind.warning,
        action: SnackBarAction(label: 'Select Manually', onPressed: () {}),
      );
      expect(bar.action!.textColor, Colors.white);
      expect(bar.action!.label, 'Select Manually');
    },
  );
}
