import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'agritrade_text.dart';
import 'sprout_loading_bar.dart';
import '../theme/app_colors.dart';

/// The very first thing Flutter draws after the native splash hands off,
/// on the phone and on the web alike. The circular logo stays exactly where
/// the native splash draws it (same background, same size, centred), so
/// the handoff is invisible; under it the AgriTrade+ name, then
/// the loading bar with its sprout ([SproutLoadingBar]) — fade in, on a
/// plain white page.
class BrandedLoadingScreen extends StatelessWidget {
  const BrandedLoadingScreen({super.key});

  static const double _logoSize = 120;

  // Between the logo and the name.
  static const double _gap = 18;

  // How tall the name and loading bar are together (measured),
  // so the entrance can start with the logo exactly in the middle.
  static const double _belowHeight = 124;

  @override
  Widget build(BuildContext context) {
    final logo = ClipOval(
      child: Image.asset(
        'assets/images/logo.png',
        width: _logoSize,
        height: _logoSize,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: _logoSize,
          height: _logoSize,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.agriculture, size: 60, color: AppColors.brand),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.page,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final below = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AgriTradeText(fontSize: 26),
              const SizedBox(height: 28),
              SproutLoadingBar(width: math.min(260, constraints.maxWidth - 48)),
            ],
          );
          // The logo, name and scene together, balanced in the
          // middle of the page (shrunk to fit on a short screen). They
          // start with the logo alone in the very middle, where the
          // phone's native splash leaves it, then rise together into
          // place as the rest fades in — so the handoff does not jump.
          const group = _logoSize + _gap + _belowHeight;
          const lift = (_gap + _belowHeight) / 2 / group;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _Entrance(
                  builder: (shown) => AnimatedSlide(
                    offset: Offset(0, shown ? 0 : lift),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        logo,
                        const SizedBox(height: _gap),
                        AnimatedOpacity(
                          opacity: shown ? 1 : 0,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          child: below,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The screen's entrance, played just after it first appears: [builder] is
/// given false for the first frame (as the native splash hands over), then
/// true. Once per app run: the loading screen is shown more than once in a
/// row while starting up, and playing the entrance each time made it blink.
class _Entrance extends StatefulWidget {
  final Widget Function(bool shown) builder;
  const _Entrance({required this.builder});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> {
  static bool _played = false;
  bool _shown = _played;

  @override
  void initState() {
    super.initState();
    if (_shown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _played = true;
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(_shown);
}
