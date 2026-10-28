import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screen/manage_account_screen.dart';
import '../screen/notification_preferences_screen.dart';
import 'page_header.dart';
import '../theme/theme_controller.dart';
import 'feedback_sheet.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';

/// The settings (gear) menu beside the farmer's Profile title:
///
///   [Share My Store]   Notification Settings   Dark Mode (a switch)
///   Manage Account   Send Feedback   Help & Support   ─────   Log Out (red)
///
/// (The buyer's Profile lists the same options on the page itself, in
/// labelled groups.) Manage Account is one screen for both roles; Help &
/// Support and Log Out are the role's own ([onHelp], [onLogout]).
class ProfileSettingsMenu extends StatelessWidget {
  /// Farmers only: shares their store. Null leaves the item out.
  final VoidCallback? onShareStore;
  final VoidCallback onHelp;
  final VoidCallback onLogout;

  const ProfileSettingsMenu({
    super.key,
    this.onShareStore,
    required this.onHelp,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    // Compact rows: a small icon, then small text.
    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String label, {
      Color? color,
    }) => PopupMenuItem(
      value: value,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color ?? AppColors.text),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color ?? AppColors.text,
            ),
          ),
        ],
      ),
    );

    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    return PopupMenuButton<String>(
      tooltip: 'Settings',
      icon: Icon(Icons.settings_outlined, color: PageHeader.titleColor),
      // A small floating panel that opens just below the icon.
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      // White, rounded, shadowed: the app-wide popup menu look (AppTheme).
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      onSelected: (value) {
        switch (value) {
          case 'share':
            onShareStore?.call();
          case 'notifications':
            open(const NotificationPreferencesScreen());
          case 'dark':
            ThemeController.instance.setDark(!AppColors.isDark);
          case 'manage':
            open(const ManageAccountScreen());
          case 'feedback':
            showFeedbackSheet(context);
          case 'help':
            onHelp();
          case 'logout':
            onLogout();
        }
      },
      itemBuilder: (context) => [
        if (onShareStore != null)
          item('share', Icons.share_outlined, t.shareMyStore),
        item(
          'notifications',
          Icons.notifications_none_rounded,
          t.notificationSettings,
        ),
        // Dark Mode: a switch in the row; tapping the row flips it, and
        // the whole app changes at once.
        PopupMenuItem(
          value: 'dark',
          height: 40,
          padding: const EdgeInsets.only(left: 14, right: 6),
          child: Row(
            children: [
              Icon(Icons.dark_mode_outlined, size: 18, color: AppColors.text),
              const SizedBox(width: 10),
              Text(
                t.darkMode,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 12),
              const Spacer(),
              IgnorePointer(
                child: Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: AppColors.isDark,
                    onChanged: (_) {},
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.brandFill,
                  ),
                ),
              ),
            ],
          ),
        ),
        item('manage', Icons.manage_accounts_outlined, t.manageAccount),
        item('feedback', Icons.rate_review_outlined, t.sendFeedback),
        item('help', Icons.help_outline, t.helpSupport),
        const PopupMenuDivider(height: 9),
        item(
          'logout',
          Icons.logout,
          t.logOut,
          color: AppColors.adapt(const Color(0xFFD32F2F)),
        ),
      ],
    );
  }
}
