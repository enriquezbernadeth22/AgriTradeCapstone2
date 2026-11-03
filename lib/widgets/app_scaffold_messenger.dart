import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The app's own [ScaffoldMessenger] (placed around every screen in
/// main.dart), so every system message (SnackBar) behaves the same:
///
///  * it shows for [shortDuration] instead of Flutter's 4 seconds — unless
///    it has a button to tap (an action) or sets its own duration;
///  * a new message replaces the one on screen at once, instead of waiting
///    in line behind it (which is what made messages seem late).
class AppScaffoldMessenger extends ScaffoldMessenger {
  const AppScaffoldMessenger({super.key, required super.child});

  static const Duration shortDuration = Duration(seconds: 2);

  @override
  ScaffoldMessengerState createState() => _AppScaffoldMessengerState();
}

class _AppScaffoldMessengerState extends ScaffoldMessengerState {
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    removeCurrentSnackBar();
    return super.showSnackBar(
      shortenedSnackBar(snackBar),
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
  }
}

/// [snackBar] shown for [AppScaffoldMessenger.shortDuration], when it
/// would otherwise use the default 4 seconds and has no action.
SnackBar shortenedSnackBar(SnackBar snackBar) {
  const flutterDefault = Duration(milliseconds: 4000);
  if (snackBar.action != null || snackBar.duration != flutterDefault) {
    return snackBar;
  }
  return SnackBar(
    key: snackBar.key,
    content: snackBar.content,
    backgroundColor: snackBar.backgroundColor,
    elevation: snackBar.elevation,
    margin: snackBar.margin,
    padding: snackBar.padding,
    width: snackBar.width,
    shape: snackBar.shape,
    hitTestBehavior: snackBar.hitTestBehavior,
    behavior: snackBar.behavior,
    actionOverflowThreshold: snackBar.actionOverflowThreshold,
    showCloseIcon: snackBar.showCloseIcon,
    closeIconColor: snackBar.closeIconColor,
    duration: AppScaffoldMessenger.shortDuration,
    persist: snackBar.persist,
    animation: snackBar.animation,
    onVisible: snackBar.onVisible,
    dismissDirection: snackBar.dismissDirection,
    clipBehavior: snackBar.clipBehavior,
  );
}

/// What a system message tells the person, which sets its colour and icon.
enum MessageKind {
  /// Something failed or was refused ("Incorrect email or password."): red.
  error,

  /// Something worked ("Reset link sent."): green.
  success,

  /// A caution ("Your session is about to expire."): amber.
  warning,

  /// A plain heads-up ("You can update this later."): blue-grey.
  info,
}

/// The bar colour of each [MessageKind]. White text reads on all four.
Color messageColor(MessageKind kind) => AppColors.isDark
    // Dark mode: the same four, muted so they sit calmly on charcoal.
    ? switch (kind) {
        MessageKind.error => const Color(0xFFA23B37),
        MessageKind.success => const Color(0xFF2E7D32),
        MessageKind.warning => const Color(0xFF9A5B12),
        MessageKind.info => const Color(0xFF44525A),
      }
    : switch (kind) {
        MessageKind.error => const Color(0xFFC62828),
        MessageKind.success => AppTheme.dark,
        MessageKind.warning => const Color(0xFFB45309),
        MessageKind.info => const Color(0xFF455A64),
      };

IconData _messageIcon(MessageKind kind) => switch (kind) {
  MessageKind.error => Icons.error_outline_rounded,
  MessageKind.success => Icons.check_circle_outline_rounded,
  MessageKind.warning => Icons.warning_amber_rounded,
  MessageKind.info => Icons.info_outline_rounded,
};

/// A system message (SnackBar) in [kind]'s colour, with its icon before
/// [message]. [action], when given, is shown in white on the bar.
SnackBar appSnackBar(
  String message, {
  required MessageKind kind,
  SnackBarAction? action,
  Duration duration = const Duration(milliseconds: 4000),
  bool showCloseIcon = false,
}) {
  return SnackBar(
    backgroundColor: messageColor(kind),
    duration: duration,
    showCloseIcon: showCloseIcon,
    closeIconColor: Colors.white,
    action: action == null
        ? null
        : SnackBarAction(
            label: action.label,
            onPressed: action.onPressed,
            textColor: Colors.white,
          ),
    content: Row(
      children: [
        Icon(_messageIcon(kind), color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: const TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

/// Shows [message] as a system message of [kind] (see [appSnackBar]).
/// Does nothing if there is no messenger above [context].
void showAppMessage(
  BuildContext context,
  String message, {
  required MessageKind kind,
  SnackBarAction? action,
  Duration duration = const Duration(milliseconds: 4000),
}) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    appSnackBar(message, kind: kind, action: action, duration: duration),
  );
}
