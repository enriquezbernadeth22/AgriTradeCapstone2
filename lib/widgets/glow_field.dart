import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';

/// The app's form field (see AppTheme's FORMS section): a white pill
/// [AppTheme.formFieldHeight] tall with a light grey outline — icon, a thin
/// vertical divider, then the text. The outline turns green with a soft glow
/// only while the field has focus. Shared by every form (log in,
/// registration, Forgot Password, Change Password…), and matched by
/// AppTheme.formFieldDecoration for fields that need InputDecoration.
class GlowField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  // e.g. [AutofillHints.email] / [AutofillHints.password] — lets the OS's
  // own password manager (Google/iCloud) recognize and offer to save or
  // fill this field, instead of the app remembering anything itself.
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  // A fixed, non-editable label shown before the editable text — e.g.
  // "+63 " for a Philippines-only mobile number field.
  final String? prefixText;
  final bool autofocus;

  /// Shows the value, greyed, without letting it be edited or focused.
  final bool readOnly;

  /// A shorter field, with smaller text and icon (the Admin Portal's
  /// login, on a desktop screen).
  final bool compact;

  /// How round its corners are: a pill unless given (the Admin Portal's
  /// login uses rounded rectangles).
  final double radius;

  const GlowField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.autofillHints,
    this.inputFormatters,
    this.prefixText,
    this.autofocus = false,
    this.readOnly = false,
    this.compact = false,
    this.radius = AppTheme.pillRadius,
  });

  @override
  State<GlowField> createState() => _GlowFieldState();
}

class _GlowFieldState extends State<GlowField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focused != _focusNode.hasFocus) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  // Autofocus waits for the page's slide in to finish. Focusing at once
  // opens the keyboard during the slide, and the first time in an app run
  // the keyboard is slow to open: the page then showed up with no slide at
  // all (Forgot Password), and slid in only from the second time on.
  ModalRoute<Object?>? _route;
  bool _autofocusStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (!widget.autofocus || _autofocusStarted) return;
    _autofocusStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusOnceIn());
  }

  // Checked after each frame until the page is in. A new page's first frame
  // is built offstage (to measure heroes), and there its slide reads as
  // already finished, so that frame does not count.
  void _focusOnceIn() {
    if (!mounted) return;
    final route = _route;
    final entrance = route?.animation;
    final isIn =
        route == null ||
        entrance == null ||
        (!route.offstage && entrance.isCompleted);
    if (isIn) {
      if (!widget.readOnly) _focusNode.requestFocus();
      return;
    }
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _focusOnceIn())
      ..ensureVisualUpdate();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: AppTheme.glowFieldWrapper(
        focused: _focused,
        radius: widget.radius,
      ),
      foregroundDecoration: AppTheme.glowFieldOutline(
        focused: _focused,
        radius: widget.radius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppTheme.formFieldHeight,
        ),
        child: Row(
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: widget.compact ? 16 : 18,
                right: 12,
              ),
              child: Icon(
                widget.icon,
                color: AppTheme.formIconColor,
                size: widget.compact ? 18 : AppTheme.formIconSize,
              ),
            ),
            Container(
              height: widget.compact ? 18 : 22,
              width: 1,
              color: AppColors.hairline,
            ),
            if (widget.prefixText != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  widget.prefixText!,
                  style: TextStyle(
                    color: AppColors.brand,
                    fontSize: AppTheme.formTextSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Expanded(
              child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              readOnly: widget.readOnly,
              canRequestFocus: !widget.readOnly,
              enableInteractiveSelection: !widget.readOnly,
              style: widget.readOnly
                  ? TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppTheme.formTextSize,
                    )
                  : TextStyle(
                      fontSize:
                          widget.compact ? 13.5 : AppTheme.formTextSize,
                    ),
              keyboardType: widget.keyboardType,
              obscureText: widget.obscureText,
              textInputAction: widget.textInputAction,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              autofillHints: widget.autofillHints,
              inputFormatters: widget.inputFormatters,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: widget.compact
                    ? TextStyle(fontSize: 13.5, color: AppColors.grey())
                    : AppTheme.formHint(),
                isDense: widget.compact,
                suffixIcon: widget.suffix,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  vertical: widget.compact ? 11 : 12,
                  horizontal: 12,
                ),
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// GlowField's plate for a field built on InputDecoration (a TextField or a
/// dropdown whose decoration is AppTheme.formFieldDecoration or
/// formDropdownDecoration with onGlowPlate: true): while anything inside is
/// typed in or open, the same soft green glow as GlowField — and the Admin
/// login's field — shows around it.
class FormFieldGlow extends StatefulWidget {
  final Widget child;

  /// The field's corners: a pill for a text field, [AppTheme.dropdownRadius]
  /// for a dropdown.
  final double radius;

  const FormFieldGlow({
    super.key,
    required this.child,
    this.radius = AppTheme.pillRadius,
  });

  @override
  State<FormFieldGlow> createState() => _FormFieldGlowState();
}

class _FormFieldGlowState extends State<FormFieldGlow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Only watches the field inside; never takes focus itself.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: AppTheme.glowFieldWrapper(
          focused: _focused,
        ).copyWith(borderRadius: BorderRadius.circular(widget.radius)),
        child: widget.child,
      ),
    );
  }
}
