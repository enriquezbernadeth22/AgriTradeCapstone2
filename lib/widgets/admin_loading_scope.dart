import 'package:flutter/widgets.dart';

/// Connects a page's existing loading indicators to the Admin shell.
///
/// The shell uses the signals to show one small progress line for a slow tab
/// load, then briefly completes it when that page's data arrives.
class AdminLoadingScope extends InheritedWidget {
  final int page;
  final void Function(int page, Object indicator, bool loading) onChanged;

  const AdminLoadingScope({
    super.key,
    required this.page,
    required this.onChanged,
    required super.child,
  });

  void report(Object indicator, bool loading) =>
      onChanged(page, indicator, loading);

  static AdminLoadingScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminLoadingScope>();

  @override
  bool updateShouldNotify(AdminLoadingScope oldWidget) =>
      page != oldWidget.page || onChanged != oldWidget.onChanged;
}
