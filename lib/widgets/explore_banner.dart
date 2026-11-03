import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_language.dart';

/// The picture at the top of Explore: farmland, as on Log In, with "Fresh
/// from Laurel farms", so the first thing a buyer sees has the place and
/// the produce in it. Words only — no figures or listings — and it scrolls
/// away with the feed.
class ExploreBanner extends StatelessWidget {
  const ExploreBanner({super.key});

  static const String art = 'assets/images/login_landscape.png';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 112,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: Image.asset(
                art,
                fit: BoxFit.cover,
                alignment: const Alignment(0, 0.3),
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: Color(0xFF2E5E2F)),
              ),
            ),
            // Dark on the left, where the words are, so they always read.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xCC0E3210), Color(0x000E3210)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    tl('Fresh from Laurel farms'),
                    style: GoogleFonts.montserrat(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tl('Buy straight from the farmers who grow it.'),
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
