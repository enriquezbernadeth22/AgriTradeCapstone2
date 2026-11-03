import 'package:flutter/material.dart';

/// Tells the motion on a page whether its page is the one on screen, so it
/// plays when the page arrives rather than while it waits off screen.
class OnboardingPageScope extends InheritedWidget {
  final bool active;

  const OnboardingPageScope({
    super.key,
    required this.active,
    required super.child,
  });

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<OnboardingPageScope>()
          ?.active ??
      true;

  @override
  bool updateShouldNotify(OnboardingPageScope oldWidget) =>
      oldWidget.active != active;
}

/// One entrance on an onboarding page: runs once, from 0 to 1, after [delayMs],
/// when its page arrives, and then stands still. With animations turned off on
/// the phone it starts at the end.
class OnboardingMotion extends StatefulWidget {
  final int delayMs;
  final int durationMs;
  final Curve curve;
  final Widget Function(BuildContext context, double progress) builder;

  const OnboardingMotion({
    super.key,
    this.delayMs = 0,
    this.durationMs = 380,
    this.curve = Curves.easeOutCubic,
    required this.builder,
  });

  @override
  State<OnboardingMotion> createState() => _OnboardingMotionState();
}

class _OnboardingMotionState extends State<OnboardingMotion>
    with SingleTickerProviderStateMixin {
  // The delay is the first part of one animation, not a timer, so nothing is
  // left waiting when the page goes away.
  late final int _total = widget.delayMs + widget.durationMs;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _total),
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(widget.delayMs / _total, 1, curve: widget.curve),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (OnboardingPageScope.of(context) &&
        !_controller.isAnimating &&
        !_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) => widget.builder(context, _progress.value),
    );
  }
}

/// [child] fading in, from [from] and at [scaleFrom], into its place.
class OnboardingReveal extends StatelessWidget {
  final int delayMs;
  final int durationMs;
  final Curve curve;
  final Offset from;
  final double scaleFrom;
  final Widget child;

  const OnboardingReveal({
    super.key,
    this.delayMs = 0,
    this.durationMs = 380,
    this.curve = Curves.easeOutCubic,
    this.from = Offset.zero,
    this.scaleFrom = 1,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return OnboardingMotion(
      delayMs: delayMs,
      durationMs: durationMs,
      curve: curve,
      builder: (context, progress) => Opacity(
        // A curve that overshoots goes past 1 for a moment.
        opacity: progress.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: from * (1 - progress),
          child: Transform.scale(
            scale: scaleFrom + (1 - scaleFrom) * progress,
            child: child,
          ),
        ),
      ),
    );
  }
}
