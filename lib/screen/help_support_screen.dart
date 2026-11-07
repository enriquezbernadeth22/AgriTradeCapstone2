import 'package:flutter/material.dart';
import '../widgets/app_scaffold_messenger.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/mobile_faqs.dart';
import '../widgets/agri_app_bar.dart';
import '../widgets/coach_mark.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

/// Help & Support for the mobile app, from the Profile tab's settings
/// menu: the FAQ for the user's role (tap a question to open its answer),
/// then how to reach the AgriTrade+ team — the support email (copy it or
/// open the mail app).
class HelpSupportScreen extends StatelessWidget {
  final bool farmer;

  const HelpSupportScreen({super.key, required this.farmer});

  @override
  Widget build(BuildContext context) {
    final faqs = mobileFaqsFor(farmer: farmer);
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AgriAppBar(title: tr(context).helpSupport),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _label(tr(context).faqTitle),
            for (var i = 0; i < faqs.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: AppColors.grey(200),
                ),
              _FaqTile(faq: faqs[i]),
            ],
            const SizedBox(height: 10),
            _label(tr(context).contactUs),
            const _ContactEmail(),
            const SizedBox(height: 10),
            _label(tl('Tips')),
            const _ShowTipsAgain(),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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

/// One question; tapping it opens the answer under it.
class _FaqTile extends StatelessWidget {
  final MobileFaq faq;
  const _FaqTile({required this.faq});

  @override
  Widget build(BuildContext context) => Theme(
    // No lines above and below an open tile — the dividers do that.
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      iconColor: AppColors.brand,
      collapsedIconColor: AppColors.grey(500),
      expandedAlignment: Alignment.centerLeft,
      title: Text(
        faq.question,
        style: GoogleFonts.montserrat(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
      children: [
        Text(
          faq.answer,
          style: GoogleFonts.montserrat(
            fontSize: 12.5,
            height: 1.5,
            color: AppColors.grey(700),
          ),
        ),
      ],
    ),
  );
}

/// The support email, with Copy and a button that opens the mail app.
/// Turns the first-time tips back on (after Skip, or to see them again):
/// each shows the next time its screen opens.
class _ShowTipsAgain extends StatelessWidget {
  const _ShowTipsAgain();

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(Icons.lightbulb_outline_rounded, color: AppColors.brand),
    title: Text(tl('Show tips again')),
    subtitle: Text(tl('The short guides on each screen, from the start')),
    onTap: () async {
      await TutorialTips.showAgain();
      if (!context.mounted) return;
      showAppMessage(
        context,
        tl('Tips will show again as you open each screen.'),
        kind: MessageKind.success,
      );
    },
  );
}

class _ContactEmail extends StatelessWidget {
  const _ContactEmail();

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(Icons.mail_outline_rounded, color: AppColors.brand),
    title: const Text(kSupportEmail),
    subtitle: Text(tl('Email the AgriTrade+ team')),
    onTap: () => _email(context),
    trailing: IconButton(
      tooltip: tl('Copy email'),
      icon: Icon(Icons.copy_rounded, size: 20, color: AppColors.grey(600)),
      onPressed: () async {
        await Clipboard.setData(const ClipboardData(text: kSupportEmail));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar(tl('Email copied.'), kind: MessageKind.success),
        );
      },
    ),
  );

  Future<void> _email(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    bool opened;
    try {
      opened = await launchUrl(
        Uri(
          scheme: 'mailto',
          path: kSupportEmail,
          query: 'subject=${Uri.encodeComponent('AgriTrade+ Support')}',
        ),
      );
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        appSnackBar(
          tl('No email app found. The address can be copied.'),
          kind: MessageKind.warning,
        ),
      );
    }
  }
}
