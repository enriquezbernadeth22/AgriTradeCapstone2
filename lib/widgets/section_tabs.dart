import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../theme/app_colors.dart';
import 'docked_nav_bar.dart';

/// The bar of a long page's sections (Product Details: Overview,
/// Description, Reviews, Recommended), in the user's design of 2026-11-08:
/// dark green names, the [active] one on a dark green pill in white with a
/// short gold line under it; a tap on one goes to it ([onTap]). The tabs
/// share the width by the length of their names and are always one size:
/// 11.5 when they fit, a little smaller together on a narrow phone.
///
/// With [onBack] it is the bar that comes down at the top of the page once
/// the page's own row of tabs has scrolled away (Back on the left, on the
/// page's cream, under the status bar); without it, that row itself.
class SectionTabs extends StatelessWidget {
  final List<String> labels;
  final int active;
  final ValueChanged<int> onTap;
  final VoidCallback? onBack;

  /// The start of each tab's key ('sectionTab' gives sectionTab0…), so the
  /// page's row and the bar at the top can both be found.
  final String keyPrefix;

  const SectionTabs({
    super.key,
    required this.labels,
    required this.active,
    required this.onTap,
    this.onBack,
    this.keyPrefix = 'sectionTab',
  });

  /// The bar's height (under the status bar, for the one at the top).
  static const double height = 40;
  static const double fontSize = 11.5;
  static const double _minFontSize = 10;
  // Room each tab keeps around its name (the pill's sides).
  static const double _tabPadding = 22;
  static const double _backWidth = 44;

  /// The page colour behind the bar at the top.
  static Color get background => AppColors.page;

  static TextStyle textStyle({required bool active, double size = fontSize}) =>
      TextStyle(
        fontFamily: 'Montserrat',
        fontSize: size,
        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
        letterSpacing: 0,
        color: active ? Colors.white : AppColors.brand,
      );

  static double _widthOf(BuildContext context, String text) {
    // Measured semibold, the widest it is drawn.
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle(active: true)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: height,
      child: Row(
        children: [
          if (onBack != null)
            SizedBox(
              width: _backWidth,
              child: IconButton(
                key: const Key('sectionTabsBack'),
                tooltip: tl('Back'),
                onPressed: onBack,
                icon: Icon(Icons.arrow_back_rounded, color: AppColors.brand),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final widths = [
                  for (final label in labels) _widthOf(context, label),
                ];
                final text = widths.fold<double>(0, (t, w) => t + w);
                final room = constraints.maxWidth - _tabPadding * labels.length;
                final size = text <= room
                    ? fontSize
                    : (fontSize * room / text).clamp(_minFontSize, fontSize);
                return Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Expanded(
                        flex: ((widths[i] * size / fontSize + _tabPadding) * 10)
                            .round()
                            .clamp(1, 1 << 20),
                        child: _tab(i, size),
                      ),
                  ],
                );
              },
            ),
          ),
          if (onBack != null) const SizedBox(width: 8),
        ],
      ),
    );
    final lined = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: row,
    );
    if (onBack == null) return lined;
    return Material(
      color: background,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: SafeArea(bottom: false, child: lined),
    );
  }

  Widget _tab(int i, double size) {
    final isActive = i == active;
    return Semantics(
      button: true,
      selected: isActive,
      child: InkWell(
        key: Key('$keyPrefix$i'),
        onTap: () => onTap(i),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive
                    ? (AppColors.isDark
                          ? AppColors.brandFill
                          : const Color(0xFF0B4225))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                labels[i],
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: textStyle(active: isActive, size: size),
              ),
            ),
            const SizedBox(height: 3),
            // The short gold line under the chosen one.
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 2.5,
              width: isActive ? 30 : 0,
              decoration: BoxDecoration(
                color: DockedNavBar.selectedColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
