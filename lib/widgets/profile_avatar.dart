import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A user's profile photo, falling back to their initials when they have
/// no photo (or it fails to load). Shared by the Messages list, Messages
/// search and the chat header so Farmer and Buyer sides always match.
class ProfileAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final double radius;

  const ProfileAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    this.radius = 24,
  });

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim() ?? '';
    final initials = Text(
      _initials,
      style: TextStyle(
        color: AppColors.brand,
        fontWeight: FontWeight.bold,
        fontSize: radius * 0.72,
      ),
    );

    // The photo from the disk cache when it has been seen before (shown at
    // once, no initials first); a plain pale circle while a new one loads,
    // fading in; the initials only with no photo or a broken one. Decoded
    // at the size it is shown (2026-11-08).
    final size = radius * 2;
    final decode = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.accent,
      child: url.isEmpty
          ? initials
          : ClipOval(
              child: CachedNetworkImage(
                imageUrl: url,
                // Keyed by URL so an updated photo replaces the old one
                // instead of reusing its image state.
                key: ValueKey(url),
                width: size,
                height: size,
                fit: BoxFit.cover,
                memCacheWidth: decode,
                fadeInDuration: const Duration(milliseconds: 150),
                fadeOutDuration: Duration.zero,
                placeholder: (_, _) => SizedBox(width: size, height: size),
                errorWidget: (_, _, _) => Center(child: initials),
              ),
            ),
    );
  }
}
