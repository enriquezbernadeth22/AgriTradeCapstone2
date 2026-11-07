import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'agritrade_text.dart';
import 'docked_nav_bar.dart';
import 'notification_bell.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

/// The header of every main tab, for both roles — Market / Explore,
/// Messages, Orders, Profile — in two rows: the AgriTrade+ logo mark on
/// the left and the notification bell and Settings gear on the right, then
/// the tab's title underneath. One widget, so the tabs cannot drift apart
/// in height, padding, logo size, font or colour.
///
/// Only the logo row is on a band: a rectangular bar across the top, in the
/// bottom bar's dark green (DockedNavBar) with a soft shadow (the user's
/// design, 2026-11-08, for both roles; the inner screens' AgriAppBar stays
/// white). It holds the logo on a white disc, the "AgriTrade" wordmark in
/// white with a gold "+", and white icons; the bell's unread mark is a gold
/// dot. The title stays below it on the page, in dark green. The band sits straight under the status bar,
/// which [PageHeaderSafeArea] paints the same colour: the role shells have
/// no app bar.
class PageHeader extends StatelessWidget {
  final String title;

  /// Optional action on the logo row, in place of the shell's notification
  /// bell. The Settings gear stays at the right end either way.
  final Widget? trailing;

  /// Optional action on the title's own row, right-aligned and centered
  /// on the title (the farmer's Inventory button on Orders).
  final Widget? titleTrailing;

  /// False leaves the title row out: a tab whose title scrolls with its
  /// content puts a [PageTitle] at the top of its scrolling page instead,
  /// under this fixed band (Market, Profile).
  final bool includeTitle;

  const PageHeader({
    super.key,
    required this.title,
    this.trailing,
    this.titleTrailing,
    this.includeTitle = true,
  });

  static const double _horizontalPadding = 22;

  /// The band's colour (and the status bar strip's): the deep green of the
  /// user's picture, 2026-11-08.
  static const Color background = Color(0xFF043C1E);

  /// The colour of an icon on the band ([trailing] — the notification
  /// bell): white on the dark green.
  static Color get onBandColor => Colors.white;

  /// The gold of the "+" and the bell's unread dot.
  static const Color accent = DockedNavBar.selectedColor;

  /// The dark green of the title, and of an icon placed beside it
  /// ([titleTrailing] — the menus).
  static Color get titleColor => AppColors.brand;

  // The size the logo's artwork appears at, and the room it stands in.
  static const double _logoSize = 32;
  static const double _discSize = 32;

  /// The band's row (as low as the user's picture; the bell keeps its full
  /// 48 tap area, reaching a little past it), and how far its wavy lower
  /// edge, with the gold stripe under it, reaches below that.
  static const double bandHeight = 40;
  static const double waveDepth = 18;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1, on the band: the logo and wordmark on the left, the
        // tab's action on the right. Fixed height, so the title under it
        // sits in the same place whether or not the tab has an action.
        // The band's lower edge is a gentle curve with a gold stripe under
        // it, thickening to the right (the user's design, 2026-11-08).
        CustomPaint(
          key: const Key('pageHeaderBand'),
          painter: HeaderWavePainter(green: background, gold: accent),
          child: Container(
            width: double.infinity,
            height: bandHeight + waveDepth,
            padding: const EdgeInsets.fromLTRB(
              _horizontalPadding,
              0,
              9,
              waveDepth,
            ),
            child: OverflowBox(
              minHeight: 48,
              maxHeight: 48,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // The logo itself, straight on the band. Logo and wordmark
                  // together go home (see HomeLogoAction).
                  _HomeLogoTap(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: Container(
                            width: _discSize,
                            height: _discSize,
                            alignment: Alignment.center,
                            child: const AgriTradeLogoMark(size: _logoSize),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const AgriTradeText(
                          fontSize: 17.5,
                          light: true,
                          plusColor: accent,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // The tab's own action, or else the notification bell the
                  // role shell provides (see HomeLogoAction), so every tab has
                  // the bell; then the shell's Settings gear.
                  ?(trailing ?? _shellBell(context)),
                  ?_shellGear(context),
                ],
              ),
            ),
          ),
        ),
        // Row 2, on the page: the title, on the logo's left edge.
        if (includeTitle) PageTitle(title: title, trailing: titleTrailing),
      ],
    );
  }
}

/// The tabs' header band (the user's picture, 2026-11-08): dark [green]
/// whose lower edge waves — down near the left, up at about a third, down
/// again at three quarters, up at the right edge — over a [gold] stripe
/// under the right-hand wave, thickest where it dips, on a soft shadow.
class HeaderWavePainter extends CustomPainter {
  final Color green;
  final Color gold;

  const HeaderWavePainter({required this.green, required this.gold});

  // (fraction of the width, depth below the row), measured from the
  // picture.
  static const List<(double, double)> greenEdge = [
    (0, 8),
    (0.09, 10),
    (0.22, 4.5),
    (0.35, 0.5),
    (0.47, 2),
    (0.60, 7.5),
    (0.73, 10),
    (0.86, 7),
    (1, 0),
  ];
  static const List<(double, double)> goldEdge = [
    (0, 8),
    (0.09, 10),
    (0.22, 4.5),
    (0.35, 0.8),
    (0.47, 5.5),
    (0.60, 15),
    (0.73, 17),
    (0.86, 11.5),
    (1, 0.8),
  ];

  // A smooth curve through [edge] (Catmull-Rom as cubic Béziers), closed
  // over the top of the box.
  static Path _shape(Size size, double band, List<(double, double)> edge) {
    final pts = [for (final (x, d) in edge) Offset(x * size.width, band + d)];
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(pts.last.dx, pts.last.dy);
    for (var i = pts.length - 1; i > 0; i--) {
      final p0 = pts[i == pts.length - 1 ? i : i + 1];
      final p1 = pts[i];
      final p2 = pts[i - 1];
      final p3 = pts[i - 1 == 0 ? 0 : i - 2];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    const band = PageHeader.bandHeight;
    final goldPath = _shape(size, band, goldEdge);
    final greenPath = _shape(size, band, greenEdge);
    canvas.drawShadow(goldPath, Colors.black, 4, false);
    canvas.drawPath(goldPath, Paint()..color = gold);
    canvas.drawPath(greenPath, Paint()..color = green);
  }

  @override
  bool shouldRepaint(HeaderWavePainter old) =>
      old.green != green || old.gold != gold;
}

/// Where the header's logo goes when tapped: the role's home tab — Market
/// for a farmer, Explore for a buyer. Each role shell puts one above its
/// tabs; without one the logo is not tappable.
class HomeLogoAction extends InheritedWidget {
  final VoidCallback onTap;

  /// Opens Notifications — the bell every tab's header shows when the tab
  /// has no action of its own there.
  final VoidCallback? onNotifications;

  /// Opens the Settings sheet — the gear in every tab's header.
  final VoidCallback? onSettings;

  const HomeLogoAction({
    super.key,
    required this.onTap,
    this.onNotifications,
    this.onSettings,
    required super.child,
  });

  // Read when used, so a new callback on every rebuild of the shell never
  // rebuilds the tabs under it.
  static VoidCallback? _of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeLogoAction>()?.onTap;

  static VoidCallback? _notificationsOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeLogoAction>()?.onNotifications;

  static VoidCallback? _settingsOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeLogoAction>()?.onSettings;

  @override
  bool updateShouldNotify(HomeLogoAction oldWidget) => false;
}

class _HomeLogoTap extends StatelessWidget {
  final Widget child;
  const _HomeLogoTap({required this.child});

  @override
  Widget build(BuildContext context) {
    if (HomeLogoAction._of(context) == null) return child;
    return Semantics(
      button: true,
      label: tl('AgriTrade+ home'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => HomeLogoAction._of(context)?.call(),
        child: child,
      ),
    );
  }
}

/// A main tab's title row — "Market", "Profile" — in the brand's dark
/// green, with an optional action at its right end. Part of [PageHeader];
/// on its own at the top of a tab's scrolling page, it scrolls away with
/// the content while the band above stays.
class PageTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const PageTitle({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(21, 8, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // As big as Explore's title, for every tab of both roles
              // (2026-11-08): extra bold Montserrat in dark green.
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 23.5,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: PageHeader.titleColor,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// The shell's notification bell for a tab header, or null without one.
Widget? _shellBell(BuildContext context) {
  if (HomeLogoAction._notificationsOf(context) == null) return null;
  return NotificationBell(
    onPressed: () => HomeLogoAction._notificationsOf(context)?.call(),
    color: PageHeader.onBandColor,
  );
}

// The shell's Settings gear for a tab header, or null without one.
Widget? _shellGear(BuildContext context) {
  if (HomeLogoAction._settingsOf(context) == null) return null;
  return IconButton(
    tooltip: tl('Settings'),
    onPressed: () => HomeLogoAction._settingsOf(context)?.call(),
    icon: Icon(
      Icons.settings_outlined,
      color: PageHeader.onBandColor,
      size: 24,
    ),
  );
}

/// The role shells' replacement for a top [SafeArea]: the strip under the
/// phone's status bar is painted in [PageHeader.background], so it runs
/// on into each tab's header, and the status bar icons turn light to stay
/// readable on it. [child] is laid out below the strip.
class PageHeaderSafeArea extends StatelessWidget {
  final Widget child;

  const PageHeaderSafeArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Column(
        children: [
          Container(
            height: MediaQuery.paddingOf(context).top,
            color: PageHeader.background,
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
