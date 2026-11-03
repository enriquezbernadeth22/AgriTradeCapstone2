import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// A crate of fresh produce (the art of the old role cards), for empty
/// product and order lists.
const String kEmptyProduceArt = 'assets/images/onboarding/role_buyer.png';

/// The one "nothing here yet" look for the mobile app: a small dark-green
/// icon on a pale-green circle (or, with [art], a picture), a title, an
/// optional line under it and an optional action. Every empty list — orders, messages, notifications,
/// reviews, search results — uses this, so they all match.
class AgriEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  /// A picture shown in place of the icon, for the empty pages a buyer or
  /// farmer sees most (no products, no orders): see [kEmptyProduceArt].
  final String? art;

  /// Space around the content. The default suits a full page; a list
  /// inside a card passes something tighter.
  final EdgeInsetsGeometry padding;

  const AgriEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.art,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  });

  Widget _iconCircle() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.tint, shape: BoxShape.circle),
    child: Icon(icon, size: 30, color: AppColors.brand),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (art != null)
            ExcludeSemantics(
              child: Image.asset(
                art!,
                height: 96,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => _iconCircle(),
              ),
            )
          else
            _iconCircle(),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 12.5,
                color: AppColors.grey(600),
                height: 1.4,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
