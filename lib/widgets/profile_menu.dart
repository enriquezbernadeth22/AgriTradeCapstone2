import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// One option on the buyer's Profile tab (My Reviews, Liked Products…):
/// a plain row — icon, label, chevron — with a hairline under it, the same
/// look as the Manage Account list (no card per option).
///
/// [destructive] is for Log Out: a full-width red button instead of a row.
class ProfileLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const ProfileLinkTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    if (destructive) return _button();
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

  // Log Out: a soft red button with a red outline, across the page.
  Widget _button() {
    final red = AppColors.tone(Colors.red, 700);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
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
                Icon(icon, size: 20, color: red),
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

/// A Profile option that is a switch (Dark Mode): the same row as
/// [ProfileLinkTile], with a switch in place of the chevron. Tapping
/// anywhere on the row flips it.
class ProfileSwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const ProfileSwitchTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
        contentPadding: const EdgeInsets.only(left: 20, right: 12),
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
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.brandFill,
        ),
        onTap: () => onChanged(!value),
      ),
      Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.grey(200)),
    ],
  );
}
