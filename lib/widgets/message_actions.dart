import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_language.dart';
import '../theme/app_colors.dart';
import 'message_reactions.dart';

/// Slides a chat message sideways under the finger to reply to it: a
/// received message to the right, your own to the left, with a reply arrow
/// appearing behind it. Past [threshold] the phone ticks; letting go there
/// replies, and the message slides back either way.
class SwipeToReply extends StatefulWidget {
  final Widget child;

  /// Your own message (slides to the left).
  final bool mine;
  final VoidCallback? onReply;

  const SwipeToReply({
    super.key,
    required this.child,
    required this.mine,
    this.onReply,
  });

  /// How far the message must slide to reply.
  static const double threshold = 56;

  /// The furthest it slides.
  static const double maxSlide = 80;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  double _offset = 0;
  bool _armed = false;
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() => setState(() => _offset = _from * (1 - _back.value)));
  double _from = 0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  // Signed: positive slides right (received), negative left (mine).
  double get _direction => widget.mine ? -1 : 1;

  void _update(DragUpdateDetails details) {
    final moved = (_offset + details.delta.dx) * _direction;
    final next = moved.clamp(0.0, SwipeToReply.maxSlide) * _direction;
    final armed = next.abs() >= SwipeToReply.threshold;
    if (armed && !_armed) HapticFeedback.selectionClick();
    setState(() {
      _offset = next;
      _armed = armed;
    });
  }

  void _end(DragEndDetails _) {
    if (_armed) widget.onReply?.call();
    _armed = false;
    _from = _offset;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) return widget.child;
    final progress = (_offset.abs() / SwipeToReply.threshold).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: () => _end(DragEndDetails()),
      child: Stack(
        alignment: widget.mine ? Alignment.centerRight : Alignment.centerLeft,
        children: [
          // The reply arrow, uncovered as the message slides away from it.
          Positioned(
            left: widget.mine ? null : 8,
            right: widget.mine ? 8 : null,
            child: Opacity(
              opacity: progress,
              child: Transform.scale(
                scale: 0.6 + 0.4 * progress,
                child: Container(
                  key: const Key('swipeReplyIcon'),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _armed ? AppColors.brandFill : AppColors.grey(200),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.reply_rounded,
                    size: 18,
                    color: _armed ? Colors.white : AppColors.grey(700),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(offset: Offset(_offset, 0), child: widget.child),
        ],
      ),
    );
  }
}

/// What can be done to a held chat message.
enum MessageAction { reply, copy, pin, unpin, unsend, report }

/// What the person chose on a held message: a reaction (its key), or an
/// action. Null when they tapped away.
typedef MessageActionChoice = ({String? reaction, MessageAction? action});

/// Holding a chat message: everything else blurs and dims, the message
/// stays sharp where it was ([rect], drawn by [message]), with the
/// reactions above it and a menu under it — Reply, Copy (text only), Pin
/// or Unpin, Unsend (your own) and Report (someone else's).
Future<MessageActionChoice?> showMessageActions(
  BuildContext context, {
  required Rect rect,
  required Widget message,
  required bool mine,
  bool canCopy = true,
  bool canReply = true,
  bool pinned = false,
  bool canReact = true,
  String? currentReaction,
}) {
  final actions = <MessageAction>[
    if (canReply) MessageAction.reply,
    if (canCopy) MessageAction.copy,
    pinned ? MessageAction.unpin : MessageAction.pin,
    if (mine) MessageAction.unsend,
    if (!mine) MessageAction.report,
  ];
  return Navigator.of(context).push<MessageActionChoice>(
    PageRouteBuilder<MessageActionChoice>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (context, animation, _) => FadeTransition(
        opacity: animation,
        child: _MessageActionsSheet(
          rect: rect,
          message: message,
          mine: mine,
          actions: actions,
          canReact: canReact,
          currentReaction: currentReaction,
        ),
      ),
    ),
  );
}

class _MessageActionsSheet extends StatelessWidget {
  final Rect rect;
  final Widget message;
  final bool mine;
  final List<MessageAction> actions;
  final bool canReact;
  final String? currentReaction;

  const _MessageActionsSheet({
    required this.rect,
    required this.message,
    required this.mine,
    required this.actions,
    required this.canReact,
    required this.currentReaction,
  });

  static const double _reactionsHeight = 52;
  static const double _rowHeight = 46;
  static const double _menuWidth = 210;
  static const double _gap = 8;

  (IconData, String, bool danger) _look(MessageAction action) =>
      switch (action) {
        MessageAction.reply => (Icons.reply_rounded, tl('Reply'), false),
        MessageAction.copy => (Icons.copy_rounded, tl('Copy'), false),
        MessageAction.pin => (Icons.push_pin_outlined, tl('Pin'), false),
        MessageAction.unpin => (Icons.push_pin, tl('Unpin'), false),
        MessageAction.unsend => (Icons.undo_rounded, tl('Unsend'), true),
        MessageAction.report => (Icons.flag_outlined, tl('Report'), true),
      };

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final top = media.padding.top + 8;
    final bottom = screen.height - media.padding.bottom - 8;
    final menuHeight = actions.length * _rowHeight + 12;
    final above = canReact ? _reactionsHeight + _gap : 0.0;

    // The message stays where it was, moved only as much as needed for the
    // reactions above and the menu below to fit on the screen.
    var messageTop = rect.top;
    final lowest = bottom - menuHeight - _gap - rect.height;
    if (messageTop > lowest) messageTop = lowest;
    if (messageTop < top + above) messageTop = top + above;

    final sideLeft = mine ? null : rect.left;
    final sideRight = mine ? screen.width - rect.right : null;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const Key('messageActionsBackdrop'),
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
              ),
            ),
          ),
          if (canReact)
            Positioned(
              top: messageTop - _reactionsHeight - _gap,
              left: mine ? null : rect.left,
              right: mine ? screen.width - rect.right : null,
              child: _reactions(context),
            ),
          Positioned(
            top: messageTop,
            left: rect.left,
            width: rect.width,
            child: IgnorePointer(child: message),
          ),
          Positioned(
            top: messageTop + rect.height + _gap,
            left: sideLeft,
            right: sideRight,
            width: _menuWidth,
            child: _menu(context),
          ),
        ],
      ),
    );
  }

  Widget _reactions(BuildContext context) => Container(
    height: _reactionsHeight,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(_reactionsHeight / 2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final reaction in kMessageReactions)
          Tooltip(
            message: reaction.name,
            child: InkWell(
              key: Key('reaction-${reaction.key}'),
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(
                context,
              ).pop((reaction: reaction.key, action: null)),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: reaction.key == currentReaction
                    ? BoxDecoration(
                        color: AppColors.tint,
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Text(
                  reaction.emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _menu(BuildContext context) => Material(
    color: AppColors.surface,
    elevation: 8,
    shadowColor: Colors.black.withValues(alpha: 0.3),
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            Builder(
              builder: (context) {
                final (icon, label, danger) = _look(action);
                final color = danger
                    ? AppColors.tone(Colors.red, 700)
                    : AppColors.text;
                return InkWell(
                  key: Key('messageAction-${action.name}'),
                  onTap: () => Navigator.of(
                    context,
                  ).pop((reaction: null, action: action)),
                  child: SizedBox(
                    height: _rowHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ),
                          Icon(icon, size: 19, color: color),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );
}
