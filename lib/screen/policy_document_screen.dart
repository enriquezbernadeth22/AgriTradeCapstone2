import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/legal_policies.dart';
import '../widgets/agri_app_bar.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../l10n/app_language.dart';

/// One policy from lib/data/legal_policies.dart as a full page of the
/// mobile app: its title, version and dates, then each section. Used for
/// the Terms of Service and the Privacy Policy, opened from registration
/// and from Settings.
class PolicyDocumentScreen extends StatelessWidget {
  final PolicyDocument document;
  const PolicyDocumentScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AgriAppBar(title: document.title),
      body: PolicyDocumentBody(document: document, cards: true),
    );
  }
}

/// A policy's text — title, version and dates, then each section — as
/// a scrolling column. The mobile page ([PolicyDocumentScreen]) and the
/// Admin Portal's policy popup both show exactly this, so what an Admin
/// confirms a farmer agreed to is the very text farmers see in the app.
class PolicyDocumentBody extends StatelessWidget {
  final PolicyDocument document;
  final EdgeInsetsGeometry padding;

  /// The mobile page's look (the user's design, 2026-11-08): a header card
  /// and one white card per section, on the cream. Off for the Admin
  /// Portal's popup, which keeps its plain column. The text is the same.
  final bool cards;

  const PolicyDocumentBody({
    super.key,
    required this.document,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 28),
    this.cards = false,
  });

  @override
  Widget build(BuildContext context) {
    if (cards) return _cards(context);
    TextStyle body({Color? color, double size = 12.5}) =>
        GoogleFonts.montserrat(
          fontSize: size,
          color: color ?? AppColors.text,
          height: 1.5,
        );

    return ListView(
      padding: padding,
      children: [
        Text(
          'AgriTrade+ ${document.title}',
          style: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${document.effectiveLabel}\n${document.updatedLabel}',
          style: body(color: AppColors.textSecondary, size: 11.5),
        ),
        const SizedBox(height: 12),
        Text(document.intro, style: body(color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        for (final section in document.sections) ...[
          Text(
            section.heading,
            style: GoogleFonts.montserrat(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(height: 6),
          for (final paragraph in section.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 2),
              child: Text(paragraph, style: body()),
            ),
          for (final point in section.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: body(color: AppColors.brand)),
                  Expanded(child: Text(point, style: body())),
                ],
              ),
            ),
          const SizedBox(height: 14),
        ],
        Text(
          tl('Version {0}', [document.version]),
          style: body(color: AppColors.textMuted, size: 11),
        ),
      ],
    );
  }
}

extension on PolicyDocumentBody {
  // The mobile page: the title, version and dates and the intro on a
  // header card, then each section on a card of its own, its number on a
  // small pale green circle.
  Widget _cards(BuildContext context) {
    TextStyle body({Color? color, double size = 12.5}) =>
        GoogleFonts.montserrat(
          fontSize: size,
          color: color ?? AppColors.text,
          height: 1.5,
        );
    final paleGreen = AppColors.isDark
        ? AppColors.tint
        : const Color(0xFFEAF2E4);
    // "tos-1.0" reads as "1.0".
    final version = document.version.contains('-')
        ? document.version.split('-').last
        : document.version;
    final privacy = document.title.toLowerCase().contains('privacy');

    Widget card({required Widget child, Key? key}) => Container(
      key: key,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: AppTheme.card(),
      child: child,
    );

    // "1. Acceptance of Terms": the number and the words apart.
    (String?, String) split(String heading) {
      final match = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(heading);
      return match == null ? (null, heading) : (match[1], match[2]!);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        card(
          key: const Key('policyHeader'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: paleGreen,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      privacy
                          ? Icons.privacy_tip_outlined
                          : Icons.description_outlined,
                      size: 19,
                      color: AppColors.brand,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'AgriTrade+ ${document.title}',
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final label in [
                    tl('Version {0}', [version]),
                    document.effectiveLabel,
                    document.updatedLabel,
                  ])
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: paleGreen,
                        borderRadius: BorderRadius.circular(
                          AppTheme.pillRadius,
                        ),
                      ),
                      child: Text(
                        label,
                        style: GoogleFonts.montserrat(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brand,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(document.intro, style: body(color: AppColors.textSecondary)),
            ],
          ),
        ),
        for (final section in document.sections)
          card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (split(section.heading).$1 case final number?) ...[
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: paleGreen,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          number,
                          style: GoogleFonts.montserrat(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brand,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                    ],
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          split(section.heading).$2,
                          style: GoogleFonts.montserrat(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.heading,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final paragraph in section.paragraphs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(paragraph, style: body()),
                  ),
                for (final point in section.points)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7, right: 9),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: AppColors.brand,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Expanded(child: Text(point, style: body())),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          tl('Version {0}', [version]),
          textAlign: TextAlign.center,
          style: body(color: AppColors.textMuted, size: 11),
        ),
      ],
    );
  }
}

/// The Admin Portal's way to read a policy: [document] in a popup, the same
/// text as the mobile page.
Future<void> showPolicyDocumentDialog(
  BuildContext context,
  PolicyDocument document,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final height = MediaQuery.sizeOf(dialogContext).height;
      return AlertDialog(
        title: Text(document.title),
        contentPadding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
        content: SizedBox(
          width: 680,
          height: height * 0.7,
          child: PolicyDocumentBody(
            document: document,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(tl('Close')),
          ),
        ],
      );
    },
  );
}
