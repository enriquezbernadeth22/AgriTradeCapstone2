import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// One option on the buyer's Profile tab (My Reviews, Liked Products…):
/// a plain row — icon, label, chevron — with a hairline under it, the same
/// look as the Manage Account list (no card per option).
class ProfileLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ProfileLinkTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: Icon(icon, color: AppColors.brand),
          title: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: AppColors.text,
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: AppColors.grey()),
          onTap: onTap,
        ),
        Divider(
          height: 1,
          indent: 20,
          endIndent: 20,
          color: AppColors.grey(200),
        ),
      ],
    );
  }
}

/// A small grey heading over a group of Profile options — the divisions
/// of the list, not cards.
class ProfileSectionLabel extends StatelessWidget {
  final String text;
  const ProfileSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.grey(600),
        ),
      ),
    ),
  );
}
