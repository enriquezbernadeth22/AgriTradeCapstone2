import 'package:flutter/material.dart';

import '../screen/farmer_storefront_screen.dart' show ProfileLandscapePainter;
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'profile_avatar.dart';

/// The top of a Profile tab, the buyer's and the farmer's alike (the
/// user's design, 2026-11-08): the tab's title (with an optional button
/// opposite it, the farmer's Settings gear) over the drawn cover of a
/// farmer's public profile, the photo standing on the cover's lower edge in
/// a full gold ring with a thin white ring, and a small dark green pencil
/// at its lower right. Tapping the photo calls [onEdit] (Edit Profile).
class ProfileCoverHeader extends StatelessWidget {
  final String title;
  final String name;
  final String? photoUrl;
  final VoidCallback onEdit;

  /// Opposite the title (the farmer's Settings gear).
  final Widget? trailing;

  const ProfileCoverHeader({
    super.key,
    required this.title,
    required this.name,
    required this.photoUrl,
    required this.onEdit,
    this.trailing,
  });

  /// The photo is 84 across: a full gold circle, a thin white ring inside
  /// it, then the photo, on a soft shadow.
  static const double photo = 84;
  static const double _ring = 2.5;
  static const double _gap = 2.5;
  static const double _cover = 128;
  static const Color _gold = Color(0xFFF5BB24);

  @override
  Widget build(BuildContext context) {
    final green = AppColors.isDark
        ? AppColors.brandFill
        : const Color(0xFF0B4225);
    return SizedBox(
      height: _cover + photo / 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The same drawn cover as a farmer's public profile: cream sky,
          // soft layered hills with faint field lines, small leaf sprigs;
          // its top fades in from the page, under the header.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _cover,
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: ProfileLandscapePainter(
                  softTop: true,
                  dark: AppColors.isDark,
                ),
              ),
            ),
          ),
          // The title alone, as on the other tabs.
          Positioned(
            left: 21,
            top: 8,
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: AppTheme.mainTitleSize,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: AppColors.heading,
              ),
            ),
          ),
          if (trailing != null) Positioned(right: 8, top: 0, child: trailing!),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: GestureDetector(
                key: const Key('profilePhoto'),
                onTap: onEdit,
                child: SizedBox.square(
                  dimension: photo,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        key: const Key('profileGoldRing'),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: _gold, width: _ring),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(_gap),
                        child: ProfileAvatar(
                          photoUrl: photoUrl,
                          name: name,
                          radius: photo / 2 - _ring - _gap,
                        ),
                      ),
                      Positioned(
                        right: -1,
                        bottom: 1,
                        child: Container(
                          key: const Key('profileEdit'),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
