import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The bottom navigation bar of the Farmer and Buyer home screens: a small,
/// solid white pill floating a little above the bottom edge, inset from
/// the sides, on a soft shadow. Like the floating Register button it has no
/// band behind it: the home screens set `extendBody`, so the page scrolls
/// on behind the pill (see [listEndPadding]). It sits above the phone's own
/// navigation (gesture bar or buttons), never under it, and it stays on
/// screen — it does not hide while a page is scrolled.
class DockedNavBar extends StatelessWidget {
  /// The bar's items, laid out in a [Row]; each is usually a [NavBarItem].
  final List<Widget> children;

  /// Height of the pill itself.
  static const double height = 54;

  /// The bar's look — pure white, these corners, this shadow — which the
  /// tabs' header band (PageHeader) shares.
  static Color get color => AppColors.surface;
  static const double cornerRadius = 27;
  static final List<BoxShadow> shadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.10),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(cornerRadius),
  );

  /// The room a list in a home tab leaves at its end, so its last row can
  /// scroll clear of the pill. A Scaffold with `extendBody` reports the
  /// whole bar as bottom padding, which also covers the taller bar on phones
  /// with three-button navigation.
  static double listEndPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + 12;

  const DockedNavBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: _radius,
            border: AppColors.cardBorder,
            boxShadow: shadow,
          ),
          // For the items' ripples. Not clipped: the farmer's + button
          // rises above the pill.
          child: Material(
            type: MaterialType.transparency,
            borderRadius: _radius,
            clipBehavior: Clip.none,
            child: SizedBox(
              height: height,
              child: Row(children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tab in [DockedNavBar] — the same small icon and label for the Farmer
/// and the Buyer. [decorateIcon] puts a badge on the icon (the red dot
/// for unread messages or new orders).
class NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget Function(Widget icon)? decorateIcon;

  /// Draws the selected icon, for a tab whose [activeIcon] has no filled
  /// version in the icon font.
  final Widget Function(Color color, double size)? activeIconBuilder;

  const NavBarItem({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.decorateIcon,
    this.activeIconBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppColors.brand
        : (AppColors.isDark
              ? AppColors.grey(500)
              : AppColors.adapt(const Color(0xFFAAB4AC)));
    const iconSize = 19.0;
    final iconWidget = selected && activeIconBuilder != null
        ? activeIconBuilder!(color, iconSize)
        : Icon(selected ? activeIcon : icon, color: color, size: iconSize);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            decorateIcon?.call(iconWidget) ?? iconWidget,
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The familiar shop of Icons.storefront_outlined, filled in. The icon font
/// has no filled version of it: Icons.storefront is an outline too.
class FilledStorefrontIcon extends StatelessWidget {
  final Color color;
  final double size;

  const FilledStorefrontIcon({
    super.key,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _FilledStorefrontPainter(color, DockedNavBar.color),
  );
}

class _FilledStorefrontPainter extends CustomPainter {
  final Color color;

  /// The bar behind the icon: the awning's lines are cut out in it.
  final Color background;

  const _FilledStorefrontPainter(this.color, this.background);

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on the 24-unit grid of the icon font.
    canvas.scale(size.width / 24);
    final shop = Path()
      ..moveTo(21.9, 8.89)
      ..relativeLineTo(-1.05, -4.37)
      ..relativeCubicTo(-.22, -.9, -1, -1.52, -1.91, -1.52)
      ..lineTo(5.05, 3)
      ..relativeCubicTo(-.9, 0, -1.69, .63, -1.9, 1.52)
      ..lineTo(2.1, 8.89)
      ..relativeCubicTo(-.24, 1.02, -.02, 2.06, .62, 2.88)
      ..relativeCubicTo(.08, .11, .19, .19, .28, .29)
      ..lineTo(3, 19)
      ..relativeCubicTo(0, 1.1, .9, 2, 2, 2)
      ..relativeLineTo(14, 0)
      ..relativeCubicTo(1.1, 0, 2, -.9, 2, -2)
      ..relativeLineTo(0, -6.94)
      ..relativeCubicTo(.09, -.09, .2, -.18, .28, -.28)
      ..relativeCubicTo(.64, -.82, .87, -1.87, .62, -2.89)
      ..close();
    canvas.drawPath(shop, Paint()..color = color);

    final line = Paint()
      ..color = background
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // The awning's scalloped edge, then its stripes.
    const left = 3.1;
    const scallop = 4.45;
    const edgeY = 10.5;
    final edge = Path()..moveTo(left, edgeY);
    for (var i = 0; i < 4; i++) {
      edge.quadraticBezierTo(
        left + scallop * (i + .5),
        15.1,
        left + scallop * (i + 1),
        edgeY,
      );
    }
    canvas.drawPath(edge, line);
    for (final (top, bottom) in const [
      (8.6, 7.55),
      (12.0, 12.0),
      (15.4, 16.45),
    ]) {
      canvas.drawLine(Offset(top, 3.9), Offset(bottom, edgeY), line);
    }
  }

  @override
  bool shouldRepaint(_FilledStorefrontPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.background != background;
}
