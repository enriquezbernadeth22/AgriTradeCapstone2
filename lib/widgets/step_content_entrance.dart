import 'package:flutter/material.dart';

/// How long a registration step's content takes to come in.
const Duration kStepContentDuration = Duration(milliseconds: 380);

/// Brings a registration step's content in from the side, fading as it
/// comes: from the right going on, from the left ([fromLeft]) going back.
///
/// Only what it wraps moves. The header and the steps (1, 2, 3) sit above
/// it and stay still, so moving between steps reads as one screen whose
/// content changes. A new [key] plays it again; with animations turned off
/// on the phone the content simply appears.
class StepContentEntrance extends StatelessWidget {
  /// Comes in from the left (going back a step), else from the right.
  final bool fromLeft;
  final Widget child;

  const StepContentEntrance({
    super.key,
    this.fromLeft = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final dx = fromLeft ? -0.12 : 0.12;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: kStepContentDuration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: FractionalTranslation(
          translation: Offset(dx * (1 - t), 0),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// The route between registration steps: no movement of its own, since the
/// next step has the same header and steps in the same place. Its content
/// comes in by itself (see [StepContentEntrance]).
PageRouteBuilder<T> registrationStepRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => page,
  );
}
