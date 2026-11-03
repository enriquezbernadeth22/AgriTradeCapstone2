import 'package:flutter/material.dart';
import 'app_scaffold_messenger.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_language.dart';
import '../l10n/tr.dart';
import '../screen/manage_account_screen.dart';
import '../screen/notification_preferences_screen.dart';
import '../services/product_share_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import 'agri_dialog.dart';
import 'feedback_sheet.dart';
import 'language_picker.dart';

enum _SettingsChoice { share, notifications, manage, feedback, help, logout }

/// Opens the Settings sheet, from the gear in the tabs' header (PageHeader):
///
///   Share AgriTrade+   Notification Settings   Dark Mode   Language
///   ─────   Manage Account
///   ─────   Send Feedback   Help & Support
///   ─────   Log Out (a soft red button)
///
/// Manage Account is one screen for both roles; Help & Support and Log Out
/// are the role's own ([onHelp], [onLogout]). Dark Mode and Language change
/// the app behind the open sheet, so the person sees the result; every other
/// row closes the sheet first.
Future<void> showSettingsSheet(
  BuildContext context, {
  required VoidCallback onHelp,
  required VoidCallback onLogout,
}) async {
  // Solid white with rounded top corners, from the app's bottom sheet theme:
  // on the frosted popup surface the dimmed page greys the sheet.
  final choice = await showModalBottomSheet<_SettingsChoice>(
    context: context,
    // A plain sheet stops at 9/16 of the screen, shorter than this list.
    isScrollControlled: true,
    barrierColor: agriBarrierColor,
    builder: (_) => const _SettingsList(),
  );
  if (!context.mounted) return;

  void open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  switch (choice) {
    case _SettingsChoice.share:
      _shareApp(context);
    case _SettingsChoice.notifications:
      open(const NotificationPreferencesScreen());
    case _SettingsChoice.manage:
      open(const ManageAccountScreen());
    case _SettingsChoice.feedback:
      showFeedbackSheet(context);
    case _SettingsChoice.help:
      onHelp();
    case _SettingsChoice.logout:
      onLogout();
    case null:
      break;
  }
}

Future<void> _shareApp(BuildContext context) async {
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

class _SettingsList extends StatelessWidget {
  const _SettingsList();

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    Widget closesWith(_SettingsChoice choice, IconData icon, String label) =>
        _SettingsRow(
          icon: icon,
          label: label,
          onTap: () => Navigator.pop(context, choice),
        );
    final groupLine = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(
        height: 1,
        indent: 20,
        endIndent: 20,
        color: AppColors.grey(300),
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Scrolls on a phone too short for the list.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    closesWith(
                      _SettingsChoice.share,
                      Icons.share_outlined,
                      tl('Share AgriTrade+'),
                    ),
                    closesWith(
                      _SettingsChoice.notifications,
                      Icons.notifications_none_rounded,
                      t.notificationSettings,
                    ),
                    // Tapping the row flips the switch too.
                    _SettingsRow(
                      icon: Icons.dark_mode_outlined,
                      label: t.darkMode,
                      onTap: () =>
                          ThemeController.instance.setDark(!AppColors.isDark),
                      trailing: Switch(
                        value: AppColors.isDark,
                        onChanged: ThemeController.instance.setDark,
                        activeThumbColor: Colors.white,
                        activeTrackColor: AppColors.brandFill,
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.language_rounded,
                      label: tl('Language'),
                      onTap: () => showLanguagePicker(context),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            LanguageController.instance.value.label,
                            style: GoogleFonts.montserrat(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.grey(600),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.chevron_right, color: AppColors.grey()),
                        ],
                      ),
                    ),
                    groupLine,
                    closesWith(
                      _SettingsChoice.manage,
                      Icons.manage_accounts_outlined,
                      t.manageAccount,
                    ),
                    groupLine,
                    closesWith(
                      _SettingsChoice.feedback,
                      Icons.rate_review_outlined,
                      t.sendFeedback,
                    ),
                    closesWith(
                      _SettingsChoice.help,
                      Icons.help_outline,
                      t.helpSupport,
                    ),
                    groupLine,
                    _LogOutButton(
                      label: t.logOut,
                      onTap: () =>
                          Navigator.pop(context, _SettingsChoice.logout),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the sheet, at least [minHeight] tall: more only when the phone
/// is set to very large text.
class _SettingsRow extends StatelessWidget {
  static const double minHeight = 50;

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.only(left: 20, right: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.brand),
              const SizedBox(width: 14),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Log Out: a soft red button with a red outline, across the sheet.
class _LogOutButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _LogOutButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final red = AppColors.tone(Colors.red, 700);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Material(
        color: AppColors.tone(Colors.red, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: red.withValues(alpha: 0.55)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout, size: 20, color: red),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: GoogleFonts.montserrat(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: red,
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
