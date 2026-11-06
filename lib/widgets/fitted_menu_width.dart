import 'package:flutter/material.dart';

/// The width for a dropdown's open list that fits its longest option, so a
/// list of short options ("Crop Farmer", "Livestock Farmer") opens as a
/// small panel instead of stretching across the whole field. Pass it as
/// `menuWidth` on a [DropdownButton] or [DropdownButtonFormField].
///
/// [labels] are the options exactly as shown, [style] the dropdown's own
/// `style` (what the options are drawn in). [extra] is room for anything
/// beside the text, such as an icon. Never narrower than [minWidth], and
/// never wider than the screen allows; a long option still gets the room
/// it needs.
double fittedMenuWidth(
  BuildContext context,
  Iterable<String> labels, {
  TextStyle? style,
  double extra = 0,
  double minWidth = 120,
}) {
  // What a dropdown draws its options in when it is given no style.
  final textStyle =
      (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).merge(
        style,
      );
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
  var longest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    if (painter.width > longest) longest = painter.width;
    painter.dispose();
  }
  // Each option has 16 px on both sides in the open list; a few more keep
  // the last letter from ever being cut by rounding.
  const itemPadding = 16.0 * 2;
  const slack = 8.0;
  final screenLimit = MediaQuery.sizeOf(context).width - 32;
  final width = longest + itemPadding + slack + extra;
  return width.clamp(minWidth, screenLimit < minWidth ? minWidth : screenLimit);
}

/// A form dropdown (like [DropdownButtonFormField]: [decoration] around it,
/// the whole field opens it) whose open list is only as wide as its
/// longest option ([fittedMenuWidth]) instead of the whole field.
/// [DropdownButtonFormField] has no way to set that width, so this is the
/// same field built from [InputDecorator] and [DropdownButton].
///
/// [labels] are the options' texts as shown, in any order.
class FittedDropdownField<T> extends StatefulWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final List<String> labels;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  final Widget? hint;
  final Widget? icon;
  final Color? dropdownColor;
  final BorderRadius? borderRadius;

  const FittedDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.labels,
    required this.onChanged,
    required this.decoration,
    this.style,
    this.hint,
    this.icon,
    this.dropdownColor,
    this.borderRadius,
  });

  @override
  State<FittedDropdownField<T>> createState() => _FittedDropdownFieldState<T>();
}

class _FittedDropdownFieldState<T> extends State<FittedDropdownField<T>> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    super.dispose();
  }

  // A tap on the field around the dropdown (its icon, its padding) opens it
  // too, as on a DropdownButtonFormField.
  void _open() {
    final target = _focus.context;
    if (target != null) Actions.maybeInvoke(target, const ActivateIntent());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onChanged == null ? null : _open,
      child: InputDecorator(
        decoration: widget.decoration,
        isEmpty: widget.value == null && widget.hint == null,
        isFocused: _focus.hasFocus,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: widget.value,
            items: widget.items,
            hint: widget.hint,
            onChanged: widget.onChanged,
            focusNode: _focus,
            isDense: true,
            isExpanded: true,
            icon: widget.icon,
            style: widget.style,
            dropdownColor: widget.dropdownColor,
            borderRadius: widget.borderRadius,
            menuWidth: fittedMenuWidth(
              context,
              widget.labels,
              style: widget.style,
            ),
          ),
        ),
      ),
    );
  }
}
