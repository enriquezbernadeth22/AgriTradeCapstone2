import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'docked_nav_bar.dart';

/// The cream page colour of the buyer's Explore (the user's design,
/// 2026-11-08) — since then every page's ([AppColors.page]).
Color get exploreBackground => AppColors.page;

/// The top of the buyer's Explore (the user's design, 2026-11-08): the
/// title, one line on what the page is, a gold underline, and a
/// drawn farm scene (hills, fields, a house and trees) on the right, on the
/// page's cream. Drawn, not a picture file, so it stays sharp and costs
/// nothing to load.
class ExploreHero extends StatelessWidget {
  final String title;
  final String subtitle;

  const ExploreHero({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The farm scene, fading in from the left behind the words; its
        // foot runs on behind the search bar under it, as in the user's
        // picture.
        Positioned(
          right: 0,
          bottom: -22,
          width: 232,
          height: 114,
          child: ExcludeSemantics(
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                colors: [Colors.transparent, Colors.black],
                stops: [0, 0.4],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: Opacity(
                opacity: dark ? 0.5 : 1,
                child: const CustomPaint(painter: FarmScenePainter()),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 6, 16, 10.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The title alone (its leaf removed by the user, 2026-11-08).
              Text(
                title,
                style: TextStyle(
                  // The bundled Montserrat, so the ExtraBold file is used
                  // (the theme's own family has only its regular one).
                  fontFamily: 'Montserrat',
                  fontSize: 23.5,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(height: 2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: AppColors.grey(800),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Container(
                width: 56,
                height: 3,
                decoration: BoxDecoration(
                  color: DockedNavBar.selectedColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A small farm, as in the user's picture: pale misty hills far off, a
/// rolling green hill with small round trees, a cream farmhouse with a
/// red-brown roof, a big round tree on the right, and a bright field with
/// rows of crops sweeping in front, filling its box from the bottom.
class FarmScenePainter extends CustomPainter {
  const FarmScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Paint fill(int color) => Paint()..color = Color(color);
    Paint shade(int top, int bottom, double y0, double y1) =>
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(top), Color(bottom)],
          ).createShader(Rect.fromLTRB(0, y0, w, y1));

    // A round tree: trunk, a canopy of overlapping circles, a highlight.
    void tree(double x, double baseY, double r, {bool big = false}) {
      final leaf = big ? 0xFF3C8C2E : 0xFF4E9E38;
      final dark = big ? 0xFF2F7425 : 0xFF3F8A2E;
      final light = big ? 0xFF6BB247 : 0xFF77BC55;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - r * 0.11, baseY - r * 1.0, r * 0.22, r * 1.0),
          Radius.circular(r * 0.05),
        ),
        fill(0xFF7A5234),
      );
      canvas.drawCircle(
        Offset(x + r * 0.15, baseY - r * 1.25),
        r * 0.75,
        fill(dark),
      );
      canvas.drawCircle(
        Offset(x - r * 0.55, baseY - r * 1.25),
        r * 0.62,
        fill(leaf),
      );
      canvas.drawCircle(
        Offset(x + r * 0.6, baseY - r * 1.35),
        r * 0.6,
        fill(leaf),
      );
      canvas.drawCircle(Offset(x, baseY - r * 1.75), r * 0.82, fill(leaf));
      canvas.drawCircle(
        Offset(x - r * 0.3, baseY - r * 2.05),
        r * 0.42,
        fill(light),
      );
      canvas.drawCircle(
        Offset(x + r * 0.35, baseY - r * 1.95),
        r * 0.3,
        fill(light),
      );
    }

    // Far hills, misty.
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.42)
        ..quadraticBezierTo(w * 0.18, h * 0.18, w * 0.40, h * 0.30)
        ..quadraticBezierTo(w * 0.62, h * 0.10, w * 0.82, h * 0.22)
        ..quadraticBezierTo(w * 0.93, h * 0.28, w, h * 0.20)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      shade(0xFFDDE9CF, 0xFFE9F1DD, h * 0.1, h * 0.6),
    );
    // A middle hill.
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.58)
        ..quadraticBezierTo(w * 0.25, h * 0.38, w * 0.52, h * 0.46)
        ..quadraticBezierTo(w * 0.78, h * 0.52, w, h * 0.36)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      shade(0xFFB5DA8C, 0xFF9CCB6E, h * 0.36, h * 0.8),
    );
    // Small trees along it.
    tree(w * 0.13, h * 0.56, h * 0.07);
    tree(w * 0.24, h * 0.50, h * 0.085);
    tree(w * 0.70, h * 0.50, h * 0.07);

    // The farmhouse.
    final hx = w * 0.36;
    final hy = h * 0.60;
    final bw = w * 0.20;
    final bh = h * 0.15;
    canvas.drawRect(
      Rect.fromLTWH(hx + bw * 0.72, hy - bh - h * 0.13, bw * 0.09, h * 0.08),
      fill(0xFF8E4B34),
    );
    canvas.drawRect(Rect.fromLTWH(hx, hy - bh, bw, bh), fill(0xFFFFF4E0));
    canvas.drawRect(
      Rect.fromLTWH(hx, hy - bh * 0.18, bw, bh * 0.18),
      fill(0xFFE9DCC4),
    );
    canvas.drawPath(
      Path()
        ..moveTo(hx - bw * 0.10, hy - bh)
        ..lineTo(hx + bw * 0.5, hy - bh - h * 0.15)
        ..lineTo(hx + bw * 1.10, hy - bh)
        ..close(),
      fill(0xFFB5482F),
    );
    canvas.drawPath(
      Path()
        ..moveTo(hx + bw * 0.5, hy - bh - h * 0.15)
        ..lineTo(hx + bw * 1.10, hy - bh)
        ..lineTo(hx + bw * 0.80, hy - bh)
        ..close(),
      fill(0xFF94381F),
    );
    canvas.drawRect(
      Rect.fromLTWH(hx + bw * 0.42, hy - bh * 0.66, bw * 0.17, bh * 0.66),
      fill(0xFF7A4B30),
    );
    for (final dx in [0.10, 0.73]) {
      canvas.drawRect(
        Rect.fromLTWH(hx + bw * dx, hy - bh * 0.76, bw * 0.17, bh * 0.30),
        fill(0xFF5B8A49),
      );
    }

    // The field in front: bright, with rows of crops sweeping towards the
    // house.
    final field = Path()
      ..moveTo(0, h * 0.92)
      ..quadraticBezierTo(w * 0.30, h * 0.58, w * 0.62, h * 0.60)
      ..quadraticBezierTo(w * 0.86, h * 0.62, w, h * 0.54)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(field, shade(0xFF95CB5A, 0xFF6FAE3C, h * 0.55, h));
    canvas.save();
    canvas.clipPath(field);
    final row = Paint()
      ..color = const Color(0xFF5E9E33).withValues(alpha: 0.75)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = -3; i < 16; i++) {
      final x = w * 0.08 * i;
      canvas.drawPath(
        Path()
          ..moveTo(x, h * 1.02)
          ..quadraticBezierTo(
            x + w * 0.10,
            h * 0.78,
            w * 0.60 + i * 2.5,
            h * 0.60,
          ),
        row,
      );
    }
    canvas.restore();

    // The big tree on the right.
    tree(w * 0.86, h * 0.64, h * 0.21, big: true);
  }

  @override
  bool shouldRepaint(FarmScenePainter oldDelegate) => false;
}
