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

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.accent,
      child: url.isEmpty
          ? initials
          : ClipOval(
              child: Image.network(
                url,
                // Keyed by URL so an updated photo replaces the old one
                // instead of reusing its image state.
                key: ValueKey(url),
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => initials,
              ),
            ),
    );
  }
}
