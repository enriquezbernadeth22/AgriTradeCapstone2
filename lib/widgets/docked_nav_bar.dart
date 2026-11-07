import 'package:flutter/material.dart';

/// The bottom navigation bar of the Farmer and Buyer home screens: a small,
/// solid dark green pill floating a little above the bottom edge, inset
/// from the sides, on a plain dark shadow, with a thin lighter green rim;
/// the selected tab sits on a gold pill in dark green, the others are white
/// (the user's picture, 2026-11-08; no gold glow). Like the floating Register button it has no
/// band behind it: the home screens set `extendBody`, so the page scrolls
/// on behind the pill (see [listEndPadding]). It sits above the phone's own
/// navigation (gesture bar or buttons), never under it. On the Farmer's
/// screens it always stays; on the Buyer's it slides away while a page is
/// scrolled down and comes back on a scroll up (BuyerMarketplaceScreen).
class DockedNavBar extends StatelessWidget {
  /// The bar's items, laid out in a [Row]; each is usually a [NavBarItem].
  final List<Widget> children;

  /// Height of the pill itself, as in the user's picture (2026-11-08; it
  /// was 48, made small twice by the user before then).
  static const double height = 54;

  /// The bar's dark green, in both modes (it reads on charcoal too), and
  /// the slightly lighter green at its top (a soft gradient).
  static const Color color = Color(0xFF063B1C);
  static const Color topColor = Color(0xFF0B4626);

  /// The gold of the selected tab's pill (and the farmer's +).
  static const Color selectedColor = Color(0xFFFDBE1D);

  /// The thin rim around the pill.
  static const Color rimColor = Color(0xFF15502C);

  /// The other tabs' icons and labels.
  static const Color unselectedColor = Colors.white;

  /// Fully round ends.
  static const double cornerRadius = height / 2;

  /// The headers' soft shadow (PageHeader, AgriAppBar).
  static final List<BoxShadow> shadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.10),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  // The pill's own shadow (a plain dark one, no gold).
  static final List<BoxShadow> _barShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.25),
      blurRadius: 18,
      offset: const Offset(0, 7),
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
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(21, 4, 21, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [topColor, color],
            ),
            borderRadius: _radius,
            border: Border.all(color: rimColor, width: 1.2),
            boxShadow: _barShadow,
          ),
          // For the items' ripples. Not clipped: the farmer's + button
          // rises above the pill.
          child: Material(
            type: MaterialType.transparency,
            borderRadius: _radius,
            clipBehavior: Clip.none,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: children),
              ),
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
    // Dark green on the gold pill; white on the bar.
    final color = selected ? DockedNavBar.color : DockedNavBar.unselectedColor;
    const iconSize = 19.0;
    final iconWidget = selected && activeIconBuilder != null
        ? activeIconBuilder!(color, iconSize)
        : Icon(selected ? activeIcon : icon, color: color, size: iconSize);
    return Expanded(
      child: Padding(
        // The gold pill: about 79 x 41 in the bar, as in the picture.
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6.5),
        child: AnimatedContainer(
          key: selected ? const Key('navSelectedPill') : null,
          // The full height of the bar, less its inset.
          height: double.infinity,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected
                ? DockedNavBar.selectedColor
                : DockedNavBar.selectedColor.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(DockedNavBar.cornerRadius),
          ),
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
                    fontFamily: 'Montserrat',
                    fontSize: 9.5,
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
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
    // Shown only on the selected tab: the lines are cut in its gold pill.
    painter: _FilledStorefrontPainter(color, DockedNavBar.selectedColor),
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
