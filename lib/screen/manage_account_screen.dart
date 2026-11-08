import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_theme.dart';
import '../widgets/agri_app_bar.dart';
import '../widgets/change_password_dialog.dart';
import 'farmer_edit_profile_screen.dart';
import 'privacy_policy_screen.dart';
import 'sign_in_activity_screen.dart';
import 'terms_and_conditions_screen.dart';
import '../l10n/app_localizations.dart';
import '../l10n/app_language.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';

/// Manage Account, opened from the Settings sheet — the same
/// screen for Farmers and Buyers: one plain list in sections (personal
/// information, the account's security, the legal pages)
/// with the app version at the foot.
///
/// Notification Settings, Help & Support and Log Out are not here: they
/// are in the Settings sheet already.
/// Which part of the screen to show: all of it (the Buyer's Manage
/// Account), or one part of it, for the Farmer's Settings page, where
/// Manage Account and Privacy & Security are rows of their own and the
/// legal pages are under About AgriTrade+.
enum ManageAccountPart { all, account, security }

class ManageAccountScreen extends StatelessWidget {
  final ManageAccountPart part;

  const ManageAccountScreen({super.key, this.part = ManageAccountPart.all});

  // Read once for the app's lifetime — it cannot change while running.
  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AgriAppBar(
        title: part == ManageAccountPart.security
            ? tl('Privacy & Security')
            : t.manageAccount,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            if (part != ManageAccountPart.security) ...[
              _SectionLabel(t.sectionAccount),
              // One row: the name, photo, contact details and the recovery
              // email are all in Edit Profile (the user, 2026-11-08; a
              // separate Recovery Email row opened the same screen).
              _SettingsRow(
                icon: Icons.person_outline,
                title: t.personalInformation,
                subtitle: t.personalInformationHint,
                onTap: () => open(const EditProfileScreen()),
              ),
            ],
            if (part == ManageAccountPart.all) const _SectionDivider(),
            if (part != ManageAccountPart.account) ...[
              _SectionLabel(t.sectionSecurity),
              _SettingsRow(
                icon: Icons.lock_outline,
                title: t.changePassword,
                subtitle: t.changePasswordHint,
                onTap: () => showChangePasswordDialog(context),
              ),
              _SettingsRow(
                icon: Icons.devices_other_outlined,
                title: t.devicesActivity,
                subtitle: t.devicesActivityHint,
                onTap: () => open(const SignInActivityScreen()),
              ),
            ],
            if (part == ManageAccountPart.all) ...[
              const _SectionDivider(),
              _SectionLabel(t.sectionAbout),
              _SettingsRow(
                icon: Icons.privacy_tip_outlined,
                title: t.privacyPolicy,
                subtitle: t.privacyPolicyHint,
                onTap: () => open(const PrivacyPolicyScreen()),
              ),
              _SettingsRow(
                icon: Icons.description_outlined,
                title: t.termsConditions,
                subtitle: t.termsConditionsHint,
                onTap: () => open(const TermsAndConditionsScreen()),
              ),
              const SizedBox(height: 24),
              _version(t),
            ],
          ],
        ),
      ),
    );
  }

  // The real version from the installed build; nothing is shown until (or
  // unless) it can be read.
  Widget _version(AppLocalizations t) => FutureBuilder<PackageInfo>(
    future: _packageInfo,
    builder: (context, snapshot) {
      final version = snapshot.data?.version ?? '';
      if (version.isEmpty) return const SizedBox(height: 15);
      return Text(
        t.appVersion(version),
        textAlign: TextAlign.center,
        style: GoogleFonts.montserrat(
          fontSize: 11.5,
          color: AppColors.grey(500),
        ),
      );
    },
  );
}

/// A small grey heading over a group of rows.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
    child: Text(
      text.toUpperCase(),
      style: GoogleFonts.montserrat(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.grey(600),
      ),
    ),
  );
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Divider(height: 1, color: AppColors.grey(200)),
  );
}

/// One plain row: green icon, title, short line under it, chevron.
class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  // The same text as the Notification Settings rows.
  static TextStyle get _titleStyle =>
      AppTheme.body(size: 14.5).copyWith(fontWeight: FontWeight.w700);
  static TextStyle get _subtitleStyle => AppTheme.body(
    size: 12.5,
  ).copyWith(color: AppColors.grey(700), fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppColors.brand),
    title: Text(title, style: _titleStyle),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(subtitle, style: _subtitleStyle),
    ),
    trailing: Icon(Icons.chevron_right, color: AppColors.grey(500)),
    onTap: onTap,
  );
}
