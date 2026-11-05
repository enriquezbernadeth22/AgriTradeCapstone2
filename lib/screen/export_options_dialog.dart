import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/pdf_report_service.dart' show ReportPaper;
import '../services/report_export_service.dart';
import '../services/report_section.dart';
import 'admin_dashboard_screen.dart'
    show AdminPalette, AdminThemeScope, adminButtonShape;
import 'admin_filter_controls.dart';

enum ReportFormat { pdf, excel, csv, png }

enum DateRangePreset {
  last7Days,
  last30Days,
  thisMonth,
  lastMonth,
  thisYear,
  custom,
}

/// One selectable Analytics Dashboard section, in the order the dashboard
/// itself renders them — [isChart] marks the 2 sections actually backed by
/// an fl_chart widget (the only ones PNG export can capture; everything
/// else is a data/list/table section). Sales Overview is a table only: the
/// dashboard has no total-sales chart of its own.
enum DashboardSection {
  accountsSummary('Accounts Summary', isChart: false),
  buyersByType('Buyers by Type', isChart: false),
  transactions('Transactions', isChart: false),
  salesOverview('Sales Overview', isChart: false),
  marketDemand('Market Demand', isChart: false),
  salesByCategory('Sales by Category', isChart: true),
  priceTrend('Price Trend vs. Baseline', isChart: true),
  topSellingProducts('Top-Selling Products', isChart: false),
  marketChangeAnalysis('Market Change Analysis', isChart: false),
  demand('Demand', isChart: false),
  liveCommodityPrices('Live Commodity Prices', isChart: false);

  final String label;
  final bool isChart;
  const DashboardSection(this.label, {required this.isChart});
}

/// The file formats and date ranges the dialog offers. The export service
/// still understands the others (CSV, PNG, last 7 days); they are simply
/// no longer offered.
const List<ReportFormat> kOfferedReportFormats = [
  ReportFormat.pdf,
  ReportFormat.excel,
];
const List<DateRangePreset> kOfferedDatePresets = [
  DateRangePreset.last30Days,
  DateRangePreset.thisMonth,
  DateRangePreset.lastMonth,
  DateRangePreset.thisYear,
];

const String _reportTitle = 'AgriTrade+ Analytics Report';

const _prefsKeyFormat = 'export_last_format';
// A new key when sections are added, so they start ticked.
const _prefsKeySections = 'export_last_sections_v3';
const _prefsKeyPreset = 'export_last_preset';
const _prefsKeyOrientation = 'export_last_orientation';
const _prefsKeyPaper = 'export_last_paper';
const _prefsKeyIncludeTables = 'export_last_include_tables';

/// Everything chosen in the dialog, as the preview and the export use it.
class ReportChoices {
  final ReportFormat format;
  final Set<DashboardSection> sections;

  /// Null for every commodity.
  final String? commodity;
  final Set<String> availableCommodities;
  final DateTimeRange range;
  final bool landscape;
  final ReportPaper paper;
  final bool includeDataTables;

  const ReportChoices({
    required this.format,
    required this.sections,
    required this.commodity,
    required this.availableCommodities,
    required this.range,
    required this.landscape,
    required this.paper,
    required this.includeDataTables,
  });
}

/// What the preview shows: the PDF's pages as pictures, or — for Excel —
/// the sheets with their rows. Both come from the report itself, built
/// from the same data the export uses.
class ReportPreview {
  final ReportFormat format;
  final List<Uint8List> pages;
  final List<ReportSection> sheets;
  final List<String> missingDataSections;

  const ReportPreview({
    required this.format,
    this.pages = const [],
    this.sheets = const [],
    this.missingDataSections = const [],
  });
}

/// Builds the preview for [choices]. [onPage] is told each PDF page as it
/// is drawn, so the first pages show before the last ones are ready.
typedef ReportPreviewLoader =
    Future<ReportPreview> Function(
      ReportChoices choices, {
      void Function(Uint8List page)? onPage,
    });

/// The Export Report dialog: the choices on the left, and on the right a
/// preview of the very report they make (its pages, or its sheets), which
/// follows every change. Export then saves that report.
class ExportOptionsDialog extends StatefulWidget {
  final AdminPalette palette;

  /// The commodities to choose from (tests); the price list by default.
  final Future<List<String>> Function()? loadCommodities;

  /// Builds the preview (tests); the real report by default.
  final ReportPreviewLoader? loadPreview;

  const ExportOptionsDialog({
    super.key,
    required this.palette,
    this.loadCommodities,
    this.loadPreview,
  });

  /// From this window width up, the preview sits beside the choices; below
  /// it, the dialog shows the choices alone.
  static const double previewFrom = 900;

  /// The width of the choices' column.
  static const double choicesWidth = 440;

  @override
  State<ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<ExportOptionsDialog> {
  ReportFormat _format = ReportFormat.pdf;
  final Set<DashboardSection> _sections = {...DashboardSection.values};
  // Null = every commodity.
  String? _commodity;
  DateRangePreset _preset = DateRangePreset.last30Days;
  DateTimeRange? _customRange;
  bool _landscape = false;
  ReportPaper _paper = ReportPaper.a4;
  bool _includeDataTables = true;

  bool _loadingPrefs = true;
  bool _exporting = false;
  // What the export is doing right now, shown while it runs.
  String _step = '';
  double _progress = 0;
  String? _error;
  String? _successMessage;

  List<String> _availableCommodities = [];

  // The records the report is made from, read once when the dialog opens
  // and used by both the preview and the export.
  Future<ReportSourceData>? _data;

  // The preview: the latest one built, whether a newer one is on its way,
  // and what went wrong with the last try.
  ReportPreview? _preview;
  final List<Uint8List> _pagesSoFar = [];
  bool _previewBusy = false;
  String? _previewError;
  int _previewRun = 0;
  Timer? _previewDebounce;

  @override
  void initState() {
    super.initState();
    _loadCommodities();
    _loadLastChoices();
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCommodities() async {
    try {
      final names =
          await (widget.loadCommodities?.call() ?? _priceListCommodities());
      if (mounted) setState(() => _availableCommodities = names);
      _schedulePreview();
    } catch (_) {
      // The dropdown just stays on "All Commodities" — never blocks the
      // dialog on this best-effort lookup.
    }
  }

  static Future<List<String>> _priceListCommodities() async {
    final snap = await FirebaseFirestore.instance
        .collection('market_prices')
        .get();
    return snap.docs.map((d) => (d.data()['name'] ?? d.id).toString()).toList()
      ..sort();
  }

  Future<void> _loadLastChoices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final formatName = prefs.getString(_prefsKeyFormat);
      final sectionNames = prefs.getStringList(_prefsKeySections);
      final presetName = prefs.getString(_prefsKeyPreset);
      final orientationLandscape = prefs.getBool(_prefsKeyOrientation);
      final paperName = prefs.getString(_prefsKeyPaper);
      final includeTables = prefs.getBool(_prefsKeyIncludeTables);

      if (!mounted) return;
      setState(() {
        // A format or range remembered from before that is no longer
        // offered falls back to the default.
        _format = kOfferedReportFormats.firstWhere(
          (f) => f.name == formatName,
          orElse: () => ReportFormat.pdf,
        );
        if (sectionNames != null && sectionNames.isNotEmpty) {
          _sections
            ..clear()
            ..addAll(
              DashboardSection.values.where(
                (s) => sectionNames.contains(s.name),
              ),
            );
        }
        _preset = kOfferedDatePresets.firstWhere(
          (p) => p.name == presetName,
          orElse: () => DateRangePreset.last30Days,
        );
        if (orientationLandscape != null) _landscape = orientationLandscape;
        _paper = ReportPaper.values.firstWhere(
          (p) => p.name == paperName,
          orElse: () => ReportPaper.a4,
        );
        if (includeTables != null) _includeDataTables = includeTables;
        _loadingPrefs = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPrefs = false);
    }
    _schedulePreview();
  }

  Future<void> _saveLastChoices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyFormat, _format.name);
      await prefs.setStringList(
        _prefsKeySections,
        _sections.map((s) => s.name).toList(),
      );
      await prefs.setString(_prefsKeyPreset, _preset.name);
      await prefs.setBool(_prefsKeyOrientation, _landscape);
      await prefs.setString(_prefsKeyPaper, _paper.name);
      await prefs.setBool(_prefsKeyIncludeTables, _includeDataTables);
    } catch (_) {
      // Not remembering the choice next time is a fine failure mode —
      // never blocks the export itself.
    }
  }

  DateTimeRange _resolveRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last30 = DateTimeRange(
      start: today.subtract(const Duration(days: 29)),
      end: today,
    );
    switch (_preset) {
      case DateRangePreset.last7Days:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        );
      case DateRangePreset.last30Days:
        return last30;
      case DateRangePreset.thisMonth:
        return DateTimeRange(
          start: DateTime(today.year, today.month, 1),
          end: today,
        );
      case DateRangePreset.lastMonth:
        final firstOfThisMonth = DateTime(today.year, today.month, 1);
        final lastMonthEnd = firstOfThisMonth.subtract(const Duration(days: 1));
        return DateTimeRange(
          start: DateTime(lastMonthEnd.year, lastMonthEnd.month, 1),
          end: lastMonthEnd,
        );
      case DateRangePreset.thisYear:
        return DateTimeRange(start: DateTime(today.year, 1, 1), end: today);
      case DateRangePreset.custom:
        return _customRange ?? last30;
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showAdminDateRangePicker(
      context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _customRange ?? _resolveRange(),
      palette: widget.palette,
    );
    if (picked == null) return;
    _change(() {
      _customRange = picked;
      _preset = DateRangePreset.custom;
    });
  }

  ReportChoices get _choices => ReportChoices(
    format: _format,
    sections: {..._sections},
    commodity: _commodity,
    availableCommodities: _availableCommodities.toSet(),
    range: _resolveRange(),
    landscape: _landscape,
    paper: _paper,
    includeDataTables: _includeDataTables,
  );

  // A choice changed: the dialog redraws, and the preview follows a moment
  // later (so a few quick clicks build it once).
  void _change(VoidCallback update) {
    setState(update);
    _schedulePreview();
  }

  void _schedulePreview() {
    if (!mounted || _loadingPrefs) return;
    _previewDebounce?.cancel();
    _previewDebounce = Timer(
      const Duration(milliseconds: 450),
      _refreshPreview,
    );
  }

  Future<void> _refreshPreview() async {
    if (!mounted) return;
    final run = ++_previewRun;
    if (_sections.isEmpty) {
      setState(() {
        _preview = null;
        _pagesSoFar.clear();
        _previewBusy = false;
        _previewError = null;
      });
      return;
    }
    setState(() {
      _previewBusy = true;
      _previewError = null;
      _pagesSoFar.clear();
    });
    try {
      final loader = widget.loadPreview ?? _realPreview;
      final preview = await loader(
        _choices,
        onPage: (page) {
          if (mounted && run == _previewRun) {
            setState(() => _pagesSoFar.add(page));
          }
        },
      );
      // A newer choice has started its own preview meanwhile.
      if (!mounted || run != _previewRun) return;
      setState(() {
        _preview = preview;
        _previewBusy = false;
      });
    } catch (e) {
      if (!mounted || run != _previewRun) return;
      setState(() {
        _previewBusy = false;
        _previewError = 'The preview could not be made: $e';
      });
    }
  }

  // The real report, built as Export would save it, drawn page by page.
  Future<ReportPreview> _realPreview(
    ReportChoices choices, {
    void Function(Uint8List page)? onPage,
  }) async {
    final data = await (_data ??= ReportExportService.loadData());
    final built = await ReportExportService.build(
      format: choices.format,
      sections: choices.sections,
      onlyCommodity: choices.commodity,
      selectedCommodities: choices.commodity == null
          ? choices.availableCommodities
          : {choices.commodity!},
      range: choices.range,
      reportTitle: _reportTitle,
      landscape: choices.landscape,
      paper: choices.paper,
      includeDataTables: choices.includeDataTables,
      notes: '',
      data: data,
    );
    if (choices.format != ReportFormat.pdf) {
      return ReportPreview(
        format: choices.format,
        sheets: built.sections,
        missingDataSections: built.missingDataSections,
      );
    }
    final pages = <Uint8List>[];
    // Small pictures of the pages: enough to read the headings and see
    // the layout, and quick to draw.
    await for (final page in Printing.raster(built.bytes, dpi: 56)) {
      final png = await page.toPng();
      pages.add(png);
      onPage?.call(png);
    }
    return ReportPreview(
      format: choices.format,
      pages: pages,
      missingDataSections: built.missingDataSections,
    );
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _step = 'Starting…';
      _progress = 0;
      _error = null;
      _successMessage = null;
    });

    try {
      final choices = _choices;
      final result = await ReportExportService.export(
        format: choices.format,
        sections: choices.sections,
        onlyCommodity: choices.commodity,
        selectedCommodities: choices.commodity == null
            ? choices.availableCommodities
            : {choices.commodity!},
        range: choices.range,
        reportTitle: _reportTitle,
        landscape: choices.landscape,
        paper: choices.paper,
        includeDataTables: choices.includeDataTables,
        notes: '',
        // The records the preview was made from, when they are in.
        data: _data == null ? null : await _data,
        onProgress: (step, progress) {
          if (mounted) {
            setState(() {
              _step = step;
              _progress = progress.clamp(0.0, 1.0).toDouble();
            });
          }
        },
      );
      await _saveLastChoices();
      if (!mounted) return;
      if (result.missingDataSections.isNotEmpty) {
        setState(() {
          _successMessage =
              'Exported ${result.filename}. No data for this period: ${result.missingDataSections.join(', ')}.';
        });
      } else {
        setState(() => _successMessage = 'Exported ${result.filename}.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    final screen = MediaQuery.sizeOf(context);
    final withPreview = screen.width >= ExportOptionsDialog.previewFrom;
    // As tall as the window allows, up to a comfortable height; what does
    // not fit scrolls inside the choices' column — nothing is shrunk.
    final height = math.min(screen.height - 32, 760.0);

    return AdminThemeScope(
      palette: c,
      child: Dialog(
        backgroundColor: c.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kAdminPopupRadius),
          side: BorderSide(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: withPreview ? 1080 : ExportOptionsDialog.choicesWidth,
          height: height,
          child: _loadingPrefs
              ? const Center(child: AdminLoadingBar())
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: ExportOptionsDialog.choicesWidth,
                      child: _choicesColumn(c),
                    ),
                    if (withPreview) ...[
                      VerticalDivider(width: 1, thickness: 1, color: c.border),
                      Expanded(child: _previewColumn(c)),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  // The left side: the title, every choice (scrolling if the window is
  // short), and the export's progress and buttons pinned at the bottom.
  Widget _choicesColumn(AdminPalette c) {
    final primary = adminActionColor(c);
    final onPrimary = adminOnActionColor(c);
    final canExport = _sections.isNotEmpty && !_exporting;
    const inner = ExportOptionsDialog.choicesWidth - 44;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 2),
          child: Text(
            'Export Report',
            style: TextStyle(
              color: c.heading,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(c, 'File Format'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final format in kOfferedReportFormats)
                      _choice(
                        c,
                        label: format == ReportFormat.pdf ? 'PDF' : 'Excel',
                        selected: _format == format,
                        onTap: () => _change(() => _format = format),
                      ),
                  ],
                ),

                _label(
                  c,
                  'Report Content',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _link(
                        c,
                        'Select All',
                        c.textPrimary,
                        () => _change(
                          () => _sections.addAll(DashboardSection.values),
                        ),
                      ),
                      const SizedBox(width: 14),
                      _link(
                        c,
                        'Clear All',
                        c.textSecondary,
                        () => _change(_sections.clear),
                      ),
                    ],
                  ),
                ),
                // Two columns, so the list takes half the height.
                Wrap(
                  spacing: 12,
                  children: [
                    for (final section in DashboardSection.values)
                      SizedBox(
                        width: (inner - 12) / 2,
                        child: _check(
                          c,
                          label: section.label,
                          value: _sections.contains(section),
                          onChanged: (checked) => _change(() {
                            if (checked) {
                              _sections.add(section);
                            } else {
                              _sections.remove(section);
                            }
                          }),
                        ),
                      ),
                  ],
                ),
                if (_format == ReportFormat.pdf)
                  _check(
                    c,
                    label: 'Certification & Wet Signature (always included)',
                    value: true,
                  ),

                _label(c, 'Commodity'),
                AdminPillDropdown<String?>(
                  width: inner,
                  value: _availableCommodities.contains(_commodity)
                      ? _commodity
                      : null,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All Commodities'),
                    ),
                    for (final name in _availableCommodities)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (value) => _change(() => _commodity = value),
                ),

                _label(c, 'Date Range'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in kOfferedDatePresets)
                      _choice(
                        c,
                        label: _presetLabel(preset),
                        selected: _preset == preset,
                        onTap: () => _change(() => _preset = preset),
                      ),
                    _choice(
                      c,
                      label:
                          _preset == DateRangePreset.custom &&
                              _customRange != null
                          ? '${DateFormat('MMM d').format(_customRange!.start)} – ${DateFormat('MMM d, y').format(_customRange!.end)}'
                          : 'Custom',
                      selected: _preset == DateRangePreset.custom,
                      onTap: _pickCustomRange,
                    ),
                  ],
                ),

                if (_format == ReportFormat.pdf) ...[
                  // The paper beside the heading, so choosing it takes no
                  // room of its own.
                  _label(c, 'PDF Options', trailing: _paperPicker(c)),
                  // The page and the tables on one row; the tables under
                  // them if the row is too narrow.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _choice(
                        c,
                        label: 'Portrait',
                        selected: !_landscape,
                        radio: true,
                        onTap: () => _change(() => _landscape = false),
                      ),
                      _choice(
                        c,
                        label: 'Landscape',
                        selected: _landscape,
                        radio: true,
                        onTap: () => _change(() => _landscape = true),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _check(
                          c,
                          label: 'Include data tables',
                          value: _includeDataTables,
                          expand: false,
                          onChanged: (checked) =>
                              _change(() => _includeDataTables = checked),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: c.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_exporting) ...[
                Text(
                  _step,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 4,
                    backgroundColor: c.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation(primary),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Please keep this window open. A report with charts can '
                  'take a little while.',
                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                ),
                const SizedBox(height: 10),
              ],
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: c.red, fontSize: 12.5)),
                const SizedBox(height: 10),
              ],
              if (_successMessage != null) ...[
                Text(
                  _successMessage!,
                  style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _exporting
                        ? null
                        : () => Navigator.of(context).pop(),
                    // Tertiary: near-black text alone; the main button is
                    // the dialog's only green.
                    style: TextButton.styleFrom(
                      foregroundColor: c.textPrimary,
                      shape: adminButtonShape,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: canExport ? _export : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: onPrimary,
                      // Stays green while exporting, so its "Exporting…"
                      // can be read.
                      disabledBackgroundColor: _exporting
                          ? primary.withValues(alpha: 0.75)
                          : c.surfaceAlt,
                      disabledForegroundColor: _exporting
                          ? onPrimary
                          : c.textMuted,
                      shape: adminButtonShape,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontFamily: kAdminFontFamily,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(_exporting ? 'Exporting…' : 'Export'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // The right side: the preview of the report the choices make.
  Widget _previewColumn(AdminPalette c) {
    final preview = _preview;
    final pages = _previewBusy ? _pagesSoFar : (preview?.pages ?? const []);
    final pdf = _format == ReportFormat.pdf;
    final caption = _sections.isEmpty
        ? ''
        : pdf
        ? '${_paper.label} · ${_landscape ? 'Landscape' : 'Portrait'}'
              '${pages.isEmpty || _previewBusy ? '' : ' · ${pages.length} ${pages.length == 1 ? 'page' : 'pages'}'}'
        : (preview == null || _previewBusy
              ? 'Excel workbook'
              : 'Excel workbook · ${preview.sheets.length} '
                    '${preview.sheets.length == 1 ? 'sheet' : 'sheets'}');

    final Widget body;
    if (_sections.isEmpty) {
      body = _previewNote(
        c,
        Icons.checklist_rounded,
        'Nothing to preview',
        'Tick at least one section under Report Content.',
      );
    } else if (_previewError != null) {
      body = _previewNote(
        c,
        Icons.error_outline_rounded,
        'No preview',
        '$_previewError\nThe export itself can still be tried.',
      );
    } else if (pdf && pages.isNotEmpty) {
      body = ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: pages.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, i) => Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Image.memory(
                pages[i],
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Page ${i + 1}',
              style: TextStyle(color: c.textSecondary, fontSize: 11.5),
            ),
          ],
        ),
      );
    } else if (!pdf && preview != null && !_previewBusy) {
      body = ListView(
        padding: const EdgeInsets.all(20),
        children: [for (final sheet in preview.sheets) _sheetPreview(c, sheet)],
      );
    } else {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AdminLoadingBar(width: 180),
            const SizedBox(height: 10),
            Text(
              'Making the preview…',
              style: TextStyle(color: c.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      );
    }

    final missing = preview?.missingDataSections ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
          child: Row(
            children: [
              Text(
                'Preview',
                style: TextStyle(
                  color: c.heading,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                ),
              ),
              if (_previewBusy && pages.isNotEmpty)
                Text(
                  'Updating…',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
            ],
          ),
        ),
        if (missing.isNotEmpty && !_previewBusy)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
            child: Text(
              'No data for this period: ${missing.join(', ')}.',
              style: TextStyle(color: c.textSecondary, fontSize: 12),
            ),
          ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(kAdminFieldRadius),
              border: Border.all(color: c.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: body,
          ),
        ),
      ],
    );
  }

  Widget _previewNote(
    AdminPalette c,
    IconData icon,
    String title,
    String message,
  ) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: c.textSecondary),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    ),
  );

  // One Excel sheet: its name and its first rows, as the workbook has them.
  Widget _sheetPreview(AdminPalette c, ReportSection sheet) {
    const shown = 5;
    final rows = sheet.rows.take(shown).toList();
    TextStyle cell({bool head = false}) => TextStyle(
      color: head ? c.textPrimary : c.textSecondary,
      fontSize: 11.5,
      fontWeight: head ? FontWeight.w700 : FontWeight.w400,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.grid_on_rounded, size: 15, color: c.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sheet.title,
                  style: TextStyle(
                    color: c.heading,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${sheet.rows.length} ${sheet.rows.length == 1 ? 'row' : 'rows'}',
                style: TextStyle(color: c.textMuted, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text('No data for this period.', style: cell())
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                children: [
                  TableRow(
                    children: [
                      for (final h in sheet.headers)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 2, 18, 4),
                          child: Text(h, style: cell(head: true)),
                        ),
                    ],
                  ),
                  for (final row in rows)
                    TableRow(
                      children: [
                        for (var i = 0; i < sheet.headers.length; i++)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 2, 18, 2),
                            child: Text(
                              i < row.length ? '${row[i] ?? ''}' : '',
                              style: cell(),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          if (sheet.rows.length > shown)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '+ ${sheet.rows.length - shown} more in the file',
                style: TextStyle(color: c.textMuted, fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }

  // A section's heading, with room above it.
  Widget _label(AdminPalette c, String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: c.heading,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _link(AdminPalette c, String text, Color color, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );

  // A pill to choose one of a few options, in black and white: outlined in
  // black when chosen. With [radio] it carries a radio dot, for an
  // either/or pair.
  Widget _choice(
    AdminPalette c, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool radio = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.fromLTRB(radio ? 12 : 16, 8, 16, 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? c.textPrimary : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (radio) ...[
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: selected ? c.textPrimary : c.textMuted,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? c.textPrimary : c.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // "Paper: A4 ▾", opening the sizes to choose from: in black and white,
  // the one chosen in bold.
  Widget _paperPicker(AdminPalette c) {
    final text = TextStyle(
      fontFamily: kAdminFontFamily,
      color: c.textPrimary,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
    );
    return AdminGreyMenu(
      child: PopupMenuButton<ReportPaper>(
        tooltip: 'Paper size',
        initialValue: _paper,
        color: c.surface,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kAdminPopupRadius),
          side: BorderSide(color: c.border),
        ),
        onSelected: (paper) => _change(() => _paper = paper),
        itemBuilder: (context) => [
          for (final paper in ReportPaper.values)
            PopupMenuItem(
              value: paper,
              height: 38,
              child: Text(
                paper.description,
                style: text.copyWith(
                  fontSize: 13,
                  fontWeight: paper == _paper
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
        ],
        // No taller than the heading beside it.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Paper: ',
                style: text.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(_paper.label, style: text),
              Icon(Icons.expand_more_rounded, size: 16, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  // A square tick box and its label, every one the same size and lined up
  // the same way. [expand]: the label takes the rest of the row; false
  // sizes it to the label, for a row it shares. Without [onChanged] it is
  // fixed (always included): ticked, greyed, and not clickable.
  Widget _check(
    AdminPalette c, {
    required String label,
    required bool value,
    ValueChanged<bool>? onChanged,
    bool expand = true,
  }) {
    final fixed = onChanged == null;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: fixed ? c.textSecondary : c.textPrimary,
        fontSize: 13,
      ),
    );
    final box = fixed ? c.textMuted : c.textPrimary;
    return Semantics(
      checked: value,
      enabled: !fixed,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: fixed ? null : () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              // Square with a slight rounding, as every tick box in the
              // portal: filled with a small white tick when ticked, an empty
              // grey outline when not.
              SizedBox(
                width: 22,
                height: 22,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: value ? box : Colors.transparent,
                      border: value
                          ? null
                          : Border.all(color: c.textMuted, width: 1.4),
                    ),
                    child: value
                        ? Icon(Icons.check_rounded, size: 12, color: c.surface)
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              expand ? Expanded(child: text) : text,
            ],
          ),
        ),
      ),
    );
  }

  String _presetLabel(DateRangePreset p) => switch (p) {
    DateRangePreset.last7Days => 'Last 7 Days',
    DateRangePreset.last30Days => 'Last 30 Days',
    DateRangePreset.thisMonth => 'This Month',
    DateRangePreset.lastMonth => 'Last Month',
    DateRangePreset.thisYear => 'This Year',
    DateRangePreset.custom => 'Custom',
  };
}
