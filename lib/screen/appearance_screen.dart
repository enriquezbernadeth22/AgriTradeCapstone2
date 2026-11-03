import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_language.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/agri_app_bar.dart';

/// Appearance, from the Buyer Profile: the Dark Mode switch, the same one
/// as in the farmer's Settings sheet (ThemeController, kept on this phone).
/// The app is English only, so there is no language here.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Redrawn when the switch flips, like every screen (ThemeController).
    return ValueListenableBuilder<AppearanceMode>(
      valueListenable: ThemeController.instance,
      builder: (context, _, _) => Scaffold(
        backgroundColor: AppColors.page,
        appBar: AgriAppBar(title: tl('Appearance')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // A Material, not a coloured box, so the row's press ripple shows.
            Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.grey(200)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                key: const Key('darkModeSwitch'),
                value: AppColors.isDark,
                onChanged: ThemeController.instance.setDark,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.brandFill,
                secondary: Icon(
                  Icons.dark_mode_outlined,
                  color: AppColors.textStrong,
                ),
                title: Text(
                  tr(context).darkMode,
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                subtitle: Text(
                  tl('Easier on the eyes at night. Kept on this phone.'),
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
