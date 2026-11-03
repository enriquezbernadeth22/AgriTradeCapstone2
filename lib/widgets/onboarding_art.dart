import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// The same as the welcome picture's background, so no edge of it shows.
const Color _cream = Color(0xFFFDFCF8);
const Color _barCream = Color(0xFFFCFAEF);

/// The onboarding's page colour, with soft hills in the distance.
class OnboardingBackdrop extends StatelessWidget {
  const OnboardingBackdrop({super.key});

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _BackdropPainter(), child: SizedBox.expand());
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = _cream);

    Path hill(double left, double middle, double right) => Path()
      ..moveTo(0, h * left)
      ..cubicTo(
        w * 0.3,
        h * (left - 0.05),
        w * 0.45,
        h * middle,
        w * 0.68,
        h * middle,
      )
      ..cubicTo(w * 0.82, h * middle, w * 0.9, h * right, w, h * (right - 0.02))
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      hill(0.72, 0.76, 0.7),
      Paint()..color = const Color(0xFFF6FAEC),
    );
    canvas.drawPath(
      hill(0.8, 0.8, 0.77),
      Paint()..color = const Color(0xFFEEF6DF),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) => false;
}

/// The green hill in front of the page, and the cream bar it ends at: whatever
/// stands on the page stands behind them. [barTop] is where the bar starts.
class OnboardingFrontHill extends StatelessWidget {
  final double barTop;

  const OnboardingFrontHill({super.key, required this.barTop});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _FrontHillPainter(barTop),
    child: const SizedBox.expand(),
  );
}

class _FrontHillPainter extends CustomPainter {
  final double barTop;

  const _FrontHillPainter(this.barTop);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(0, barTop - 26)
        ..cubicTo(
          w * 0.22,
          barTop - 34,
          w * 0.42,
          barTop + 2,
          w * 0.62,
          barTop - 4,
        )
        ..cubicTo(w * 0.78, barTop - 10, w * 0.9, barTop - 40, w, barTop - 44)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = const Color(0xFFDDF0B8),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, barTop - 8)
        ..cubicTo(w * 0.3, barTop - 22, w * 0.5, barTop + 8, w * 0.72, barTop)
        ..cubicTo(w * 0.86, barTop - 6, w * 0.94, barTop - 16, w, barTop - 20)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = const Color(0xFFC6E78A),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, barTop + 12)
        ..quadraticBezierTo(w * 0.5, barTop - 10, w, barTop + 12)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = _barCream,
    );
  }

  @override
  bool shouldRepaint(_FrontHillPainter oldDelegate) =>
      oldDelegate.barTop != barTop;
}

/// The dark green stroke under a title, swelling from left to right.
class OnboardingSwoosh extends StatelessWidget {
  final double width;

  const OnboardingSwoosh({super.key, required this.width});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, width * 0.07),
    painter: const _SwooshPainter(),
  );
}

class _SwooshPainter extends CustomPainter {
  const _SwooshPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(0, h)
        ..quadraticBezierTo(w * 0.45, h * 0.02, w * 0.97, h * 0.18)
        ..quadraticBezierTo(w * 1.03, h * 0.5, w * 0.95, h * 0.78)
        ..quadraticBezierTo(w * 0.45, h * 0.42, 0, h)
        ..close(),
      Paint()..color = AppTheme.dark,
    );
  }

  @override
  bool shouldRepaint(_SwooshPainter oldDelegate) => false;
}

/// Three short strokes fanning out from a corner, for a bit of life.
class OnboardingSparks extends StatelessWidget {
  final double size;
  final Color color;

  /// Which way they fan: to the upper right, or else to the upper left.
  final bool toRight;

  const OnboardingSparks({
    super.key,
    required this.size,
    required this.color,
    this.toRight = true,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _SparksPainter(color, toRight),
  );
}

class _SparksPainter extends CustomPainter {
  final Color color;
  final bool toRight;

  const _SparksPainter(this.color, this.toRight);

  @override
  void paint(Canvas canvas, Size size) {
    if (!toRight) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final s = size.width;
    final line = Paint()
      ..color = color
      ..strokeWidth = s * 0.13
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(s * 0.12, s * 0.55),
      Offset(s * 0.22, s * 0.1),
      line,
    );
    canvas.drawLine(
      Offset(s * 0.42, s * 0.68),
      Offset(s * 0.72, s * 0.34),
      line,
    );
    canvas.drawLine(
      Offset(s * 0.56, s * 0.92),
      Offset(s * 0.98, s * 0.74),
      line,
    );
  }

  @override
  bool shouldRepaint(_SparksPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.toRight != toRight;
}

/// The dashed arrow curving from an order down to its receipt.
class OnboardingDashedArrow extends StatelessWidget {
  final Size size;

  const OnboardingDashedArrow({super.key, required this.size});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: size, painter: const _DashedArrowPainter());
}

class _DashedArrowPainter extends CustomPainter {
  const _DashedArrowPainter();

  static const Color _green = AppTheme.dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final curve = Path()
      ..moveTo(w * 0.06, 0)
      ..quadraticBezierTo(w * 0.06, h * 0.82, w * 0.86, h * 0.8);
    final dash = Paint()
      ..color = _green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (final metric in curve.computeMetrics()) {
      for (double at = 0; at < metric.length; at += 10) {
        canvas.drawPath(metric.extractPath(at, at + 5.5), dash);
      }
    }
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.72, h * 0.6)
        ..lineTo(w, h * 0.8)
        ..lineTo(w * 0.72, h),
      dash,
    );
  }

  @override
  bool shouldRepaint(_DashedArrowPainter oldDelegate) => false;
}
