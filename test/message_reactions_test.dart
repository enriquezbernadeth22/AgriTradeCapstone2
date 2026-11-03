// Holding a chat message offers five reactions — Heart, Like, Wow, Sad and
// Angry — and the message shows which were chosen and how many in all. A
// like from before reactions still counts as a Like.
import 'package:agritrade/widgets/message_reactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the five reactions, in order', () {
    expect(kMessageReactions.map((r) => r.emoji), [
      '❤️',
      '👍',
      '😮',
      '😢',
      '😠',
    ]);
    expect(kMessageReactions.map((r) => r.key), [
      'heart',
      'like',
      'wow',
      'sad',
      'angry',
    ]);
  });

  test('a like from before reactions counts as a Like', () {
    expect(reactionKeyOf(true), 'like');
    expect(reactionKeyOf('wow'), 'wow');
    expect(reactionKeyOf('laugh'), null);
    expect(reactionKeyOf(false), null);
  });

  test('reactions are counted, most chosen first', () {
    expect(
      reactionCounts({'a': 'sad', 'b': 'heart', 'c': true, 'd': 'heart'}),
      [
        (key: 'heart', count: 2),
        (key: 'like', count: 1),
        (key: 'sad', count: 1),
      ],
    );
  });

  testWidgets('a message shows its reactions and the total', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageReactionSummary(
            likes: {'a': 'heart', 'b': 'heart', 'c': 'wow'},
          ),
        ),
      ),
    );
    expect(find.text('❤️😮 3'), findsOneWidget);
  });

  testWidgets('no reactions, nothing shown', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MessageReactionSummary(likes: {})),
      ),
    );
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('the picker offers all five and returns the one tapped', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    final chosen = showReactionPicker(
      ctx,
      position: const Offset(200, 300),
      current: 'like',
    );
    await tester.pumpAndSettle();
    for (final emoji in ['❤️', '👍', '😮', '😢', '😠']) {
      expect(find.text(emoji), findsOneWidget);
    }
    // The current one is marked.
    final like = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('reaction-like')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(like.properties.selected, isTrue);

    await tester.tap(find.text('😢'));
    await tester.pumpAndSettle();
    expect(await chosen, 'sad');
  });
}
