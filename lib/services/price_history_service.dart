import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import '../screen/export_options_dialog.dart' show ReportFormat;
import 'audit_log_service.dart';
import 'csv_report_service.dart';
import 'download_helper.dart';
import 'excel_report_service.dart';
import 'market_price_helpers.dart';
import 'pdf_report_service.dart';
import 'report_section.dart';

/// One reference price the Admin set for a commodity in Price Management,
/// with the price it replaced.
class PriceHistoryEntry {
  final String commodity;
  final String category;
  final String unit;
  final double price;

  /// The commodity's reference price just before this one (by effective
  /// date); null for its first.
  final double? previous;
  final DateTime effectiveDate;

  /// When it was saved, and by whom (the Admin's email).
  final DateTime? recordedAt;
  final String recordedBy;

  /// False while the commodity is archived.
  final bool isActive;

  const PriceHistoryEntry({
    required this.commodity,
    required this.category,
    required this.unit,
    required this.price,
    required this.previous,
    required this.effectiveDate,
    required this.recordedAt,
    required this.recordedBy,
    required this.isActive,
  });

  /// The change from [previous], in pesos; null for a first price.
  double? get change => previous == null ? null : price - previous!;

  /// The change from [previous], in percent; null for a first price.
  double? get changePercent => previous == null || previous == 0
      ? null
      : (price - previous!) / previous! * 100;

  /// "+₱10.00 (+5.0%)", "−₱4.00 (−2.0%)", "No change" or "First price".
  String get changeLabel {
    final amount = change;
    if (amount == null) return 'First price';
    if (amount.abs() < 0.005) return 'No change';
    final sign = amount > 0 ? '+' : '−';
    final percent = changePercent;
    return '$sign${formatPeso(amount.abs())}'
        '${percent == null ? '' : ' ($sign${percent.abs().toStringAsFixed(1)}%)'}';
  }
}

/// Price Management → History: every reference price the Admin has set,
/// read from each commodity's `market_prices/{id}/history` (one entry per
/// effective date — see _recordReferencePrice), with what it changed from,
/// and its export.
class PriceHistoryService {
  const PriceHistoryService._();

  /// Every commodity's price history, newest effective date first.
  static Future<List<PriceHistoryEntry>> load(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> marketPrices,
  ) async {
    final perCommodity = await Future.wait([
      for (final doc in marketPrices)
        doc.reference.collection('history').get().then((snap) {
          final data = doc.data();
          final name = (data['name'] ?? doc.id).toString();
          final category = normalizeCategory(
            data['category'] ?? categoryOfCommodity(name),
          );
          final ordered =
              [
                for (final entry in snap.docs)
                  if (entry.data()['effectiveDate'] is Timestamp &&
                      entry.data()['price'] is num)
                    entry.data(),
              ]..sort(
                (a, b) => (a['effectiveDate'] as Timestamp).compareTo(
                  b['effectiveDate'] as Timestamp,
                ),
              );
          double? previous;
          final entries = <PriceHistoryEntry>[];
          for (final entry in ordered) {
            final price = (entry['price'] as num).toDouble();
            final unit = (entry['unit'] ?? data['unit'] ?? '').toString();
            entries.add(
              PriceHistoryEntry(
                commodity: name,
                category: category,
                unit: unit.isEmpty ? unitForCommodity(name) : unit,
                price: price,
                previous: previous,
                effectiveDate: (entry['effectiveDate'] as Timestamp).toDate(),
                recordedAt: (entry['recordedAt'] as Timestamp?)?.toDate(),
                recordedBy: (entry['recordedBy'] ?? '').toString(),
                isActive: data['isActive'] != false,
              ),
            );
            previous = price;
          }
          return entries;
        }),
    ]);
    return [for (final list in perCommodity) ...list]..sort((a, b) {
      final byDate = b.effectiveDate.compareTo(a.effectiveDate);
      return byDate != 0 ? byDate : a.commodity.compareTo(b.commodity);
    });
  }

  static final DateFormat _day = DateFormat('MMM d, y');
  static final DateFormat _moment = DateFormat('MMM d, y · h:mm a');

  /// The history as a report table, in the order given.
  static ReportSection section(List<PriceHistoryEntry> entries) =>
      ReportSection(
        title: 'Reference Price History',
        headers: const [
          'Effective Date',
          'Commodity',
          'Category',
          'Unit',
          'Price',
          'Previous Price',
          'Change',
          'Recorded',
          'Recorded By',
        ],
        columnWeights: const [1.1, 1.2, 1.1, 0.8, 0.9, 0.9, 1.2, 1.4, 1.6],
        rows: [
          for (final e in entries)
            [
              _day.format(e.effectiveDate),
              e.isActive ? e.commodity : '${e.commodity} (archived)',
              e.category.isEmpty ? '—' : e.category,
              e.unit,
              formatPeso(e.price),
              e.previous == null ? '—' : formatPeso(e.previous!),
              e.changeLabel,
              e.recordedAt == null ? '—' : _moment.format(e.recordedAt!),
              e.recordedBy.isEmpty ? '—' : e.recordedBy,
            ],
        ],
      );

  /// Builds the history file in [format] and hands it over (the share
  /// sheet for a PDF, a download otherwise); logs it in the Audit Log.
  /// [scopeLabel] says what is in it ("All commodities", "Search: corn").
  /// Returns the file's name.
  static Future<String> export(
    List<PriceHistoryEntry> entries, {
    required ReportFormat format,
    required String scopeLabel,
  }) async {
    const title = 'Reference Price History';
    final now = DateTime.now();
    final user = FirebaseAuth.instance.currentUser;
    final preparedBy = user?.displayName ?? user?.email ?? 'Admin';
    final sections = [section(entries)];
    final period = entries.isEmpty
        ? 'No entries'
        : '${_day.format(entries.last.effectiveDate)} – '
              '${_day.format(entries.first.effectiveDate)}';
    final count =
        '${NumberFormat('#,##0').format(entries.length)} '
        '${entries.length == 1 ? 'price change' : 'price changes'}';
    final base =
        'AgriTrade_Price_History_${DateFormat('yyyy-MM-dd').format(now)}';

    late final Uint8List bytes;
    late final String filename;
    switch (format) {
      case ReportFormat.pdf:
        bytes = await PdfReportService.buildFullDashboardReport(
          title: title,
          kind: 'Price Management Report',
          adminName: preparedBy,
          generatedAt: now,
          dateRangeLabel: period,
          notes: '',
          landscape: true,
          includeDataTables: true,
          keyFindings: const [],
          sections: sections,
          particulars: [
            ('Effective dates', period),
            ('Included', scopeLabel),
            ('Entries', count),
            ('Date generated', _moment.format(now)),
          ],
        );
        filename = '$base.pdf';
        await PdfReportService.share(bytes, filename);
      case ReportFormat.excel:
        bytes = ExcelReportService.build(
          sections,
          title: title,
          period: period,
          preparedBy: preparedBy,
          generatedAt: now,
          findings: const [],
          details: [('Included', scopeLabel), ('Entries', count)],
        );
        filename = '$base.xlsx';
        WebDownloadHelper.download(
          bytes,
          filename,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      case ReportFormat.csv:
      case ReportFormat.png:
        final csv = CsvReportService.build(sections);
        bytes = csv.bytes;
        filename = '$base.${csv.extension}';
        WebDownloadHelper.download(
          bytes,
          filename,
          filename.endsWith('.zip') ? 'application/zip' : 'text/csv',
        );
    }

    AuditLogService.log(
      AuditAction.exportReport,
      'Exported the Reference Price History '
      '(${format.name.toUpperCase()}), $count; $scopeLabel.',
    );
    return filename;
  }
}
