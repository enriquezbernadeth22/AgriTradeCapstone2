import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Opens [page] by growing it out of the card the user tapped (a container
/// transform; the user's design, 2026-11-08): the page starts at the card's
/// size and place — its photo at the top standing where the card's photo
/// was — and widens to fill the screen while the page behind dims a little;
/// Back shrinks it into the card again. No sideways slide.
///
/// [cardContext] is the context of the tapped card; without a laid-out card
/// it falls back to an ordinary page.
Future<T?> openFromCard<T>(BuildContext cardContext, Widget page) {
  final box = cardContext.findRenderObject();
  final navigator = Navigator.of(cardContext);
  final overlay = navigator.overlay?.context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || overlay is! RenderBox) {
    return navigator.push(MaterialPageRoute<T>(builder: (_) => page));
  }
  final origin = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  return navigator.push(CardZoomRoute<T>(origin: origin, page: page));
}

/// The route of [openFromCard].
class CardZoomRoute<T> extends PageRouteBuilder<T> {
  /// Where the card was, in the navigator's overlay.
  final Rect origin;

  /// The card's corners, opening out to the screen's square ones.
  final double radius;

  CardZoomRoute({required this.origin, required Widget page, this.radius = 14})
    : super(
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (context, animation, _, child) => _CardZoom(
          animation: animation,
          origin: origin,
          radius: radius,
          child: child,
        ),
      );
}

class _CardZoom extends StatelessWidget {
  final Animation<double> animation;
  final Rect origin;
  final double radius;
  final Widget child;

  const _CardZoom({
    required this.animation,
    required this.origin,
    required this.radius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = Offset.zero & constraints.biggest;
        return AnimatedBuilder(
          animation: curved,
          child: child,
          builder: (context, page) {
            // The same widgets throughout (only their sizes change), so
            // the page keeps its state when the animation ends.
            final t = curved.value;
            final rect = Rect.lerp(origin, screen, t)!;
            return Stack(
              children: [
                // The page behind recedes a little.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.18 * t),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      lerpDouble(radius, 0, t)!,
                    ),
                    child: ColoredBox(
                      color: AppColors.surface,
                      // The page at full size, scaled to the growing box's
                      // width from its top: its photo stands where the
                      // card's photo was, and grows with it.
                      child: FittedBox(
                        fit: BoxFit.fitWidth,
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox.fromSize(
                          size: constraints.biggest,
                          // Fully there within the first quarter, so the
                          // card does not flash white as it opens.
                          child: Opacity(
                            opacity: (t * 4).clamp(0.0, 1.0),
                            child: page,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
