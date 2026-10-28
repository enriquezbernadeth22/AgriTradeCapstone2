import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'agritrade_text.dart';
import 'walking_farmer_loader.dart';
import '../theme/app_colors.dart';

/// The very first thing Flutter draws after the native splash hands off,
/// on the phone and on the web alike. The circular logo stays exactly where
/// the native splash draws it (same background, same size, centred), so
/// the handoff is invisible; under it the AgriTrade+ name and tagline, then
/// the loading scene — the farmer walking over to the buyer while the bar
/// fills ([WalkingFarmerLoader]) — fade in, on a plain white page.
class BrandedLoadingScreen extends StatelessWidget {
  const BrandedLoadingScreen({super.key});

  static const double _logoSize = 120;

  // Between the logo and the name.
  static const double _gap = 18;

  // About how tall the name, tagline and loading scene are together.
  static const double _belowHeight = 236;

  /// The line under the name.
  static const String tagline = 'Smart Agricultural Trading, Made Simple.';

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
              const SizedBox(height: 6),
              Text(
                tagline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),
              WalkingFarmerLoader(
                width: math.min(300, constraints.maxWidth - 48),
              ),
            ],
          );
          // Room under the centred logo for the name, tagline and scene;
          // on a short screen (a phone on its side, a low window) all of
          // it is centred together instead, shrunk to fit if need be.
          final roomBelow =
              constraints.maxHeight / 2 - _logoSize / 2 - _gap - 16;
          return Stack(
            children: [
              if (roomBelow >= _belowHeight) ...[
                Center(child: logo),
                // Below the logo, without moving it.
                Positioned(
                  left: 24,
                  right: 24,
                  top: constraints.maxHeight / 2 + _logoSize / 2 + _gap,
                  child: _FadeIn(child: below),
                ),
              ] else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          logo,
                          const SizedBox(height: _gap),
                          _FadeIn(child: below),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Fades its child in just after the screen appears, so nothing pops in
/// at the moment the native splash hands over.
class _FadeIn extends StatefulWidget {
  final Widget child;
  const _FadeIn({required this.child});

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> {
  // Once per app run: the loading screen is shown more than once in a row
  // while starting up, and fading in again each time made it blink.
  static bool _fadedIn = false;
  bool _shown = _fadedIn;

  @override
  void initState() {
    super.initState();
    if (_shown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadedIn = true;
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _shown ? 1 : 0,
    duration: const Duration(milliseconds: 400),
    curve: Curves.easeOut,
    child: widget.child,
  );
}
