import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../theme/app_colors.dart';

/// The reactions a chat message can get by holding it, in the picker's
/// order: the key saved in the message's `likes` map, its emoji and name.
/// firestore.rules allows exactly these keys.
const List<({String key, String emoji, String name})> kMessageReactions = [
  (key: 'heart', emoji: '❤️', name: 'Heart'),
  (key: 'like', emoji: '👍', name: 'Like'),
  (key: 'wow', emoji: '😮', name: 'Wow'),
  (key: 'sad', emoji: '😢', name: 'Sad'),
  (key: 'angry', emoji: '😠', name: 'Angry'),
];

/// One person's reaction as saved in `likes`: a key from
/// [kMessageReactions], or `true` from before reactions, which was a like.
/// Null for anything else.
String? reactionKeyOf(Object? saved) {
  if (saved == true) return 'like';
  return kMessageReactions.any((r) => r.key == saved) ? saved as String : null;
}

String _emojiOf(String key) =>
    kMessageReactions.firstWhere((r) => r.key == key).emoji;

/// Each reaction on a message with how many people chose it, most chosen
/// first (ties in the picker's order).
List<({String key, int count})> reactionCounts(Map<String, dynamic> likes) {
  final counts = <String, int>{};
  for (final saved in likes.values) {
    final key = reactionKeyOf(saved);
    if (key != null) counts[key] = (counts[key] ?? 0) + 1;
  }
  final order = [for (final r in kMessageReactions) r.key];
  return [
    for (final key in order)
      if (counts[key] != null) (key: key, count: counts[key]!),
  ]..sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0
        ? byCount
        : order.indexOf(a.key).compareTo(order.indexOf(b.key));
  });
}

/// The reactions under a message: each emoji chosen, then how many people
/// reacted in all ("❤️👍 2"). Nothing when nobody has reacted.
class MessageReactionSummary extends StatelessWidget {
  final Map<String, dynamic> likes;

  const MessageReactionSummary({super.key, required this.likes});

  @override
  Widget build(BuildContext context) {
    final counts = reactionCounts(likes);
    if (counts.isEmpty) return const SizedBox.shrink();
    final total = counts.fold<int>(0, (sum, r) => sum + r.count);
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey(200)),
      ),
      child: Text(
        '${counts.map((r) => _emojiOf(r.key)).join()} $total',
        style: TextStyle(fontSize: 11, color: AppColors.grey(700)),
      ),
    );
  }
}

/// The five reactions in a small bar above where the message was held
/// ([position], on screen). The person's current reaction ([current]) is
/// marked; choosing it again takes it off. Resolves to the key chosen, or
/// null if dismissed.
Future<String?> showReactionPicker(
  BuildContext context, {
  required Offset position,
  String? current,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tl('Close'),
    barrierColor: Colors.black12,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (dialogContext, _, _) {
      final size = MediaQuery.sizeOf(dialogContext);
      const width = 5 * 48.0 + 16;
      final left = (position.dx - width / 2).clamp(8.0, size.width - width - 8);
      final top = (position.dy - 72).clamp(8.0, size.height - 64);
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: Material(
              color: AppColors.surface,
              elevation: 6,
              shape: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final reaction in kMessageReactions)
                      Semantics(
                        button: true,
                        selected: reaction.key == current,
                        label: tl(reaction.name),
                        child: InkWell(
                          key: ValueKey('reaction-${reaction.key}'),
                          customBorder: const CircleBorder(),
                          onTap: () =>
                              Navigator.pop(dialogContext, reaction.key),
                          child: Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: reaction.key == current
                                ? BoxDecoration(
                                    color: AppColors.grey(200),
                                    shape: BoxShape.circle,
                                  )
                                : null,
                            child: ExcludeSemantics(
                              child: Text(
                                reaction.emoji,
                                style: const TextStyle(fontSize: 26),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}
