import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The search bar of the tabs (Explore, Messages; the user's design,
/// 2026-11-08): a white pill on a soft shadow holding the search field (its
/// own thin pill, a dark green search icon, the hint in grey) and, at its
/// end, an optional [trailing] button. Sizes from the user's picture of
/// Explore, for a 390-wide screen.
///
/// With [onTap] it is a button that opens that tab's search screen; with
/// [controller] it is the field itself (the Search screen), the very same
/// bar, so moving from one to the other changes nothing in its look.
class ExploreSearchPill extends StatefulWidget {
  final String hint;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// The key of the tappable field (for tests and first-time tips).
  final Key? fieldKey;

  // As a field.
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Shown as a small × while the field has text.
  final VoidCallback? onClear;
  final bool autofocus;

  const ExploreSearchPill({
    super.key,
    required this.hint,
    this.onTap,
    this.trailing,
    this.fieldKey,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
  }) : assert(onTap != null || controller != null);

  static const double height = 41;
  static const double fontSize = 10.5;

  @override
  State<ExploreSearchPill> createState() => _ExploreSearchPillState();
}

class _ExploreSearchPillState extends State<ExploreSearchPill> {
  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(ExploreSearchPill old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_rebuild);
      widget.controller?.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One letter spacing for the button and the field (a field would
    // otherwise take the wider one of the input theme).
    final hintStyle = TextStyle(
      fontSize: ExploreSearchPill.fontSize,
      letterSpacing: 0.25,
      color: AppColors.grey(500),
    );
    final controller = widget.controller;
    final showClear =
        widget.onClear != null && (controller?.text.isNotEmpty ?? false);
    final field = Container(
      height: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        border: Border.all(color: const Color(0xFFE8E8E4)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 11),
          Icon(Icons.search, color: AppColors.brand, size: 16),
          const SizedBox(width: 15),
          Expanded(
            child: controller == null
                ? Text(
                    widget.hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: hintStyle,
                  )
                : TextField(
                    controller: controller,
                    focusNode: widget.focusNode,
                    autofocus: widget.autofocus,
                    cursorColor: AppColors.brand,
                    cursorHeight: 14,
                    // In the middle of the bar, like the icon: the app's
                    // input theme would otherwise give the field a taller
                    // box with the text at its top.
                    textAlignVertical: TextAlignVertical.center,
                    textInputAction: TextInputAction.search,
                    style: TextStyle(
                      fontSize: ExploreSearchPill.fontSize,
                      letterSpacing: 0.25,
                      color: AppColors.text,
                    ),
                    // Every border off: the bar's own pill is its only
                    // outline, focused or not, as on Explore.
                    decoration: InputDecoration(
                      isCollapsed: true,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: widget.hint,
                      hintStyle: hintStyle,
                      hintMaxLines: 1,
                    ),
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                  ),
          ),
          if (showClear)
            InkWell(
              key: const Key('searchClear'),
              customBorder: const CircleBorder(),
              onTap: widget.onClear,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: Icon(Icons.close, size: 15, color: AppColors.grey(500)),
              ),
            )
          else
            const SizedBox(width: 11),
        ],
      ),
    );
    return Container(
      height: ExploreSearchPill.height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        border: AppColors.cardBorder,
        boxShadow: AppColors.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            Expanded(
              child: widget.onTap == null
                  ? KeyedSubtree(
                      key: widget.fieldKey ?? const Key('searchField'),
                      child: field,
                    )
                  : InkWell(
                      key: widget.fieldKey,
                      customBorder: const StadiumBorder(),
                      onTap: widget.onTap,
                      child: field,
                    ),
            ),
            if (widget.trailing != null)
              Padding(
                padding: const EdgeInsets.only(left: 7),
                child: widget.trailing,
              ),
          ],
        ),
      ),
    );
  }
}

/// The filter pills of the tabs (Explore's categories and location,
/// Messages' All / Unread; the user's design, 2026-11-08): dark green with
/// white text when selected; otherwise white with a grey outline, or pale
/// green with a green outline ([tinted]: Explore's location).
class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final IconData? trailing;
  final bool tinted;
  final VoidCallback onTap;

  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailing,
    this.tinted = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppColors.brand;
    final iconColor = selected ? Colors.white : AppColors.brand;
    final paleGreen = AppColors.isDark
        ? AppColors.tint
        : const Color(0xFFEBF3DF);
    return Material(
      color: selected
          ? (AppColors.isDark ? AppColors.brandFill : const Color(0xFF0B411A))
          : (tinted ? paleGreen : AppColors.surface),
      shape: StadiumBorder(
        side: selected
            ? BorderSide.none
            : BorderSide(
                color: tinted
                    ? const Color(0xFFC9DDB9)
                    : const Color(0xFFC9D2C6),
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // About 24.5 tall (the plain pills) or 27 (with an icon).
          padding: icon == null
              ? const EdgeInsets.symmetric(horizontal: 13, vertical: 6)
              : const EdgeInsets.fromLTRB(13, 6.5, 12, 6.5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14.5, color: iconColor),
                const SizedBox(width: 7),
              ],
              // A very long name is cut with an ellipsis rather than
              // making one pill as wide as the screen.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w500,
                    fontSize: 10.5,
                    height: 1.2,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                Icon(trailing, size: 15, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
