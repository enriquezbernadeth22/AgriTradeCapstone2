import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../l10n/app_language.dart';
import '../data/account_types.dart';
import 'glow_field.dart';
import 'fitted_menu_width.dart';

/// The role-specific question shown on registration forms after role choice.
class RegistrationRoleDetails extends StatelessWidget {
  final bool isFarmer;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Says the answer is needed: after a submit attempt without one.
  final bool showRequired;

  const RegistrationRoleDetails({
    super.key,
    required this.isFarmer,
    required this.value,
    required this.onChanged,
    this.showRequired = false,
  });

  @override
  Widget build(BuildContext context) {
    final options = isFarmer ? kFarmerTypes : kBuyerTypes;
    final baseTheme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isFarmer
              ? tl('What best describes you as a farmer?')
              : tl('What best describes you as a buyer?'),
          style: AppTheme.label(),
        ),
        const SizedBox(height: AppTheme.formLabelGap),
        FormFieldGlow(
          radius: AppTheme.dropdownRadius,
          child: Theme(
            data: baseTheme.copyWith(
              // Dropdown menus inherit Material's selected and hover colours.
              // Keep those neutral grey rather than using the brand green.
              colorScheme: baseTheme.colorScheme.copyWith(
                primary: AppColors.adapt(Colors.grey.shade300),
                onPrimary: AppColors.text,
              ),
              hoverColor: AppColors.adapt(Colors.grey.shade200),
              focusColor: AppColors.adapt(Colors.grey.shade200),
              highlightColor: AppColors.adapt(Colors.grey.shade200),
              splashColor: AppColors.adapt(Colors.grey.shade300),
            ),
            // The open list is as wide as its longest option, not the
            // whole field (FittedDropdownField).
            child: FittedDropdownField<String>(
              key: ValueKey(isFarmer),
              value: options.contains(value) ? value : null,
              labels: [for (final option in options) tl(option)],
              icon: Icon(
                Icons.expand_more_rounded,
                color: AppTheme.formIconColor,
                size: AppTheme.formIconSize,
              ),
              dropdownColor: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.dropdownRadius),
              style: AppTheme.body(
                color: AppColors.text,
              ).copyWith(fontSize: AppTheme.formTextSize),
              decoration: AppTheme.formDropdownDecoration(
                // The same for both roles: the question is what kind of
                // farmer or buyer, so an ID card rather than a role picture.
                icon: Icons.badge_outlined,
                onGlowPlate: true,
              ),
              hint: Text(tl('Select an option'), style: AppTheme.formHint()),
              items: [
                for (final option in options)
                  DropdownMenuItem(value: option, child: Text(tl(option))),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
        if (showRequired && value == null) ...[
          const SizedBox(height: 6),
          Text(
            tl('Please choose what best describes you.'),
            style: AppTheme.body(
              size: 12,
              color: AppColors.tone(Colors.red, 700),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Registering as Buyer" or "Registering as Farmer", under a registration
/// form's title: the role was chosen on the screen before, and this form has
/// no way to switch it (Back does).
class RegisteringAsBadge extends StatelessWidget {
  final bool isFarmer;

  const RegisteringAsBadge({super.key, required this.isFarmer});

  @override
  Widget build(BuildContext context) {
    // Plain green words, lined up with the title above them.
    return Text(
      isFarmer ? tl('Registering as Farmer') : tl('Registering as Buyer'),
      style: AppTheme.formLink(size: 12.5),
    );
  }
}
