import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

/// One stop of a first-time tour: a widget to point at (via [targetKey])
/// plus the short hint shown next to it.
class CoachMarkStep {
  final GlobalKey targetKey;
  final String title;
  final String message;

  const CoachMarkStep({
    required this.targetKey,
    required this.title,
    required this.message,
  });
}

/// The app's first-time tips as a whole: the tours on each screen
/// ([showCoachMarksOnce]) and the Market tab's section hints. Skip on any
/// hint turns them all off; Help & Support's "Show tips again" turns them
/// back on and forgets which have been seen.
class TutorialTips {
  TutorialTips._();

  /// Set once Skip is tapped: no tour shows any more.
  static const offKey = 'tips_off';

  /// Each screen's tour remembers it was seen under a key starting so.
  static const tourKeyPrefix = 'tour_seen_';

  // Older names of the home screens' tours, and the Market tab's place.
  static const _otherSeenPrefixes = [
    'walkthrough_seen_',
    'market_tab_hints_',
    'orders_swipe_tutorial_seen_',
  ];

  static Future<bool> isOff() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(offKey) ?? false;
    } catch (_) {
      return true; // Can't tell: safer to stay quiet than to nag.
    }
  }

  /// Skip: no more tips anywhere.
  static Future<void> skipAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(offKey, true);
    } catch (_) {}
  }

  /// Every tip shows again, each the next time its screen opens.
  static Future<void> showAgain() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (key == offKey ||
            key.startsWith(tourKeyPrefix) ||
            _otherSeenPrefixes.any(key.startsWith)) {
          await prefs.remove(key);
        }
      }
    } catch (_) {}
  }
}

// One tour at a time: a screen's tour that comes up while another is
// showing (a tab opened during the home tour) waits for it to end.
Completer<void>? _activeTour;

/// A first-time tour, once ever per device per [prefsKey]: it dims the page,
/// highlights each button, and shows a light hint card with Skip. The
/// user's taps move it along; while a popup or another screen is in front,
/// the hints wait.
///
/// Only the steps whose button is on screen when it starts are shown; with
/// none, nothing shows and it is tried again the next time. Nothing shows
/// once the tips are off ([TutorialTips]).
///
/// Call it after the screen's first frame (e.g. from a post-frame callback
/// in initState).
Future<void> showCoachMarksOnce({
  required BuildContext context,
  required String prefsKey,
  required List<CoachMarkStep> steps,
}) async {
  while (_activeTour != null && !_activeTour!.isCompleted) {
    await _activeTour!.future;
  }
  if (!context.mounted) return;
  final mine = Completer<void>();
  _activeTour = mine;
  try {
    await _runTour(context: context, prefsKey: prefsKey, steps: steps);
  } finally {
    if (!mine.isCompleted) mine.complete();
  }
}

Future<void> _runTour({
  required BuildContext context,
  required String prefsKey,
  required List<CoachMarkStep> steps,
}) async {
  if (steps.isEmpty) return;
  late final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(prefsKey) ?? false) return;
    if (prefs.getBool(TutorialTips.offKey) ?? false) return;
  } catch (_) {
    return; // Can't remember "seen" — safer to skip than nag every launch.
  }

  // Give the frame a moment to settle (layout/animations) before measuring.
  await Future.delayed(const Duration(milliseconds: 500));
  if (!context.mounted) return;
  // Not while another screen or a popup is in front of this one: it waits
  // for this screen to be back in front (or gone).
  while (context.mounted && !(ModalRoute.of(context)?.isCurrent ?? true)) {
    await Future.delayed(const Duration(milliseconds: 300));
  }
  if (!context.mounted) return;

  final screen = MediaQuery.sizeOf(context);
  final shown = steps.where((step) {
    final box = step.targetKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    // Wholly on screen: not below the fold, nor on a tab off to the side.
    return rect.top >= 0 &&
        rect.bottom <= screen.height &&
        rect.left >= 0 &&
        rect.right <= screen.width &&
        rect.width > 0;
  }).toList();
  if (shown.isEmpty) return;
  try {
    await prefs.setBool(prefsKey, true);
  } catch (_) {
    return;
  }
  if (!context.mounted) return;

  final done = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CoachHints(
      host: context,
      steps: shown,
      onDone: () {
        entry.remove();
        if (!done.isCompleted) done.complete();
      },
      // Taken away with its screen (or the app): the next tour may start.
      onGone: () {
        if (!done.isCompleted) done.complete();
      },
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return done.future;
}

class _CoachHints extends StatefulWidget {
  /// The screen the tour belongs to.
  final BuildContext host;
  final List<CoachMarkStep> steps;
  final VoidCallback onDone;
  final VoidCallback onGone;

  const _CoachHints({
    required this.host,
    required this.steps,
    required this.onDone,
    required this.onGone,
  });

  @override
  State<_CoachHints> createState() => _CoachHintsState();
}

class _CoachHintsState extends State<_CoachHints>
    with SingleTickerProviderStateMixin {
  // The arrow's gentle bounce; it also redraws the hint every frame, so it
  // follows its button and notices when the screen is covered.
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  var _index = 0;
  var _finished = false;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _bounce.dispose();
    widget.onGone();
    super.dispose();
  }

  bool get _hostShowing {
    if (!widget.host.mounted) return false;
    return ModalRoute.of(widget.host)?.isCurrent ?? true;
  }

  // Fingers that went down while the hint was showing. A tap is judged by
  // where it started: one on a popup's button closes the popup before
  // the tour sees it lift, and must not count as a step.
  final _downWhileShowing = <int>{};

  // Any tap — a lifted finger — while a hint is up moves the tour along.
  // The tap itself still reaches whatever was under it.
  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (_hostShowing) _downWhileShowing.add(event.pointer);
      return;
    }
    if (event is PointerCancelEvent) {
      _downWhileShowing.remove(event.pointer);
      return;
    }
    if (event is! PointerUpEvent) return;
    final counts = _downWhileShowing.remove(event.pointer);
    if (!counts || _finished || !_hostShowing) return;
    // Skip handles its own tap.
    if (_onSkip(event.position)) return;
    if (_index < widget.steps.length - 1) {
      setState(() => _index++);
    } else {
      _finish();
    }
  }

  final _skipKey = GlobalKey();

  // Skip: this tour ends, and no other tip shows any more.
  void _skip() {
    TutorialTips.skipAll();
    _finish();
  }

  bool _onSkip(Offset position) {
    final box = _skipKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(position);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    // Not while the pointer event is still being handled.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return const SizedBox.shrink();
    if (!widget.host.mounted) {
      _finish();
      return const SizedBox.shrink();
    }
    // Only the hint card takes taps (its Skip); the dimmed page lets them
    // through to whatever is under them.
    return AnimatedBuilder(
      animation: _bounce,
      builder: (context, _) {
        if (!_hostShowing) return const SizedBox.shrink();
        final step = widget.steps[_index];
        final box =
            step.targetKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.attached || !box.hasSize) {
          return const SizedBox.shrink();
        }
        final target = box.localToGlobal(Offset.zero) & box.size;
        return _hint(context, step, target);
      },
    );
  }

  Widget _hint(BuildContext context, CoachMarkStep step, Rect target) {
    final screen = MediaQuery.sizeOf(context);
    // Above a button in the lower half of the screen, below one higher up.
    final above = target.center.dy > screen.height / 2;
    const bubbleWidth = 250.0;
    const arrowSize = 30.0;
    const gap = 6.0;
    final lift = Curves.easeInOut.transform(_bounce.value) * 7;
    final left = (target.center.dx - bubbleWidth / 2)
        .clamp(16.0, math.max(16.0, screen.width - bubbleWidth - 16))
        .toDouble();

    final arrow = Icon(
      above ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
      size: arrowSize,
      color: AppColors.accent,
      shadows: [Shadow(color: AppColors.textSecondary, blurRadius: 6)],
    );
    final last = _index == widget.steps.length - 1;
    final bubble = _HintBubble(
      title: step.title,
      message: step.message,
      progress: widget.steps.length > 1
          ? '${_index + 1}/${widget.steps.length}'
          : null,
      footer: last
          ? tl('Tap anywhere to close')
          : tl('Tap anywhere to continue'),
      skipKey: _skipKey,
      onSkip: _skip,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _TutorialScrim(target)),
          ),
        ),
        // A soft ring around the button, in its own shape (round on an
        // icon, a rounded box on a wide field).
        Positioned.fromRect(
          rect: target.inflate(8 + lift * 0.4),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  math.min(18 + lift * 0.4, target.shortestSide / 2 + 8),
                ),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.9),
                  width: 2.5,
                ),
              ),
            ),
          ),
        ),
        // The arrow, nudging toward the button.
        Positioned(
          left: target.center.dx - arrowSize / 2,
          top: above
              ? target.top - gap - arrowSize - lift
              : target.bottom + gap + lift,
          child: IgnorePointer(child: arrow),
        ),
        Positioned(
          left: left,
          width: bubbleWidth,
          top: above ? null : target.bottom + gap + arrowSize + 12,
          bottom: above
              ? screen.height - target.top + gap + arrowSize + 12
              : null,
          child: bubble,
        ),
      ],
    );
  }
}

/// The light hint card with its place in the tour ([progress], e.g. "1/2")
/// and a line on how it goes away ([footer]).
class _HintBubble extends StatelessWidget {
  final String title;
  final String message;
  final String? progress;
  final String footer;

  /// Skip, at the foot of the card: ends the tour and turns all tips off.
  final VoidCallback? onSkip;
  final Key? skipKey;

  const _HintBubble({
    required this.title,
    required this.message,
    required this.footer,
    this.progress,
    this.onSkip,
    this.skipKey,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.grey(300)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand,
                    ),
                  ),
                ),
                if (progress != null)
                  Text(
                    progress!,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              tl(message),
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12,
                height: 1.4,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    footer,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (onSkip != null)
                  // Its own tap target, so it never counts as "continue".
                  GestureDetector(
                    key: skipKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: onSkip,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 2, 2),
                      child: Text(
                        tl('Skip'),
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brand,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Where a [showSectionHint] card's top edge must be — as a share of its
/// scroll view's height — for its hint to show: low enough to leave room
/// for the label above it, high enough that the card is in view.
const double kSectionHintBandTop = 0.28;
const double kSectionHintBandBottom = 0.78;

/// Where [key]'s top edge is in its scroll view, as a share of the view's
/// height (0 at the top, 1 at the bottom); null when it is not laid out.
double? sectionTopFraction(GlobalKey key) {
  final context = key.currentContext;
  if (context == null) return null;
  final box = context.findRenderObject() as RenderBox?;
  final scrollable = Scrollable.maybeOf(context);
  final view = scrollable?.context.findRenderObject() as RenderBox?;
  if (box == null || !box.attached || view == null || !view.attached) {
    return null;
  }
  final top = box.localToGlobal(Offset.zero).dy;
  final viewTop = view.localToGlobal(Offset.zero).dy;
  if (view.size.height == 0) return null;
  return (top - viewTop) / view.size.height;
}

/// A hint about one section of a scrolling page — a card the user has just
/// scrolled to: a soft outline around it, a bouncing arrow at its top edge
/// and a short label above. It never blocks the page. It goes away with
/// any tap, or once the card has been scrolled on past; the future then
/// completes. While a popup or another screen covers [context]'s screen
/// it waits, hidden.
Future<void> showSectionHint({
  required BuildContext context,
  required CoachMarkStep step,
  String? progress,
}) {
  final done = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _SectionHint(
      host: context,
      step: step,
      progress: progress,
      onDone: () {
        entry.remove();
        if (!done.isCompleted) done.complete();
      },
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return done.future;
}

class _SectionHint extends StatefulWidget {
  final BuildContext host;
  final CoachMarkStep step;
  final String? progress;
  final VoidCallback onDone;

  const _SectionHint({
    required this.host,
    required this.step,
    required this.progress,
    required this.onDone,
  });

  @override
  State<_SectionHint> createState() => _SectionHintState();
}

class _SectionHintState extends State<_SectionHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  // Where each finger went down while the hint was showing.
  final _downWhileShowing = <int, Offset>{};
  var _finished = false;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _bounce.dispose();
    super.dispose();
  }

  bool get _hostShowing {
    if (!widget.host.mounted) return false;
    return ModalRoute.of(widget.host)?.isCurrent ?? true;
  }

  // A tap counts when it started while the hint was showing (see
  // _CoachHintsState). A scroll is a drag, not a tap, so scrolling on does
  // not dismiss it this way — leaving the card behind does.
  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (_hostShowing) _downWhileShowing[event.pointer] = event.position;
      return;
    }
    if (event is PointerCancelEvent) {
      _downWhileShowing.remove(event.pointer);
      return;
    }
    if (event is! PointerUpEvent) return;
    final down = _downWhileShowing.remove(event.pointer);
    // A tap: the finger barely moved. The end of a scroll is not one.
    final tapped =
        down != null && (event.position - down).distance <= kTouchSlop;
    if (tapped && _hostShowing) _finish();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return const SizedBox.shrink();
    if (!widget.host.mounted) {
      _finish();
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _bounce,
        builder: (context, _) {
          if (!_hostShowing) return const SizedBox.shrink();
          final key = widget.step.targetKey;
          final box = key.currentContext?.findRenderObject() as RenderBox?;
          final fraction = sectionTopFraction(key);
          if (box == null || !box.attached || fraction == null) {
            return const SizedBox.shrink();
          }
          // Scrolled on past it (or back above it): it has been seen.
          if (fraction < 0.06 || fraction > 0.94) {
            _finish();
            return const SizedBox.shrink();
          }
          final card = box.localToGlobal(Offset.zero) & box.size;
          return _hint(context, card);
        },
      ),
    );
  }

  Widget _hint(BuildContext context, Rect card) {
    final screen = MediaQuery.sizeOf(context);
    const arrowSize = 28.0;
    const bubbleWidth = 270.0;
    final lift = Curves.easeInOut.transform(_bounce.value) * 6;
    final left = (card.center.dx - bubbleWidth / 2)
        .clamp(16.0, math.max(16.0, screen.width - bubbleWidth - 16))
        .toDouble();
    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _TutorialScrim(card))),
        // A soft outline around the card.
        Positioned.fromRect(
          rect: card.inflate(3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.95),
                width: 2.5,
              ),
            ),
          ),
        ),
        // The arrow, nudging down at the card's top edge.
        Positioned(
          left: card.center.dx - arrowSize / 2,
          top: card.top - arrowSize - 2 - lift,
          child: Icon(
            Icons.arrow_downward_rounded,
            size: arrowSize,
            color: AppColors.mid,
            shadows: [Shadow(color: Colors.white, blurRadius: 6)],
          ),
        ),
        Positioned(
          left: left,
          width: bubbleWidth,
          bottom: screen.height - card.top + arrowSize + 10,
          child: _HintBubble(
            title: widget.step.title,
            message: widget.step.message,
            progress: widget.progress,
            footer: tl('Tap anywhere to close'),
          ),
        ),
      ],
    );
  }
}

/// Dims the page while leaving the tutorial target clear and easy to find.
class _TutorialScrim extends CustomPainter {
  final Rect target;

  const _TutorialScrim(this.target);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(target.inflate(8), const Radius.circular(18)),
      );
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.42),
    );
  }

  @override
  bool shouldRepaint(_TutorialScrim oldDelegate) =>
      oldDelegate.target != target;
}
