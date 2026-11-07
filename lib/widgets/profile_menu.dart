import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// One option on the buyer's Profile tab (My Reviews, Liked Products…): a
/// compact row — a dark green icon, the label, a chevron — inside its
/// group's white card ([ProfileMenuGroup]); the user's design, 2026-11-08.
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
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.brand),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.grey(500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A group of Profile options: its title, then its rows on one white
/// rounded card with hairlines between them (the user's design,
/// 2026-11-08).
class ProfileMenuGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const ProfileMenuGroup({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final (i, child) in children.indexed) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: 50,
            endIndent: 14,
            color: AppColors.isDark
                ? AppColors.hairline
                : const Color(0xFFE8E9E3),
          ),
        );
      }
      rows.add(child);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileSectionLabel(title),
          Container(
            width: double.infinity,
            decoration: AppTheme.card(),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: rows),
            ),
          ),
        ],
      ),
    );
  }
}

/// The small dark green heading over a group of Profile options.
class ProfileSectionLabel extends StatelessWidget {
  final String text;
  const ProfileSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: GoogleFonts.montserrat(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.brand,
        ),
      ),
    ),
  );
}
