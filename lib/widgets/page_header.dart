import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
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
/// bottom bar's (DockedNavBar) pure white with its soft shadow, the same as
/// AgriAppBar's on the inner screens. It holds the logo (on no background of
/// its own), the dark green "AgriTrade+" wordmark and dark green icons. The
/// title stays below it on
/// the page, in dark green. The band sits straight under the status bar,
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

  static const double _horizontalPadding = 16;

  /// The band's colour — the bottom bar's pure white.
  static Color get background => DockedNavBar.color;

  /// The colour of an icon on the band ([trailing] — the notification
  /// bell): dark green on the light band.
  static Color get onBandColor => AppColors.brand;

  /// The dark green of the title, and of an icon placed beside it
  /// ([titleTrailing] — the menus).
  static Color get titleColor => AppColors.brand;

  // The size the logo's artwork appears at, and the room it stands in.
  static const double _logoSize = 30;
  static const double _discSize = 34;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1, on the band: the logo and wordmark on the left, the
        // tab's action on the right. Fixed height, so the title under it
        // sits in the same place whether or not the tab has an action.
        // The shadow is kept to below the band: above, it would shade the
        // white status bar strip it joins.
        ClipRect(
          clipper: const _BelowOnly(),
          child: Container(
            width: double.infinity,
            height: 56,
            padding: const EdgeInsets.fromLTRB(_horizontalPadding, 0, 8, 4),
            // Rectangular: white with the bottom bar's soft shadow, and in
            // Dark Mode a line along its lower edge only.
            decoration: BoxDecoration(
              color: background,
              border: AppColors.cardBorder == null
                  ? null
                  : Border(bottom: AppColors.outlineSide),
              boxShadow: DockedNavBar.shadow,
            ),
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
                      const SizedBox(width: 9),
                      const AgriTradeText(fontSize: 17),
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
        // Row 2, on the page: the title, on the logo's left edge.
        if (includeTitle) PageTitle(title: title, trailing: titleTrailing),
      ],
    );
  }
}

// Clips to the band and everything below it (where its shadow falls), but
// nothing above.
class _BelowOnly extends CustomClipper<Rect> {
  const _BelowOnly();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-40, 0, size.width + 40, size.height + 40);

  @override
  bool shouldReclip(_BelowOnly oldClipper) => false;
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
      padding: const EdgeInsets.fromLTRB(
        PageHeader._horizontalPadding,
        12,
        8,
        4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Montserrat SemiBold in the brand's dark green.
              style: AppTheme.heading(22).copyWith(
                fontWeight: FontWeight.w600,
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
      size: 22,
    ),
  );
}

/// The role shells' replacement for a top [SafeArea]: the strip under the
/// phone's status bar is painted in [PageHeader.background], so it runs
/// on into each tab's header, and the status bar icons turn dark to stay
/// readable on it. [child] is laid out below the strip.
class PageHeaderSafeArea extends StatelessWidget {
  final Widget child;

  const PageHeaderSafeArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppColors.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
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
