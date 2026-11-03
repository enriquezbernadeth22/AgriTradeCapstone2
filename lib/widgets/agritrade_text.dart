import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

import '../theme/app_theme.dart';

// Reusable "AgriTrade+" wordmark, in one colour: the whole word is the
// brand's dark green (see AppTheme.brandText — the one shared style for
// it). Pass light: true for the version sitting on a dark background
// (e.g. the login hero), where it is white instead.
class AgriTradeText extends StatelessWidget {
  final double fontSize;
  final bool light;
  const AgriTradeText({super.key, this.fontSize = 28, this.light = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      'AgriTrade+',
      style: AppTheme.brandText(fontSize: fontSize, light: light),
    );
  }
}

/// The AgriTrade+ logo with no background of its own, its artwork [size] wide.
class AgriTradeLogoMark extends StatelessWidget {
  final double size;

  const AgriTradeLogoMark({super.key, required this.size});

  // logo.png is 612x408 with the artwork taking only the middle 330x310 of
  // it — the rest is transparent margin — so fitting the whole file into a
  // small square would leave the mark looking tiny. The file is drawn larger
  // instead, sized so the artwork itself comes out [size] wide, with the
  // transparent margin allowed to spill past the layout box (it draws
  // nothing).
  static const double _assetWidth = 612;
  static const double _assetHeight = 408;
  static const double _artworkWidth = 330;

  @override
  Widget build(BuildContext context) {
    final scale = size / _artworkWidth;
    return SizedBox(
      width: size,
      height: size,
      child: OverflowBox(
        maxWidth: _assetWidth * scale,
        maxHeight: _assetHeight * scale,
        child: Image.asset(
          'assets/images/logo.png',
          width: _assetWidth * scale,
          height: _assetHeight * scale,
          fit: BoxFit.contain,
          // Smooth, sharp scaling of the large artwork down to header size.
          filterQuality: FilterQuality.high,
          errorBuilder: (c, e, s) => Icon(
            Icons.agriculture,
            color: AppColors.brand,
            size: size * 0.66,
          ),
        ),
      ),
    );
  }
}

/// The small logo and name in the header of an account screen (Choose Role,
/// registration, the Google profile form, Forgot Password), next to Back:
/// quieter than the page's own title, and the only logo on the page.
class AgriTradeHeaderBrand extends StatelessWidget {
  const AgriTradeHeaderBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AgriTradeLogoMark(size: 28),
        SizedBox(width: 8),
        AgriTradeText(fontSize: 18),
      ],
    );
  }
}
