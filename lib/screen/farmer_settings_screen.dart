import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_language.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/agri_app_bar.dart';
import '../widgets/feedback_sheet.dart';
import '../widgets/settings_sheet.dart' show LogOutButton, shareAgriTrade;
import 'about_screen.dart';
import 'help_support_screen.dart';
import 'manage_account_screen.dart';
import 'notification_preferences_screen.dart';

/// The Farmer's Settings, a page of its own opened from the gear beside
/// the Profile title (the user's design, 2026-11-07; the Buyer keeps hers
/// on the Buyer Profile). Every row opens something that already exists:
///
///   ACCOUNT & SECURITY   Manage Account · Privacy & Security
///   PREFERENCES          Notification Settings · Dark Mode
///   SUPPORT & INFORMATION Send Feedback · Help & Support ·
///                         About AgriTrade+ · Share AgriTrade+
///   Log Out (a soft red outlined button)
///
/// A chevron only on a row that opens another screen.
class FarmerSettingsScreen extends StatelessWidget {
  /// The Farmer's Log Out, with its confirmation (FarmerHomeScreen's).
  final VoidCallback onLogout;

  const FarmerSettingsScreen({super.key, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AgriAppBar(title: tl('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          children: [
            _SectionLabel(tl('Account & Security')),
            _Row(
              icon: Icons.person_outline,
              label: t.manageAccount,
              opensScreen: true,
              onTap: () => open(
                const ManageAccountScreen(part: ManageAccountPart.account),
              ),
            ),
            _Row(
              icon: Icons.lock_outline,
              label: tl('Privacy & Security'),
              opensScreen: true,
              onTap: () => open(
                const ManageAccountScreen(part: ManageAccountPart.security),
              ),
            ),
            const _SectionDivider(),
            _SectionLabel(tl('Preferences')),
            _Row(
              icon: Icons.notifications_none_rounded,
              label: t.notificationSettings,
              opensScreen: true,
              onTap: () => open(const NotificationPreferencesScreen()),
            ),
            // Rebuilds with the theme, so the switch shows the saved choice.
            ListenableBuilder(
              listenable: ThemeController.instance,
              builder: (context, _) => _Row(
                icon: Icons.dark_mode_outlined,
                label: t.darkMode,
                // Tapping the row flips the switch too.
                onTap: () =>
                    ThemeController.instance.setDark(!AppColors.isDark),
                trailing: Switch(
                  value: AppColors.isDark,
                  onChanged: ThemeController.instance.setDark,
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.brandFill,
                ),
              ),
            ),
            const _SectionDivider(),
            _SectionLabel(tl('Support & Information')),
            _Row(
              icon: Icons.rate_review_outlined,
              label: tl('Send Feedback'),
              onTap: () => showFeedbackSheet(context),
            ),
            _Row(
              icon: Icons.help_outline_rounded,
              label: tl('Help & Support'),
              opensScreen: true,
              onTap: () => open(const HelpSupportScreen(farmer: true)),
            ),
            _Row(
              icon: Icons.info_outline_rounded,
              label: tl('About AgriTrade+'),
              opensScreen: true,
              onTap: () => open(const AboutScreen()),
            ),
            _Row(
              icon: Icons.share_outlined,
              label: tl('Share AgriTrade+'),
              onTap: () => shareAgriTrade(context),
            ),
            const SizedBox(height: 20),
            LogOutButton(label: t.logOut, onTap: onLogout),
          ],
        ),
      ),
    );
  }
}

/// A small grey heading over a group of rows.
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
    child: Text(
      text.toUpperCase(),
      style: GoogleFonts.montserrat(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

/// A thin line between the groups.
class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Divider(
      height: 1,
      indent: 20,
      endIndent: 20,
      color: AppColors.hairline,
    ),
  );
}

/// One setting: an outline icon, its name, and on the right a chevron
/// (only when it opens another screen) or its own control.
class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool opensScreen;
  final Widget? trailing;

  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.opensScreen = false,
    this.trailing,
  });

  /// Every row is this tall, switch or not.
  static const double height = 52;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.text),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.montserrat(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
            ),
            ?trailing,
            if (trailing == null && opensScreen)
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.textSecondary,
              ),
          ],
        ),
      ),
    ),
  );
}
