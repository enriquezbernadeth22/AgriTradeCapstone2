import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/legal_policies.dart';
import '../data/mobile_faqs.dart' show kSupportEmail;
import '../l10n/app_language.dart';
import '../services/product_share_service.dart' show kAppPageUrl;
import '../theme/app_colors.dart';
import '../widgets/agri_app_bar.dart';
import '../widgets/agritrade_text.dart';
import 'privacy_policy_screen.dart';
import 'terms_and_conditions_screen.dart';

/// About AgriTrade+, from the Farmer's Settings: what the app is for, the
/// installed version, who makes it and how to reach them, and the legal
/// pages. Every fact is the app's own (the version is read from the build;
/// the email and policy date are the app's constants) — nothing made up.
class AboutScreen extends StatelessWidget {
  /// The installed version; tests pass their own.
  final Future<String?>? version;

  const AboutScreen({super.key, this.version});

  static Future<String?> _installedVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AgriAppBar(title: tl('About AgriTrade+')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
          children: [
            const Center(child: AgriTradeLogoMark(size: 64)),
            const SizedBox(height: 8),
            const Center(child: AgriTradeText(fontSize: 22)),
            const SizedBox(height: 4),
            // Only once it can be read; never a made-up number.
            FutureBuilder<String?>(
              future: version ?? _installedVersion(),
              builder: (context, snapshot) {
                final v = snapshot.data ?? '';
                if (v.isEmpty) return const SizedBox(height: 16);
                return Text(
                  tl('Version {0}', [v]),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                tl(
                  'AgriTrade+ connects the farmers and buyers of Laurel, Batangas. Farmers post their harvest and livestock; buyers order straight from them, chat, and arrange pick-up or delivery.',
                ),
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: 13.5,
                  height: 1.5,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _label(tl('Developer')),
            ListTile(
              leading: Icon(Icons.groups_outlined, color: AppColors.brand),
              title: Text(tl('The AgriTrade+ team')),
              subtitle: const Text(kSupportEmail),
              onTap: () => _launch(
                Uri(
                  scheme: 'mailto',
                  path: kSupportEmail,
                  query: 'subject=${Uri.encodeComponent('AgriTrade+ Support')}',
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.language_rounded, color: AppColors.brand),
              title: Text(tl('Download page')),
              subtitle: const Text(kAppPageUrl),
              onTap: () => _launch(Uri.parse(kAppPageUrl)),
            ),
            _label(tl('Policies')),
            ListTile(
              leading: Icon(Icons.privacy_tip_outlined, color: AppColors.brand),
              title: Text(tl('Privacy Policy')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => open(const PrivacyPolicyScreen()),
            ),
            ListTile(
              leading: Icon(Icons.description_outlined, color: AppColors.brand),
              title: Text(tl('Terms & Conditions')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => open(const TermsAndConditionsScreen()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                tl('Effective {0}', [kPolicyEffectiveDate]),
                style: GoogleFonts.montserrat(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
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

  static Future<void> _launch(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
