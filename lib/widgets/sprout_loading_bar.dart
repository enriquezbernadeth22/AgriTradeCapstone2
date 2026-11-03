import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../l10n/app_language.dart';

/// The splash screen's loading bar: a pale green track filling dark green
/// from the left, with a small sprout standing at the end of the fill and
/// growing as it goes, and "Loading AgriTrade+…" under it. Drawn in code (no
/// image or package).
///
/// It does not report real progress — it only shows the app is working.
/// With animations turned off on the phone it stands still, two thirds full.
class SproutLoadingBar extends StatefulWidget {
  /// Width of the bar.
  final double width;

  const SproutLoadingBar({super.key, this.width = 260});

  /// How long the bar takes to fill.
  static const Duration fillTime = Duration(milliseconds: 3000);

  /// Completes once the bar is full, so the phone's splash can stay up until
  /// then even when the app loads faster than that (see AppRouter). Right
  /// away when it is full already, or when it never began.
  static Future<void> untilFilled() async {
    final started = _startedAt;
    if (started == null) return;
    final left = fillTime - DateTime.now().difference(started);
    if (left > Duration.zero) await Future<void>.delayed(left);
  }

  // When the bar began filling, for the whole app run. Starting up shows the
  // loading screen more than once in a row (app start, then the signed-in
  // check), each a new widget — they all continue this one fill instead of
  // starting another, so it plays only once.
  static DateTime? _startedAt;

  /// Starts the fill afresh (tests only).
  @visibleForTesting
  static void resetFill() => _startedAt = null;

  @override
  State<SproutLoadingBar> createState() => _SproutLoadingBarState();
}

class _SproutLoadingBarState extends State<SproutLoadingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: SproutLoadingBar.fillTime,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _fill,
    curve: Curves.easeInOut,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _fill
        ..stop()
        ..value = 0.66;
    } else if (!_fill.isAnimating && !_fill.isCompleted) {
      // Pick up where the fill already is (or stay full when it is over) —
      // once per app run, no starting over.
      final started = SproutLoadingBar._startedAt ??= DateTime.now();
      final done =
          DateTime.now().difference(started).inMilliseconds /
          SproutLoadingBar.fillTime.inMilliseconds;
      _fill.value = done.clamp(0.0, 1.0);
      if (!_fill.isCompleted) _fill.forward();
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tl('Loading AgriTrade+'),
      child: SizedBox(
        width: widget.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Its own layer, so each frame of the fill redraws only this.
            RepaintBoundary(
              child: SizedBox(
                width: widget.width,
                height: _BarPainter.height,
                child: CustomPaint(painter: _BarPainter(progress: _progress)),
              ),
            ),
            const SizedBox(height: 12),
            ExcludeSemantics(
              child: Text(
                tl('Loading AgriTrade+…'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The track, the fill and the sprout at its end.
class _BarPainter extends CustomPainter {
  final Animation<double> progress;

  _BarPainter({required this.progress}) : super(repaint: progress);

  /// Room for the sprout above the bar, and the bar.
  static const double height = 28;
  static const double _barHeight = 6;

  // The sprout at full size: from the bar to the leaves' tips.
  static const double _sproutHeight = 20;

  static Color get _track => AppColors.adapt(const Color(0xFFC5DEB0));
  static Color get _fillStart => AppColors.adapt(AppTheme.dark);
  static Color get _fillEnd => AppColors.adapt(const Color(0xFF3F8F2A));
  static Color get _leaf => AppColors.adapt(const Color(0xFF4CA531));
  static Color get _leafDark => AppColors.adapt(const Color(0xFF2E7D32));

  @override
  void paint(Canvas canvas, Size size) {
    final value = progress.value;
    final barTop = size.height - _barHeight;
    const radius = Radius.circular(_barHeight / 2);
    final track = RRect.fromLTRBR(0, barTop, size.width, size.height, radius);
    canvas.drawRRect(track, Paint()..color = _track);

    final fillEnd = size.width * value;
    if (fillEnd > 0) {
      final fill = Rect.fromLTRB(0, barTop, fillEnd, size.height);
      canvas.save();
      canvas.clipRRect(track);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fill, radius),
        Paint()
          ..shader = LinearGradient(
            colors: [_fillStart, _fillEnd],
          ).createShader(fill),
      );
      canvas.restore();
    }

    // The sprout stands where the fill ends (kept on the bar at both ends),
    // growing from small to full size as the bar fills.
    final x = fillEnd.clamp(_barHeight, size.width - _barHeight);
    _drawSprout(canvas, Offset(x, barTop + 1), 0.55 + 0.45 * value);
  }

  void _drawSprout(Canvas canvas, Offset base, double scale) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.scale(scale);
    const stemTop = Offset(0, -_sproutHeight * 0.55);
    canvas.drawLine(
      Offset.zero,
      stemTop,
      Paint()
        ..color = _leafDark
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
    // Two leaves from the top of the stem, the right one a little larger.
    canvas.drawPath(
      _leafPath(stemTop, const Offset(-9, -_sproutHeight * 0.95), 5.4),
      Paint()..color = _leafDark,
    );
    canvas.drawPath(
      _leafPath(stemTop, const Offset(10, -_sproutHeight), 6.2),
      Paint()..color = _leaf,
    );
    canvas.restore();
  }

  // A leaf from [from] to its tip at [to], [width] across at the middle.
  Path _leafPath(Offset from, Offset to, double width) {
    final middle = Offset.lerp(from, to, 0.5)!;
    final along = to - from;
    final across = Offset(-along.dy, along.dx) / along.distance * width;
    return Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(
        middle.dx + across.dx,
        middle.dy + across.dy,
        to.dx,
        to.dy,
      )
      ..quadraticBezierTo(
        middle.dx - across.dx,
        middle.dy - across.dy,
        from.dx,
        from.dy,
      )
      ..close();
  }

  @override
  bool shouldRepaint(_BarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
