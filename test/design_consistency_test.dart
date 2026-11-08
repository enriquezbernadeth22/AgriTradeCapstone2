// The mobile app's design rules, checked over its whole source, so a
// screen left behind when a rule changes is caught here, not by the panel:
// buttons are rounded rectangles (only "Continue with Google" is a pill),
// no text is too small to read, and white cards have AppTheme.cardRadius.
// When a rule is changed on purpose, change it here too.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The mobile app's own Dart files: not the Admin Portal, and not the
/// documents it writes (PDF / Excel reports, receipts).
List<File> mobileSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) {
      final p = f.path.replaceAll('\\', '/');
      return !RegExp(
        r'/admin_|export_options|pdf_report|report_export|excel_report|'
        r'order_receipt_service|verification_queue|app_localizations',
      ).hasMatch(p);
    })
    .toList();

String pathOf(File f) => f.path.replaceAll('\\', '/');

int lineAt(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset)).length + 1;

/// The text of the call that opens at [open] (an index of its "(").
String callAt(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    if (text[i] == '(') depth++;
    if (text[i] == ')' && --depth == 0) return text.substring(open, i + 1);
  }
  return text.substring(open);
}

void main() {
  test('buttons are rounded rectangles, not pills', () {
    // The pill button the user chose: Continue with Google (2026-11-07).
    const allowed = {'lib/widgets/login_form_fields.dart'};
    final found = <String>[];
    final button = RegExp(
      r'(ElevatedButton|OutlinedButton|FilledButton|TextButton)\.styleFrom\(',
    );
    for (final file in mobileSources()) {
      if (allowed.contains(pathOf(file))) continue;
      final text = file.readAsStringSync();
      for (final m in button.allMatches(text)) {
        final style = callAt(text, m.end - 1);
        final pill =
            style.contains('StadiumBorder') ||
            RegExp(r'shape:[^;]*?circular\((2\d|[3-9]\d)\)').hasMatch(style);
        if (pill) found.add('${pathOf(file)}:${lineAt(text, m.start)}');
      }
      for (final m in RegExp(
        r'WidgetStatePropertyAll\(StadiumBorder\(\)\)',
      ).allMatches(text)) {
        found.add('${pathOf(file)}:${lineAt(text, m.start)}');
      }
    }
    expect(found, isEmpty, reason: 'pill-shaped buttons: $found');
  });

  test('no text smaller than 9.5', () {
    // Not for reading: the tag drawn on the Log In picture, and the code
    // field's hidden input (its digits show in the boxes).
    const allowed = {
      'lib/widgets/login_hero.dart',
      'lib/widgets/otp_code_field.dart',
    };
    final found = <String>[];
    for (final file in mobileSources()) {
      if (allowed.contains(pathOf(file))) continue;
      final text = file.readAsStringSync();
      for (final m in RegExp(r'fontSize: (\d+(\.\d+)?)\b').allMatches(text)) {
        if (double.parse(m.group(1)!) < 9.5) {
          found.add('${pathOf(file)}:${lineAt(text, m.start)} ${m.group(0)}');
        }
      }
    }
    expect(found, isEmpty, reason: 'too small to read: $found');
  });

  test('white cards have the cards\' corners (AppTheme.cardRadius)', () {
    // Not cards: hint bubbles, badges, chips, the reaction bar, loading
    // plates, a search-history chip, the onboarding's look-alike screens.
    const allowed = [
      'coach_mark',
      'demand_badge',
      'message_reactions',
      'branded_loading',
      'chat_attachments',
      'public_location_preview',
      'onboarding',
      'buyer_search_screen',
      'app_theme',
      // Product Details' section cards are 20, from the user's picture of
      // 2026-11-08.
      'product_detail_screen',
    ];
    final found = <String>[];
    for (final file in mobileSources()) {
      final p = pathOf(file);
      if (allowed.any(p.contains)) continue;
      final text = file.readAsStringSync();
      for (final m in RegExp(r'BoxDecoration\(').allMatches(text)) {
        final body = callAt(text, m.end - 1);
        if (!RegExp(r'color: AppColors\.(surface|card)\b').hasMatch(body)) {
          continue;
        }
        final r = RegExp(r'BorderRadius\.circular\((\d+)\)').firstMatch(body);
        if (r == null) continue;
        final radius = int.parse(r.group(1)!);
        if (radius >= 12 && radius != 16) {
          found.add('$p:${lineAt(text, m.start)} radius $radius');
        }
      }
    }
    expect(found, isEmpty, reason: 'cards with their own corners: $found');
  });
}
