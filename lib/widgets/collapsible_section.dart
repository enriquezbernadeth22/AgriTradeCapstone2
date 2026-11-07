import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../theme/app_colors.dart';

/// A section that collapses to its heading: the heading, any [trailing]
/// controls (shown only while open, such as a month), and a chevron on the
/// right; tapping the heading or the chevron opens or closes it, and the
/// [body] grows and shrinks into place. Open to begin with
/// ([initiallyOpen]).
class CollapsibleSection extends StatefulWidget {
  final Widget heading;
  final Widget? trailing;
  final Widget body;
  final bool initiallyOpen;

  const CollapsibleSection({
    super.key,
    required this.heading,
    required this.body,
    this.trailing,
    this.initiallyOpen = true,
  });

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _open = widget.initiallyOpen;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          // As tall with or without the trailing controls, so nothing moves.
          constraints: const BoxConstraints(minHeight: 36),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  expanded: _open,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    child: widget.heading,
                  ),
                ),
              ),
              if (_open && widget.trailing != null) widget.trailing!,
              IconButton(
                key: const Key('sectionToggle'),
                tooltip: _open ? tl('Collapse') : tl('Expand'),
                onPressed: _toggle,
                visualDensity: VisualDensity.compact,
                icon: AnimatedRotation(
                  turns: _open ? 0 : 0.5,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _open ? widget.body : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
