import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_language.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'agri_dialog.dart';

/// The small month selector on the Market tab's cards: the month on show
/// ("Nov 2026", short so the card's title keeps its room) and an arrow.
/// Tapping it opens [showMonthYearPicker].
class MonthPickerPill extends StatelessWidget {
  final DateTime month;
  final VoidCallback onTap;

  const MonthPickerPill({super.key, required this.month, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tl('Select month'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.compactDropdownRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.compactDropdownRadius),
            border: Border.all(color: AppColors.adapt(const Color(0xFFE3E9DF))),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('MMM y').format(month),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.normal,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A calendar of months in a bottom sheet: a year with arrows, and its twelve
/// months. Only [firstMonth]..[currentMonth] can be chosen, and [note] says
/// why. Returns the month on Apply, or null on Cancel.
Future<DateTime?> showMonthYearPicker(
  BuildContext context, {
  required DateTime selectedMonth,
  required DateTime firstMonth,
  required DateTime currentMonth,
  required String note,
}) {
  final minimumYear = firstMonth.year;
  final maximumYear = currentMonth.year;
  var pickerYear = selectedMonth.year;
  var draftMonth = selectedMonth;

  return showAgriPanelSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final canGoPrevious = pickerYear > minimumYear;
        final canGoNext = pickerYear < maximumYear;

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.adapt(const Color(0xFFDDE5DB)),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                tl('Select Month'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _YearArrow(
                    icon: Icons.chevron_left_rounded,
                    enabled: canGoPrevious,
                    onTap: () => setSheetState(() => pickerYear--),
                  ),
                  Text(
                    '$pickerYear',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  _YearArrow(
                    icon: Icons.chevron_right_rounded,
                    enabled: canGoNext,
                    onTap: () => setSheetState(() => pickerYear++),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 12,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisExtent: 42,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final month = DateTime(pickerYear, index + 1);
                  final isValid =
                      !month.isBefore(firstMonth) &&
                      !month.isAfter(currentMonth);
                  final isSelected =
                      month.year == draftMonth.year &&
                      month.month == draftMonth.month;
                  return InkWell(
                    onTap: isValid
                        ? () => setSheetState(() => draftMonth = month)
                        : null,
                    borderRadius: BorderRadius.circular(11),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.brandFill
                            : isValid
                            ? AppColors.adapt(const Color(0xFFF4F8F2))
                            : AppColors.adapt(const Color(0xFFF7F7F7)),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.brand
                              : AppColors.adapt(const Color(0xFFE8EEE6)),
                        ),
                      ),
                      child: Text(
                        DateFormat.MMMM().format(month),
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : isValid
                              ? AppColors.text
                              : AppColors.grey(400),
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _LegendDot(AppColors.brand),
                  const SizedBox(width: 5),
                  Text(
                    tl('Selectable month'),
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  _LegendDot(AppColors.adapt(const Color(0xFFD8DDD9))),
                  const SizedBox(width: 5),
                  Text(
                    tl('Not available'),
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.adapt(const Color(0xFFF0F8EF)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.brand,
                      size: 16,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        note,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.35,
                          color: AppColors.adapt(const Color(0xFF52614F)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brand,
                        side: BorderSide(
                          color: AppColors.adapt(const Color(0xFFDDE5DB)),
                        ),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      child: Text(tl('Cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext, draftMonth),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandFill,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      child: Text(tl('Apply')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _YearArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _YearArrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.tint
              : AppColors.adapt(const Color(0xFFF3F4F3)),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? AppColors.brand : AppColors.grey(400),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;

  const _LegendDot(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
