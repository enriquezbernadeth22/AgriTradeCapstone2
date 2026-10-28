import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/legal_policies.dart';
import '../widgets/agri_app_bar.dart';
import '../theme/app_colors.dart';

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
      body: PolicyDocumentBody(document: document),
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

  const PolicyDocumentBody({
    super.key,
    required this.document,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 28),
  });

  @override
  Widget build(BuildContext context) {
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
          'Version ${document.version}',
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
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
