// The Export Report dialog: the choices on the left (the report's sections
// in two columns, every tick box alike, nothing shrunk to fit — a short
// window scrolls instead), and on the right a preview of the report those
// choices make, which follows every change.
import 'dart:convert';
import 'dart:typed_data';

import 'package:agritrade/screen/admin_dashboard_screen.dart';
import 'package:agritrade/screen/export_options_dialog.dart';
import 'package:agritrade/services/report_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A one-pixel PNG, standing in for a drawn page.
final Uint8List page = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class PreviewCalls {
  final List<ReportChoices> choices = [];
}

Future<PreviewCalls> pumpDialog(
  WidgetTester tester, {
  Size size = const Size(1366, 900),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final calls = PreviewCalls();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: Builder(
        builder: (context) => Theme(
          data: adminThemeData(context, AdminPalette.light),
          child: Scaffold(
            body: ExportOptionsDialog(
              palette: AdminPalette.light,
              loadCommodities: () async => ['Chicken', 'Corn', 'Eggplant'],
              loadPreview: (choices, {onPage}) async {
                calls.choices.add(choices);
                if (choices.format == ReportFormat.pdf) {
                  onPage?.call(page);
                  onPage?.call(page);
                  return ReportPreview(
                    format: choices.format,
                    pages: [page, page],
                  );
                }
                return ReportPreview(
                  format: choices.format,
                  sheets: const [
                    ReportSection(
                      title: 'Top-Selling Products',
                      headers: ['Product', 'Sold'],
                      rows: [
                        ['Eggplant (kg)', 12],
                        ['Corn (kg)', null],
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 600));
  return calls;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('the choices on the left, the preview of the report on the '
      'right', (tester) async {
    final calls = await pumpDialog(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Export Report'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Preview')).dx,
      greaterThan(tester.getTopRight(find.text('Export Report')).dx),
    );
    // The PDF's pages, built from the choices.
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.textContaining('2 pages'), findsOneWidget);
    expect(calls.choices, isNotEmpty);
    expect(calls.choices.last.sections, DashboardSection.values.toSet());
  });

  testWidgets('the sections sit in two columns, and every tick box is the '
      'same size and lined up', (tester) async {
    await pumpDialog(tester);
    final first = tester.getTopLeft(find.text('Accounts Summary'));
    final second = tester.getTopLeft(find.text('Buyers by Type'));
    expect(second.dy, first.dy); // side by side
    expect(second.dx, greaterThan(first.dx));
    final third = tester.getTopLeft(find.text('Transactions'));
    expect(third.dx, first.dx); // the next row, first column

    // "Certification & Wet Signature" is a tick box like the others: the
    // same 18px box at the same left edge, not a smaller icon.
    Rect boxBefore(String label) {
      final row = find.ancestor(
        of: find.text(label),
        matching: find.byType(Row),
      );
      final box = find.descendant(
        of: row.first,
        matching: find.byType(AnimatedContainer),
      );
      return tester.getRect(box.first);
    }

    final fixed = boxBefore('Certification & Wet Signature (always included)');
    final normal = boxBefore('Accounts Summary');
    expect(fixed.size, normal.size);
    expect(fixed.left, normal.left);
  });

  testWidgets('a short window scrolls the choices instead of shrinking them', (
    tester,
  ) async {
    await pumpDialog(tester, size: const Size(1366, 900));
    final tall = tester.getSize(find.text('Accounts Summary'));
    await pumpDialog(tester, size: const Size(1366, 560));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('Accounts Summary')), tall);
    expect(find.byType(FittedBox), findsNothing);
    // The buttons stay in view at the bottom.
    expect(find.text('Export'), findsOneWidget);
    expect(tester.getBottomLeft(find.text('Export')).dy, lessThan(560));
  });

  testWidgets('a change of choice redraws the preview', (tester) async {
    final calls = await pumpDialog(tester);
    final before = calls.choices.length;
    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(calls.choices.length, before + 1);
    expect(
      calls.choices.last.sections.contains(DashboardSection.transactions),
      isFalse,
    );
  });

  testWidgets('Excel shows its sheets and their first rows', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.text('Excel'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.textContaining('1 sheet'), findsOneWidget);
    expect(find.text('Eggplant (kg)'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('null'), findsNothing); // a blank cell stays blank
  });

  testWidgets('with nothing ticked the preview says so', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.text('Clear All'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('Nothing to preview'), findsOneWidget);
  });

  testWidgets('the Commodity list is a compact menu', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.text('All Commodities'));
    await tester.pumpAndSettle();
    final corn = find.ancestor(
      of: find.text('Corn').last,
      matching: find.byType(PopupMenuItem<int>),
    );
    expect(tester.getSize(corn).height, lessThanOrEqualTo(40));
    await tester.tap(find.text('Corn').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
  });

  testWidgets('a narrow window shows the choices alone', (tester) async {
    await pumpDialog(tester, size: const Size(700, 800));
    expect(tester.takeException(), isNull);
    expect(find.text('Export Report'), findsOneWidget);
    expect(find.text('Preview'), findsNothing);
  });
}
