import 'package:flutter/material.dart';
import 'app_scaffold_messenger.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_language.dart';
import '../services/product_share_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Share AgriTrade+: the share sheet with the app's message and link, or
/// an error message when it cannot open. From the Farmer's Settings page
/// and the Buyer Profile.
Future<void> shareAgriTrade(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ProductShareService.shareApp(context);
  } catch (_) {
    messenger?.showSnackBar(
      appSnackBar(
        tl('Could not open sharing. Try again.'),
        kind: MessageKind.error,
      ),
    );
  }
}

/// Log Out: the app's secondary button (white, grey outline, dark text),
/// across the page. Not red (the user's choice, 2026-11-08): the red is kept
/// for the Log Out button in the confirmation that follows.
class LogOutButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// A thin dark green outline with a dark green icon and label (the
  /// Buyer Profile, 2026-11-08), in place of the grey outline and dark
  /// text the farmer's Settings keep.
  final bool brandOutline;

  const LogOutButton({
    super.key,
    required this.label,
    required this.onTap,
    this.brandOutline = false,
  });

  @override
  Widget build(BuildContext context) {
    final green = AppColors.isDark ? AppColors.brand : const Color(0xFF0B4225);
    final ink = brandOutline ? green : AppColors.text;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          side: BorderSide(
            color: brandOutline ? green : AppColors.grey(600),
            width: brandOutline ? 1.2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            // About 45 high, 13 text, an 18 icon (2026-11-08).
            padding: const EdgeInsets.symmetric(vertical: 12.5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout, size: 18, color: ink),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ink,
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
