import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_colors.dart';

/// [GlowField]'s tap-to-choose twin: the same pill-shaped white plate, icon
/// and thin divider used by the login and registration fields, for a value
/// that is picked rather than typed (a location, a date). Looks identical
/// at rest, so a form can mix typed and picked fields without them looking
/// like two different components.
class GlowTapField extends StatelessWidget {
  final IconData icon;

  /// The chosen value, or null/empty to show [hint] instead.
  final String? value;
  final String hint;
  final VoidCallback onTap;
  final IconData? trailing;

  const GlowTapField({
    super.key,
    required this.icon,
    required this.value,
    required this.hint,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.trim().isNotEmpty;
    final theme = Theme.of(context);
    // The same text and hint styles a TextField inside GlowField resolves to.
    final textStyle = theme.textTheme.titleMedium?.copyWith(
      color: hasValue ? AppColors.text : null,
    );
    final hintStyle =
        theme.inputDecorationTheme.hintStyle ??
        theme.textTheme.titleMedium?.copyWith(color: theme.hintColor);

    return Container(
      decoration: AppTheme.glowFieldWrapper(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 18, right: 12),
                child: Icon(icon, color: AppColors.mid, size: 20),
              ),
              Container(height: 22, width: 1, color: AppColors.hairline),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 18,
                    horizontal: 12,
                  ),
                  child: Text(
                    hasValue ? value! : hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: hasValue ? textStyle : hintStyle,
                  ),
                ),
              ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Icon(trailing, color: AppColors.grey(600), size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
