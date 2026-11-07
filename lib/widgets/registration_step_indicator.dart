import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Shows progress through the three mobile account registration steps:
/// numbered circles joined by thin lines, each with its name underneath.
///
/// It only shows where the user is; the circles cannot be tapped, so the
/// form's own Back and Continue stay the only way between steps.
class RegistrationStepIndicator extends StatelessWidget {
  /// The active step, from 1 through 3.
  final int step;

  const RegistrationStepIndicator({super.key, required this.step});

  /// The name shown under each circle, in order.
  static const labels = ['Choose Role', 'Your Information', 'Account Setup'];

  static const double _circleSize = 30;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tl('Step {0} of {1}: {2}', [
        step,
        labels.length,
        tl(labels[step - 1]),
      ]),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.formSectionGap),
        // Each step takes an equal third, so the labels have the same room
        // and the circles sit evenly spaced over them.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var number = 1; number <= labels.length; number++)
              Expanded(child: _step(number)),
          ],
        ),
      ),
    );
  }

  Widget _step(int number) {
    final completed = number < step;
    final active = number == step;
    final filled = active || completed;
    return Column(
      children: [
        Row(
          children: [
            // The line into this circle, from the step before (none on
            // the first), green once that step is done.
            Expanded(
              child: _line(visible: number > 1, done: number <= step),
            ),
            Container(
              width: _circleSize,
              height: _circleSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? AppColors.brandFill : AppColors.surface,
                border: Border.all(
                  color: filled ? AppColors.brandFill : AppColors.grey(400),
                  width: 1.2,
                ),
              ),
              child: completed
                  ? const Icon(
                      Icons.check_rounded,
                      size: 17,
                      color: Colors.white,
                    )
                  : Text(
                      '$number',
                      style: AppTheme.body(
                        color: active ? Colors.white : AppColors.textMuted,
                        size: 13,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
            ),
            Expanded(
              child: _line(
                visible: number < labels.length,
                done: number < step,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Always one line, so the steps are the same height on every screen
        // and never move between them: 11.5, which fits "Your Information"
        // from a 360-wide phone up; on a narrower one it shrinks a little.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            tl(labels[number - 1]),
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            style:
                AppTheme.body(
                  color: active ? AppColors.brand : AppColors.textSecondary,
                  size: 11.5,
                ).copyWith(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  height: 1.2,
                ),
          ),
        ),
      ],
    );
  }

  Widget _line({required bool visible, required bool done}) => Container(
    height: 1.5,
    color: !visible
        ? Colors.transparent
        : done
        ? AppColors.brandFill
        : AppColors.grey(300),
  );
}
