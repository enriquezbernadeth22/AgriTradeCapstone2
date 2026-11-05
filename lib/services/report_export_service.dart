import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screen/export_options_dialog.dart' show ReportFormat, DashboardSection;
import '../widgets/chart_capture_boundary.dart';
import 'audit_log_service.dart';
import 'csv_report_service.dart';
import 'dashboard_analytics_service.dart';
import 'excel_report_service.dart';
import 'historical_demand_service.dart';
import 'market_price_helpers.dart';
import 'market_report_sections.dart';
import 'pdf_report_service.dart';
import 'price_trend_service.dart';
import 'download_helper.dart';
import 'report_section.dart';

class ExportResult {
  final String filename;
  final List<String> missingDataSections;
  const ExportResult({required this.filename, required this.missingDataSections});
}

/// The records a report is made from, read once from Firestore. The Export
/// Report dialog reads them when it opens and reuses them for its preview
/// and the export, so changing an option does not read them again.
class ReportSourceData {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> users;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> completedOrders;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> marketPrices;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> products;
  final DateTime readAt;
  const ReportSourceData({
    required this.users,
    required this.completedOrders,
    required this.marketPrices,
    required this.products,
    required this.readAt,
  });
}

/// A report built in memory, before it is saved: the file itself and what
/// went into it.
class BuiltReport {
  final Uint8List bytes;
  final String filename;
  final String mimeType;
  final ReportFormat format;
  final List<ReportSection> sections;
  final List<String> missingDataSections;
  const BuiltReport({
    required this.bytes,
    required this.filename,
    required this.mimeType,
    required this.format,
    required this.sections,
    required this.missingDataSections,
  });
}

/// Orchestrates the Export Report dialog: fetches real Firestore data once
/// (not streams — this is a one-shot action), re-runs the exact same
/// DashboardAnalyticsService logic the live dashboard uses for whichever
/// date range was chosen, builds the sections for the chosen format,
/// captures chart images where relevant, triggers the browser download,
/// and logs the export to the Audit Log.
class ReportExportService {
  const ReportExportService._();

  static GlobalKey? _keyFor(DashboardSection s) => switch (s) {
        DashboardSection.salesByCategory => DashboardChartKeys.salesByCategory,
        DashboardSection.priceTrend => DashboardChartKeys.priceTrend,
        _ => null,
      };

  /// Reads the records every report is made from (completed orders only,
  /// as all analytics).
  static Future<ReportSourceData> loadData() async {
    final firestore = FirebaseFirestore.instance;
    final results = await Future.wait([
      firestore.collection('users').get(),
      firestore.collection('orders').where('status', isEqualTo: 'completed').get(),
      firestore.collection('market_prices').get(),
      firestore.collection('products').get(),
    ]);
    return ReportSourceData(
      users: results[0].docs,
      completedOrders: results[1].docs,
      marketPrices: results[2].docs,
      products: results[3].docs,
      readAt: DateTime.now(),
    );
  }

  /// Builds the report and saves it (the browser's download, or the PDF
  /// share/print sheet), then logs the export to the Audit Log. [data] is
  /// what the dialog already read; without it, the latest is read now.
  static Future<ExportResult> export({
    required ReportFormat format,
    required Set<DashboardSection> sections,
    required Set<String> selectedCommodities,
    // The one commodity the Admin chose; null for every commodity, including
    // products that are not on the price list.
    String? onlyCommodity,
    required DateTimeRange? range,
    required String reportTitle,
    required bool landscape,
    ReportPaper paper = ReportPaper.a4,
    required bool includeDataTables,
    required String notes,
    ReportSourceData? data,
    // Told what the export is doing at each step, to show the Admin.
    void Function(String step, double progress)? onProgress,
  }) async {
    if (format == ReportFormat.png) {
      return _exportPng(sections: sections, range: range);
    }
    final built = await build(
      format: format,
      sections: sections,
      selectedCommodities: selectedCommodities,
      onlyCommodity: onlyCommodity,
      range: range,
      reportTitle: reportTitle,
      landscape: landscape,
      paper: paper,
      includeDataTables: includeDataTables,
      notes: notes,
      data: data,
      onProgress: onProgress,
    );

    onProgress?.call('Saving the file…', 0.97);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (format == ReportFormat.pdf) {
      await PdfReportService.share(built.bytes, built.filename);
    } else {
      WebDownloadHelper.download(built.bytes, built.filename, built.mimeType);
    }

    final rangeLabel = _rangeLabel(range);
    AuditLogService.log(
      AuditAction.exportReport,
      'Exported the Dashboard Overview report (${_formatName(format)}), $rangeLabel, '
      'sections: ${sections.map((s) => s.label).join(', ')}.',
    );

    onProgress?.call('Export complete', 1);

    return ExportResult(filename: built.filename, missingDataSections: built.missingDataSections);
  }

  static String _rangeLabel(DateTimeRange? range) => range == null
      ? 'All time'
      : '${DateFormat('MMM d, y').format(range.start)} – ${DateFormat('MMM d, y').format(range.end)}';

  /// Builds the report in memory, exactly as [export] would save it, without
  /// saving or logging anything: the dialog's preview. PDF, Excel or CSV.
  static Future<BuiltReport> build({
    required ReportFormat format,
    required Set<DashboardSection> sections,
    required Set<String> selectedCommodities,
    String? onlyCommodity,
    required DateTimeRange? range,
    required String reportTitle,
    required bool landscape,
    ReportPaper paper = ReportPaper.a4,
    required bool includeDataTables,
    required String notes,
    ReportSourceData? data,
    void Function(String step, double progress)? onProgress,
  }) async {
    // Says what is happening and lets the screen draw it before the next
    // (possibly long, uninterrupted) step starts.
    Future<void> step(String message, double progress) async {
      onProgress?.call(message, progress);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }

    if (data == null) await step('Loading the latest data…', 0.08);
    final source = data ?? await loadData();
    final userDocs = source.users;
    final orders = source.completedOrders;
    final priceDocs = source.marketPrices;
    final products = source.products;
    final now = DateTime.now();
    final orderData = [for (final doc in orders) doc.data()];
    final productData = [for (final doc in products) doc.data()];

    final missing = <String>[];
    final reportSections = <ReportSection>[];
    final chartImages = <String, ({Uint8List rgba, int width, int height})>{};
    await step('Preparing the report…', 0.25);

    // Dashboard order, exactly as the live page renders it.
    final selectedSections = DashboardSection.values
        .where((section) => sections.contains(section))
        .toList();
    for (var sectionIndex = 0; sectionIndex < selectedSections.length; sectionIndex++) {
      final section = selectedSections[sectionIndex];

      final built = switch (section) {
        DashboardSection.accountsSummary => _accountsSummary(userDocs, now),
        DashboardSection.buyersByType => MarketReportSections.buyersByType(
          [for (final doc in userDocs) doc.data()],
        ),
        DashboardSection.transactions => _transactionsSummary(orders, range),
        DashboardSection.salesOverview => _salesOverview(orders, range),
        DashboardSection.marketDemand => MarketReportSections.marketDemand(
          orders: orderData,
          range: range,
          commodities: {?onlyCommodity},
        ),
        DashboardSection.salesByCategory => _salesByCategory(orders, products, range),
        DashboardSection.priceTrend =>
          _priceTrend(orders, priceDocs, selectedCommodities, now, range),
        DashboardSection.topSellingProducts => _topProducts(orders, range),
        DashboardSection.marketChangeAnalysis => MarketReportSections.marketChange(
          orders: orderData,
          products: productData,
          historical: await _historicalOnRecord(orderData, now),
          commodities: {?onlyCommodity},
          now: now,
        ),
        DashboardSection.demand => _demand(orders, range),
        DashboardSection.liveCommodityPrices => _livePrices(priceDocs),
      };
      reportSections.add(built);
      if (built.rows.isEmpty) missing.add(built.title);
      final preparedProgress = 0.3 + 0.42 * (sectionIndex + 1) / selectedSections.length;
      await step('Preparing ${built.title}…', preparedProgress);

      // A chart with nothing in it for this period is left out: a picture
      // of an empty card adds nothing, and each picture costs time.
      if (format == ReportFormat.pdf &&
          section.isChart &&
          built.rows.isNotEmpty) {
        final key = _keyFor(section);
        if (key != null) {
          await step('Capturing ${built.title}…', preparedProgress);
          final image = await ChartCaptureBoundary.captureRawFrom(key);
          if (image != null) chartImages[built.title] = image;
        }
      }
    }

    final keyFindings = _keyFindings(
      users: userDocs,
      orders: orders,
      products: products,
      priceDocs: priceDocs,
      range: range,
    );

    final rangeLabel = _rangeLabel(range);
    final adminName =
        FirebaseAuth.instance.currentUser?.displayName ?? FirebaseAuth.instance.currentUser?.email ?? 'Admin';
    final baseName = _fileBaseName(range);

    late final Uint8List bytes;
    late final String extension;
    late final String mimeType;

    await step(
      format == ReportFormat.pdf
          ? 'Building the PDF…'
          : 'Building the file…',
      0.84,
    );
    switch (format) {
      case ReportFormat.pdf:
        bytes = await PdfReportService.buildFullDashboardReport(
          title: reportTitle,
          adminName: adminName,
          generatedAt: now,
          dateRangeLabel: rangeLabel,
          notes: notes,
          landscape: landscape,
          paper: paper,
          includeDataTables: includeDataTables,
          keyFindings: keyFindings,
          sections: reportSections,
          rawChartImages: chartImages,
        );
        extension = 'pdf';
        mimeType = 'application/pdf';
      case ReportFormat.excel:
        // The findings go on the workbook's Summary sheet. Not in the CSV,
        // which stays the tables' data only.
        bytes = ExcelReportService.build(
          reportSections,
          title: reportTitle,
          period: rangeLabel,
          preparedBy: adminName,
          generatedAt: now,
          findings: keyFindings,
        );
        extension = 'xlsx';
        mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case ReportFormat.csv:
        final csv = CsvReportService.build(reportSections);
        bytes = csv.bytes;
        extension = csv.extension;
        mimeType = extension == 'zip' ? 'application/zip' : 'text/csv';
      case ReportFormat.png:
        throw StateError('handled above');
    }
    onProgress?.call(
      format == ReportFormat.pdf ? 'Finishing the PDF…' : 'Finishing the file…',
      0.93,
    );

    return BuiltReport(
      bytes: bytes,
      filename: 'AgriTrade_Analytics_$baseName.$extension',
      mimeType: mimeType,
      format: format,
      sections: reportSections,
      missingDataSections: missing,
    );
  }

  static Future<ExportResult> _exportPng({
    required Set<DashboardSection> sections,
    required DateTimeRange? range,
  }) async {
    final images = <String, Uint8List>{};
    final missing = <String>[];
    for (final section in sections.where((s) => s.isChart)) {
      final key = _keyFor(section);
      final image = key == null ? null : await ChartCaptureBoundary.captureFrom(key);
      if (image != null) {
        images[section.label] = image;
      } else {
        missing.add(section.label);
      }
    }

    final baseName = _fileBaseName(range);
    final String filename;
    if (images.isEmpty) {
      throw StateError('None of the selected charts could be captured — try again after they finish loading.');
    } else if (images.length == 1) {
      final entry = images.entries.first;
      filename = 'AgriTrade_${_fileSafe(entry.key)}_$baseName.png';
      WebDownloadHelper.download(entry.value, filename, 'image/png');
    } else {
      final archive = Archive();
      for (final entry in images.entries) {
        archive.addFile(ArchiveFile('${_fileSafe(entry.key)}.png', entry.value.length, entry.value));
      }
      final zipped = ZipEncoder().encode(archive);
      filename = 'AgriTrade_Charts_$baseName.zip';
      WebDownloadHelper.download(Uint8List.fromList(zipped ?? const []), filename, 'application/zip');
    }

    AuditLogService.log(
      AuditAction.exportReport,
      'Exported Dashboard chart images (PNG): ${sections.map((s) => s.label).join(', ')}.',
    );

    return ExportResult(filename: filename, missingDataSections: missing);
  }

  static String _fileSafe(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  static String _fileBaseName(DateTimeRange? range) {
    if (range == null) return DateFormat('yyyy-MM-dd').format(DateTime.now());
    final f = DateFormat('yyyy-MM-dd');
    return '${f.format(range.start)}_to_${f.format(range.end)}';
  }

  static String _formatName(ReportFormat f) => switch (f) {
        ReportFormat.pdf => 'PDF',
        ReportFormat.excel => 'Excel',
        ReportFormat.csv => 'CSV',
        ReportFormat.png => 'PNG',
      };

  // ============================================================
  // SECTION BUILDERS — each mirrors exactly what the live dashboard card
  // shows, via DashboardAnalyticsService, for the chosen [range] (null for
  // the snapshot sections that don't take one).
  // ============================================================

  /// A few plain sentences on what the period's figures say, for the top
  /// of the report: sales, the leading category and product, the
  /// farmer applications waiting, and the listing price furthest from its
  /// reference price. Built from the same DashboardAnalyticsService figures
  /// as the sections, so the summary and the tables always agree.
  static List<String> _keyFindings({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> priceDocs,
    required DateTimeRange? range,
  }) {
    final findings = <String>[];

    final total = DashboardAnalyticsService.platformTransactionTotal(orders, range: range);
    final count = DashboardAnalyticsService.completedOrderCount(orders, range: range);
    if (count == 0) {
      findings.add('No completed sales in this period.');
    } else {
      findings.add(
        'Completed sales reached ${formatPeso(total)} from $count '
        '${count == 1 ? 'order' : 'orders'}, an average of '
        '${formatPeso(total / count)} per order.',
      );

      final categories = DashboardAnalyticsService.categoryRevenue(orders, products, range: range);
      if (categories.isNotEmpty) {
        final top = categories.entries.reduce((a, b) => b.value > a.value ? b : a);
        final all = categories.values.fold<num>(0, (acc, v) => acc + v);
        findings.add(
          'Top category: ${top.key}, with ${formatPeso(top.value)} '
          '(${_share(top.value, all)} of sales).',
        );
      }

      final topProducts = DashboardAnalyticsService.topSellingProducts(orders, limit: 1, range: range);
      if (topProducts.isNotEmpty) {
        final p = topProducts.first;
        final parts = _productUnitParts(p.name);
        findings.add(
          'Most sold by quantity: ${formatStock(p.quantity, parts.unit)} '
          'of ${parts.product}, across ${p.orders} completed '
          '${p.orders == 1 ? 'order' : 'orders'}.',
        );
      }
    }

    final pending = DashboardAnalyticsService.pendingVerifications(users);
    findings.add(
      pending == 0
          ? 'No farmer applications are waiting for review.'
          : '$pending farmer ${pending == 1 ? 'application is' : 'applications are'} '
              'waiting for review.',
    );

    // The commodity whose active listings are priced furthest from the
    // Admin reference price, either way.
    ({String name, double average, double reference, String unit})? furthest;
    for (final doc in priceDocs) {
      final data = doc.data();
      if (data['isActive'] == false) continue;
      final reference = (data['baselinePrice'] as num?)?.toDouble() ?? 0;
      if (reference <= 0) continue;
      final name = (data['name'] ?? doc.id).toString();
      final average = computeLiveAverage(products, name);
      if (average == null) continue;
      if (furthest == null ||
          (average - reference).abs() / reference >
              (furthest.average - furthest.reference).abs() / furthest.reference) {
        furthest = (name: name, average: average, reference: reference, unit: (data['unit'] ?? '').toString());
      }
    }
    if (furthest != null) {
      final gap = (furthest.average - furthest.reference) / furthest.reference * 100;
      findings.add(
        gap.abs() < 0.05
            ? '${furthest.name} listings average '
                '${formatPriceWithUnit(furthest.average, furthest.unit)}, the same as '
                'its reference price.'
            : '${furthest.name} listings average '
                '${formatPriceWithUnit(furthest.average, furthest.unit)}, '
                '${gap.abs().toStringAsFixed(1)}% ${gap > 0 ? 'above' : 'below'} its '
                '${formatPriceWithUnit(furthest.reference, furthest.unit)} reference price '
                '(the largest gap among commodities).',
      );
    }
    return findings;
  }

  /// Account totals are as of the day the report is made, whatever range was
  /// chosen; the transaction value is for the chosen date range only.
  static ReportSection _accountsSummary(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    DateTime now,
  ) {
    final farmerCount = DashboardAnalyticsService.farmerCount(users);
    final buyerCount = DashboardAnalyticsService.buyerCount(users);
    final pending = DashboardAnalyticsService.pendingVerifications(users);
    final day = DateFormat('MMM d, y');
    return ReportSection(
      title: 'Accounts (as of ${day.format(now)})',
      headers: const ['Metric', 'Value'],
      rows: [
        ['Total Users', farmerCount + buyerCount],
        ['Farmers', farmerCount],
        ['Buyers', buyerCount],
        ['Pending Verifications', pending],
      ],
    );
  }

  static ReportSection _transactionsSummary(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    DateTimeRange? range,
  ) {
    final total = DashboardAnalyticsService.platformTransactionTotal(orders, range: range);
    return ReportSection(
      title: 'Transactions (${_periodLabel(range)})',
      headers: const ['Metric', 'Value'],
      rows: [
        ['Total Transaction Value', formatPeso(total)],
      ],
    );
  }

  // "Sep 16 – Oct 15, 2026" within one year, both years otherwise.
  static String _periodLabel(DateTimeRange? range) {
    if (range == null) return 'All time';
    final end = DateFormat('MMM d, y').format(range.end);
    final start = DateFormat(
      range.start.year == range.end.year ? 'MMM d' : 'MMM d, y',
    ).format(range.start);
    return '$start – $end';
  }

  static ReportSection _salesOverview(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    DateTimeRange? range,
  ) {
    if (range == null) {
      return const ReportSection(
        title: 'Sales Overview',
        headers: ['Period', 'Orders', 'Revenue'],
        rows: [],
      );
    }
    final start = _dateOnly(range.start);
    final end = _dateOnly(range.end);
    final count = (end.difference(start).inDays ~/ 7) + 1;
    final weekly = List.generate(
      count,
      (i) => (start: start.add(Duration(days: i * 7)), revenue: 0.0, orders: 0),
    );
    for (final doc in orders) {
      final data = doc.data();
      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      final date = _orderDate(data);
      if (date == null || date.isBefore(start) || date.isAfter(_dayEnd(end))) {
        continue;
      }
      final index = date.difference(start).inDays ~/ 7;
      final amount = data['total'];
      final value = amount is num
          ? amount.toDouble()
          : double.tryParse(amount?.toString() ?? '') ?? 0;
      weekly[index] = (
        start: weekly[index].start,
        revenue: weekly[index].revenue + value,
        orders: weekly[index].orders + 1,
      );
    }
    return ReportSection(
      title: 'Sales Overview',
      headers: const ['Period (Week)', 'Orders', 'Revenue'],
      rows: [
        for (var i = 0; i < weekly.length; i++)
          [
            _weeklyPeriodLabel(weekly[i].start, end),
            weekly[i].orders,
            formatPeso(weekly[i].revenue),
          ],
      ],
    );
  }

  static DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  static DateTime _dayEnd(DateTime date) => DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  static DateTime? _orderDate(Map<String, dynamic> data) {
    DateTime? dateOf(Object? value) => switch (value) {
          Timestamp timestamp => timestamp.toDate(),
          DateTime date => date,
          _ => null,
        };
    return dateOf(data['completedAt']) ??
        dateOf(data['updatedAt']) ??
        dateOf(data['createdAt']);
  }

  static String _weeklyPeriodLabel(DateTime start, DateTime selectedEnd) {
    final weekEnd = start.add(const Duration(days: 6));
    final end = weekEnd.isAfter(selectedEnd) ? selectedEnd : weekEnd;
    final sameYear = start.year == end.year;
    final left = DateFormat(sameYear ? 'MMM d' : 'MMM d, y').format(start);
    final right = DateFormat('MMM d, y').format(end);
    return '$left–$right';
  }

  // Imported records from the year of the first completed order on, as on
  // the dashboard. Only a report's seasonal note rests on them, so a failed
  // read leaves them out rather than stopping the export.
  static Future<List<HistoricalDemandRecord>> _historicalOnRecord(
    List<Map<String, dynamic>> orders,
    DateTime now,
  ) async {
    try {
      final firstYear = PriceTrendService.yearsOnRecord(orders, now).first;
      final records = await HistoricalDemandService.watch().first;
      return [
        for (final record in records)
          if (record.year >= firstYear) record,
      ];
    } catch (_) {
      return const [];
    }
  }

  static ReportSection _salesByCategory(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
    DateTimeRange? range,
  ) {
    final revenue = DashboardAnalyticsService.categoryRevenue(orders, products, range: range);
    final entries = revenue.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<num>(0, (acc, e) => acc + e.value);
    return ReportSection(
      title: 'Sales by Category',
      headers: const ['Category', 'Revenue', 'Share of Sales'],
      rows: [
        for (final e in entries) [e.key, formatPeso(e.value), _share(e.value, total)],
        if (entries.isNotEmpty) ['Total', formatPeso(total), '100%'],
      ],
    );
  }

  // [part] as a percentage of [whole]: "45.2%".
  static String _share(num part, num whole) =>
      whole <= 0 ? '—' : '${(part / whole * 100).toStringAsFixed(1)}%';

  static ReportSection _priceTrend(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> priceDocs,
    Set<String> selectedCommodities,
    DateTime now,
    DateTimeRange? range,
  ) {
    final rows = <List<Object?>>[];
    for (final doc in priceDocs) {
      final data = doc.data();
      final name = (data['name'] ?? doc.id).toString();
      if (!selectedCommodities.contains(name)) continue;
      final baseline = (data['baselinePrice'] as num?)?.toDouble() ?? 0;
      final weekly = DashboardAnalyticsService.weeklyAveragePrice(orders, name, now: now, range: range);
      // A commodity with no sale in any week of the period says nothing:
      // left out rather than listed as a column of "No data".
      if (weekly.every((price) => price == null)) continue;
      for (var i = 0; i < weekly.length; i++) {
        final price = weekly[i];
        final firstWeek = range == null
            ? DateTime(now.year, now.month, now.day).subtract(const Duration(days: 56))
            : DateTime(range.start.year, range.start.month, range.start.day);
        final periodEnd = range == null
            ? DateTime(now.year, now.month, now.day)
            : DateTime(range.end.year, range.end.month, range.end.day);
        rows.add([
          name,
          _weeklyPeriodLabel(firstWeek.add(Duration(days: i * 7)), periodEnd),
          price == null ? 'No data' : formatPeso(price),
          formatPeso(baseline),
        ]);
      }
    }
    return ReportSection(
      title: 'Price Trend vs. Baseline',
      headers: const ['Commodity', 'Period (Week)', 'Average Price', 'Baseline Price'],
      rows: rows,
    );
  }

  static ReportSection _topProducts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    DateTimeRange? range,
  ) {
    final products = DashboardAnalyticsService.topSellingProducts(orders, limit: 100, range: range);
    final total = products.fold<num>(0, (acc, p) => acc + p.revenue);
    return ReportSection(
      title: 'Top-Selling Products',
      headers: const ['Product', 'Unit', 'Completed Orders', 'Quantity Sold', 'Revenue', 'Share of Sales'],
      rows: [
        for (final p in products)
          [
            _productUnitParts(p.name).product,
            _productUnitParts(p.name).unit,
            p.orders,
            formatStock(p.quantity, _productUnitParts(p.name).unit),
            formatPeso(p.revenue),
            _share(p.revenue, total),
          ],
        // Quantities are in different units (kg, pieces, heads), so they
        // are not added up.
        if (products.isNotEmpty)
          [
            'Total',
            '—',
            products.fold<int>(0, (acc, p) => acc + p.orders),
            '—',
            formatPeso(total),
            '100%',
          ],
      ],
    );
  }

  static ({String product, String unit}) _productUnitParts(String label) {
    final match = RegExp(r'^(.*) \(([^()]*)\)$').firstMatch(label);
    if (match == null) return (product: label, unit: '');
    return (product: match.group(1)!, unit: match.group(2)!);
  }

  static ReportSection _demand(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    DateTimeRange? range,
  ) {
    final demand = DashboardAnalyticsService.topSellingProducts(
      orders,
      limit: orders.length,
      range: range,
    )..sort((a, b) {
        final byOrders = b.orders.compareTo(a.orders);
        return byOrders != 0 ? byOrders : b.revenue.compareTo(a.revenue);
      });
    final totalOrders = demand.fold<int>(0, (acc, product) => acc + product.orders);
    final totalRevenue = demand.fold<num>(0, (acc, product) => acc + product.revenue);
    return ReportSection(
      title: 'Demand',
      headers: const ['Product', 'Orders', 'Revenue', 'Share of Orders'],
      rows: [
        for (final product in demand)
          [
            product.name,
            product.orders,
            formatPeso(product.revenue),
            _share(product.orders, totalOrders),
          ],
        if (demand.isNotEmpty) ['Total', totalOrders, formatPeso(totalRevenue), '100%'],
      ],
    );
  }

  static ReportSection _livePrices(List<QueryDocumentSnapshot<Map<String, dynamic>>> priceDocs) {
    final prices = DashboardAnalyticsService.commodityPrices(priceDocs);
    return ReportSection(
      title: 'Live Commodity Prices',
      headers: const ['Commodity', 'Current Price', 'Previous Price', 'Change %', 'Last Updated'],
      rows: prices
          .map((p) => [
                p.name,
                formatPeso(p.currentPrice),
                p.previousPrice == null ? '—' : formatPeso(p.previousPrice!),
                p.changePct == null ? 'New' : '${p.changePct!.toStringAsFixed(1)}%',
                p.updatedAt == null ? '—' : DateFormat('MMM d, y').format(p.updatedAt!),
              ])
          .toList(),
    );
  }

}
