import 'package:flutter/material.dart';

import '../screen/admin_filter_controls.dart' show adminFont;

/// One page in the Admin Portal's navigation. A page with several views of
/// its own lists them as [children], which the sidebar shows as a
/// collapsible submenu under it.
///
/// [section] starts a new group of pages ("Main", "Moderation"): the
/// sidebar shows it as a small heading above this page, with a line above
/// every heading but the first.
class AdminSidebarEntry {
  final IconData icon;
  final String label;
  final List<String> children;
  final String? section;
  const AdminSidebarEntry(
    this.icon,
    this.label, {
    this.children = const [],
    this.section,
  });
}

/// The sidebar's colours (the user's design, 2026-11-10): the mobile app's
/// dark green bar, white text and icons, and the open page a solid golden
/// yellow pill with dark green on it.
class AdminSidebarColors {
  final Color background;
  // The text and icons of every page that isn't open.
  final Color foreground;
  // The open page's pill, and its icon and text.
  final Color activeBackground;
  final Color activeForeground;
  // The open submenu item's dot and text.
  final Color accent;
  // The small group headings ("MAIN", "MODERATION").
  final Color sectionLabel;
  // The lines between groups and above the account.
  final Color edge;
  // The "AgriTrade" name at the top (its "+" is [accent]).
  final Color brand;
  // The thin line along the upper part of the curved right edge.
  final Color curveAccent;
  // The page beside the sidebar, which shows where the edge curves in.
  final Color page;

  const AdminSidebarColors._({
    required this.background,
    required this.foreground,
    required this.activeBackground,
    required this.activeForeground,
    required this.accent,
    required this.sectionLabel,
    required this.edge,
    required this.brand,
    required this.curveAccent,
    required this.page,
  });

  static const light = AdminSidebarColors._(
    background: Color(0xFF0B4225),
    foreground: Colors.white,
    activeBackground: Color(0xFFF5BB24),
    activeForeground: Color(0xFF0B4225),
    accent: Color(0xFFF5BB24),
    sectionLabel: Color(0xE6FFFFFF),
    edge: Color(0x26FFFFFF),
    brand: Colors.white,
    curveAccent: Color(0xFFF5BB24),
    page: Color(0xFFFAF8F2),
  );

  // Dark Mode: a deeper forest green beside the charcoal page; the same
  // white text and golden yellow.
  static const dark = AdminSidebarColors._(
    background: Color(0xFF0A2E1B),
    foreground: Colors.white,
    activeBackground: Color(0xFFF5BB24),
    activeForeground: Color(0xFF0B4225),
    accent: Color(0xFFF5BB24),
    sectionLabel: Color(0xCCFFFFFF),
    edge: Color(0x1FFFFFFF),
    brand: Colors.white,
    curveAccent: Color(0xCCF5BB24),
    page: Color(0xFF111315),
  );

  /// The colours for the portal's theme at [context]: light or dark.
  static AdminSidebarColors of(BuildContext context) =>
      Theme.of(context).colorScheme.brightness == Brightness.dark
      ? dark
      : light;
}

/// The Admin Portal's navigation: the AgriTrade+
/// logo, name and "Admin Panel" on top, and the pages under it in groups
/// ([AdminSidebarEntry.section]), one row each. A page with
/// [AdminSidebarEntry.children] has a small chevron and a submenu.
///
/// The same widget is the full sidebar on a desktop window, the icon-only
/// rail on a tablet-sized one ([collapsed]) and the contents of the
/// navigation drawer on a phone-sized one — so the three can never list
/// different pages. The rail has no room for submenus: its icons open the
/// page, whose own tabs then do the rest.
class AdminSidebar extends StatefulWidget {
  final List<AdminSidebarEntry> entries;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// Which child of the selected entry is open, if it has children.
  final int? selectedChildIndex;

  /// A submenu item was chosen: the entry's index, then the child's.
  final void Function(int index, int childIndex)? onSelectChild;

  /// Pinned at the bottom under a thin divider (the Admin account). It
  /// stays put while the pages above it scroll.
  final Widget? footer;

  /// Icon-only rail: labels become tooltips.
  final bool collapsed;

  /// Opens or closes the sidebar. When set, the expanded sidebar has a
  /// sidebar button beside the logo, and on the rail the logo turns into
  /// that button while the pointer is over it.
  final VoidCallback? onToggleCollapsed;

  /// The keyboard shortcut for [onToggleCollapsed], shown in its tooltip.
  final String? toggleShortcut;

  /// The right edge flows in a shallow curve below the top (the user's
  /// design, 2026-11-10). Off in the drawer, where it lies over the page.
  final bool curved;

  const AdminSidebar({
    super.key,
    required this.entries,
    required this.selectedIndex,
    required this.onSelect,
    this.selectedChildIndex,
    this.onSelectChild,
    this.footer,
    this.collapsed = false,
    this.onToggleCollapsed,
    this.toggleShortcut,
    this.curved = true,
  });

  static const double expandedWidth = 256;
  static const double collapsedWidth = 72;

  @override
  State<AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends State<AdminSidebar> {
  // The entries whose submenu is open. Every submenu starts open, so all
  // the sub-pages are in view without a click.
  late final Set<int> _expanded = {
    for (var i = 0; i < widget.entries.length; i++)
      if (widget.entries[i].children.isNotEmpty) i,
  };

  @override
  void didUpdateWidget(AdminSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Going to a page (from anywhere) opens its submenu.
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _expanded.add(widget.selectedIndex);
    }
    if (widget.collapsed != oldWidget.collapsed) _brandHovered = false;
  }

  void _toggle(int index) => setState(() {
    if (!_expanded.remove(index)) _expanded.add(index);
  });

  // The parent row itself: opens its page, or — already there — folds its
  // submenu away or back out.
  void _onParentTap(int index) {
    if (index == widget.selectedIndex) {
      _toggle(index);
    } else {
      setState(() => _expanded.add(index));
      widget.onSelect(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.collapsed;
    final entries = widget.entries;
    final colors = AdminSidebarColors.of(context);
    // How far the curved edge comes in: room the rows keep clear of.
    final curve = !widget.curved ? 0.0 : (collapsed ? 5.0 : 10.0);
    final top = MediaQuery.paddingOf(context).top + _brandHeight;
    return Material(
      color: Colors.transparent,
      child: CustomPaint(
        painter: _SidebarShapePainter(colors: colors, top: top, curve: curve),
        child: SizedBox(
          width: collapsed
              ? AdminSidebar.collapsedWidth
              : AdminSidebar.expandedWidth,
          child: Padding(
            padding: EdgeInsets.only(right: curve),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _brand(),
                // The pages scroll on their own if the window is too short
                // for them; the brand above stays put.
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < entries.length; i++) ...[
                          ..._sectionStart(i),
                          ..._entry(i),
                        ],
                      ],
                    ),
                  ),
                ),
                if (widget.footer != null) ...[
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 12,
                    endIndent: 12,
                    color: colors.edge,
                  ),
                  SafeArea(top: false, child: widget.footer!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // The heading of a group of pages, above its first page: a line first
  // (except for the very first group), then the name in small capitals.
  // The rail has no room for the name, so it keeps only the line.
  List<Widget> _sectionStart(int i) {
    final section = widget.entries[i].section;
    if (section == null) return const [];
    final colors = AdminSidebarColors.of(context);
    final first = !widget.entries.take(i).any((e) => e.section != null);
    return [
      if (!first)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1, thickness: 1, color: colors.edge),
        ),
      if (!widget.collapsed)
        Padding(
          padding: EdgeInsets.fromLTRB(12, first ? 8 : 4, 12, 8),
          child: Text(
            section.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: adminFont(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: colors.sectionLabel,
            ),
          ),
        ),
    ];
  }

  List<Widget> _entry(int i) {
    final entry = widget.entries[i];
    final selected = i == widget.selectedIndex;
    final colors = AdminSidebarColors.of(context);
    final hasChildren = entry.children.isNotEmpty && !widget.collapsed;
    if (!hasChildren) {
      return [
        _AdminSidebarItem(
          icon: entry.icon,
          label: entry.label,
          colors: colors,
          selected: selected,
          collapsed: widget.collapsed,
          onTap: () => widget.onSelect(i),
        ),
      ];
    }

    final open = _expanded.contains(i);
    return [
      _AdminSidebarItem(
        icon: entry.icon,
        label: entry.label,
        colors: colors,
        selected: selected,
        collapsed: false,
        expanded: open,
        onTap: () => _onParentTap(i),
        // The chevron on its own only folds the submenu, without leaving
        // the current page.
        onToggle: () => _toggle(i),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: open
            ? Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < entry.children.length; j++)
                      _AdminSidebarSubItem(
                        label: entry.children[j],
                        colors: colors,
                        selected: selected && j == widget.selectedChildIndex,
                        onTap: () => widget.onSelectChild?.call(i, j),
                      ),
                  ],
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    ];
  }

  // The pointer is over the rail's logo, which then shows the sidebar
  // button in its place.
  bool _brandHovered = false;

  /// How tall the top of the sidebar, with the logo, is.
  static const double _brandHeight = kAdminHeaderHeight;

  // The top of the sidebar, on its own white: the logo, "AgriTrade+" in
  // bold dark green with "Admin Panel" under it, and the sidebar button at
  // the end. On the rail, the logo alone, which turns into the sidebar
  // button while hovered.
  Widget _brand() {
    final collapsed = widget.collapsed;
    final colors = AdminSidebarColors.of(context);
    final onToggle = widget.onToggleCollapsed;
    final top = MediaQuery.paddingOf(context).top;
    final logo = SizedBox(
      width: 40,
      height: 40,
      // The file has a wide transparent margin round the artwork, so it is
      // drawn larger than the box to fill it.
      child: OverflowBox(
        maxWidth: 72,
        maxHeight: 48,
        child: Image.asset(
          'assets/images/logo.png',
          width: 72,
          height: 48,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, _, _) =>
              Icon(Icons.eco_rounded, color: colors.brand, size: 26),
        ),
      ),
    );

    final Widget content;
    if (collapsed) {
      content = Center(
        child: onToggle == null
            ? logo
            : MouseRegion(
                onEnter: (_) => setState(() => _brandHovered = true),
                onExit: (_) => setState(() => _brandHovered = false),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: _brandHovered
                        ? _SidebarToggleButton(
                            color: colors.foreground,
                            tooltip: 'Open sidebar',
                            shortcut: widget.toggleShortcut,
                            onTap: () {
                              setState(() => _brandHovered = false);
                              onToggle();
                            },
                          )
                        : logo,
                  ),
                ),
              ),
      );
    } else {
      content = Padding(
        padding: EdgeInsets.fromLTRB(16, 0, onToggle == null ? 16 : 10, 0),
        child: Row(
          children: [
            // Logo and name open the first page (the Analytics
            // Dashboard), like a website's logo.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: widget.entries.first.label,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => widget.onSelect(0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        logo,
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  text: 'AgriTrade',
                                  children: [
                                    TextSpan(
                                      text: '+',
                                      style: TextStyle(color: colors.accent),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: adminFont(
                                  fontSize: 18,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: colors.brand,
                                ),
                              ),
                              Text(
                                'Admin Panel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: adminFont(
                                  fontSize: 11.5,
                                  height: 1.3,
                                  fontWeight: FontWeight.w500,
                                  color: colors.foreground.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (onToggle != null) ...[
              const SizedBox(width: 4),
              _SidebarToggleButton(
                color: colors.foreground,
                tooltip: 'Close sidebar',
                shortcut: widget.toggleShortcut,
                onTap: onToggle,
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: top),
      child: SizedBox(height: _brandHeight, child: content),
    );
  }
}

/// The square button that opens or closes the sidebar, with the sidebar
/// icon on it in [color] and a tooltip naming its keyboard shortcut. A
/// faint tint of [color] on hover.
class _SidebarToggleButton extends StatefulWidget {
  final Color color;
  final String tooltip;
  final String? shortcut;
  final VoidCallback onTap;

  const _SidebarToggleButton({
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.shortcut,
  });

  @override
  State<_SidebarToggleButton> createState() => _SidebarToggleButtonState();
}

class _SidebarToggleButtonState extends State<_SidebarToggleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final shortcut = widget.shortcut;
    return Tooltip(
      richMessage: TextSpan(
        text: widget.tooltip,
        children: [
          if (shortcut != null)
            TextSpan(
              text: '   $shortcut',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
            ),
        ],
      ),
      waitDuration: const Duration(milliseconds: 300),
      child: Semantics(
        button: true,
        label: widget.tooltip,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: _hovered ? 0.12 : 0),
                borderRadius: BorderRadius.circular(kAdminSidebarRowRadius),
              ),
              child: CustomPaint(
                size: const Size(20, 18),
                painter: _SidebarIconPainter(color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded window with a narrow panel on its left: the usual "sidebar"
/// sign.
class _SidebarIconPainter extends CustomPainter {
  final Color color;
  const _SidebarIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7;
    final box = Rect.fromLTWH(1, 1.5, size.width - 2, size.height - 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      paint,
    );
    final x = box.left + box.width * 0.36;
    canvas.drawLine(Offset(x, box.top), Offset(x, box.bottom), paint);
  }

  @override
  bool shouldRepaint(_SidebarIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// One row of the sidebar. Transparent until hovered (light grey) or
/// selected (a dark green rounded block, white icon and text, inset from
/// both sides of the sidebar). Both fade over 160 ms.
///
/// With [onToggle], the row is a submenu's parent: it ends in a small
/// chevron that points down while the submenu is [expanded].
class _AdminSidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final AdminSidebarColors colors;
  final bool selected;
  final bool collapsed;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final bool expanded;

  const _AdminSidebarItem({
    required this.icon,
    required this.label,
    required this.colors,
    required this.selected,
    required this.collapsed,
    this.onTap,
    this.onToggle,
    this.expanded = false,
  });

  @override
  State<_AdminSidebarItem> createState() => _AdminSidebarItemState();
}

class _AdminSidebarItemState extends State<_AdminSidebarItem> {
  bool _hovered = false;

  static const double _height = 42;
  static const double _iconSize = 19;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final color = widget.selected
        ? colors.activeForeground
        : colors.foreground.withValues(alpha: _hovered ? 1 : 0.85);

    final Widget content = widget.collapsed
        ? Center(
            child: Icon(widget.icon, size: _iconSize, color: color),
          )
        : Row(
            children: [
              Icon(widget.icon, size: _iconSize, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: adminFont(
                    fontSize: 13,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
              if (widget.onToggle != null)
                Semantics(
                  button: true,
                  label: widget.expanded
                      ? 'Collapse ${widget.label}'
                      : 'Expand ${widget.label}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onToggle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      child: AnimatedRotation(
                        turns: widget.expanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );

    Widget item = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: _height,
            padding: widget.collapsed
                ? EdgeInsets.zero
                : EdgeInsets.only(
                    left: 12,
                    right: widget.onToggle != null ? 4 : 12,
                  ),
            decoration: BoxDecoration(
              color: widget.selected
                  ? colors.activeBackground
                  : colors.foreground.withValues(alpha: _hovered ? 0.08 : 0),
              // The open page: a solid golden yellow pill.
              borderRadius: BorderRadius.circular(kAdminSidebarRowRadius),
            ),
            child: content,
          ),
        ),
      ),
    );

    // A submenu's parent keeps its chevron reachable on its own.
    if (widget.onToggle == null) {
      item = Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        onTap: widget.onTap,
        excludeSemantics: true,
        child: item,
      );
    }
    // On the rail the label is only a tooltip.
    if (widget.collapsed) {
      item = Tooltip(message: widget.label, child: item);
    }
    return item;
  }
}

/// One submenu row: a small dot and smaller text, indented under its
/// parent. The open one is semi-bold in dark green, with a green dot.
class _AdminSidebarSubItem extends StatefulWidget {
  final String label;
  final AdminSidebarColors colors;
  final bool selected;
  final VoidCallback onTap;

  const _AdminSidebarSubItem({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_AdminSidebarSubItem> createState() => _AdminSidebarSubItemState();
}

class _AdminSidebarSubItemState extends State<_AdminSidebarSubItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final colors = widget.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: 30,
            margin: const EdgeInsets.only(left: 30, bottom: 1),
            padding: const EdgeInsets.only(left: 12, right: 10),
            decoration: BoxDecoration(
              color: colors.foreground.withValues(alpha: _hovered ? 0.08 : 0),
              borderRadius: BorderRadius.circular(kAdminSidebarRowRadius),
            ),
            child: Row(
              children: [
                // The marker: solid green on the open view.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? colors.accent
                        : colors.foreground.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: adminFont(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? colors.accent
                          : colors.foreground.withValues(
                              alpha: _hovered ? 0.92 : 0.72,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How round a sidebar row's corners are: pills (the open page's golden
/// yellow pill, the user's design of 2026-11-10).
const double kAdminSidebarRowRadius = 999;

/// The height of the portal's dark green top bar, and of the sidebar's top
/// beside it, so the two read as one band.
const double kAdminHeaderHeight = 64;

/// The sidebar's shape: dark green, its right edge straight beside the top
/// bar and then flowing in a shallow curve down the side (the mobile app's
/// header wave turned on its side), with a thin golden yellow line along
/// the upper part of that curve only. Where the edge curves in, the page
/// colour shows.
class _SidebarShapePainter extends CustomPainter {
  final AdminSidebarColors colors;
  final double top;
  final double curve;

  const _SidebarShapePainter({
    required this.colors,
    required this.top,
    required this.curve,
  });

  // The curved edge from (width, top) down to the bottom, added to [path]
  // (which must already be at its start).
  void _edge(Path path, Size size) {
    final w = size.width;
    final a = curve;
    final h = size.height - top;
    path
      ..cubicTo(w, top + h * 0.12, w - a, top + h * 0.2, w - a, top + h * 0.34)
      ..cubicTo(
        w - a,
        top + h * 0.48,
        w - a * 0.25,
        top + h * 0.56,
        w - a * 0.25,
        top + h * 0.7,
      )
      ..cubicTo(
        w - a * 0.25,
        top + h * 0.84,
        w - a * 0.75,
        top + h * 0.92,
        w - a * 0.75,
        size.height,
      );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final green = Paint()..color = colors.background;
    if (curve <= 0 || size.height <= top + 40) {
      canvas.drawRect(Offset.zero & size, green);
      return;
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.page);
    final shape = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, top);
    _edge(shape, size);
    shape
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(shape, green);

    // The golden line: the upper part of the curve, fading out.
    final edge = Path()..moveTo(size.width, top);
    _edge(edge, size);
    final metric = edge.computeMetrics().first;
    final part = metric.extractPath(0, metric.length * 0.5);
    final end = top + (size.height - top) * 0.5;
    canvas.drawPath(
      part.shift(const Offset(-0.75, 0)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.curveAccent,
            colors.curveAccent,
            colors.curveAccent.withValues(alpha: 0),
          ],
          stops: const [0, 0.65, 1],
        ).createShader(Rect.fromLTRB(0, top, size.width, end)),
    );
  }

  @override
  bool shouldRepaint(_SidebarShapePainter old) =>
      old.colors != colors || old.top != top || old.curve != curve;
}
