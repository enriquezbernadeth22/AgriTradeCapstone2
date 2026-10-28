import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/pdf_report_service.dart' show ReportPaper;
import '../services/report_export_service.dart';
import '../widgets/busy_indicator.dart';
import 'admin_dashboard_screen.dart' show AdminPalette, adminButtonShape;
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
  kpiSummary('KPI Summary', isChart: false),
  salesOverview('Sales Overview', isChart: false),
  salesByCategory('Sales by Category', isChart: true),
  priceTrend('Price Trend vs. Baseline', isChart: true),
  topSellingProducts('Top-Selling Products', isChart: false),
  demandByBarangay('Demand by Barangay', isChart: false),
  newRegistrations('New Registrations', isChart: false),
  verificationStatus('Verification Status', isChart: false),
  liveCommodityPrices('Live Commodity Prices', isChart: false),
  recentVerificationRequests('Recent Verification Requests', isChart: false);

  final String label;
  final bool isChart;
  const DashboardSection(this.label, {required this.isChart});
}

/// What the Export Report dialog offers, in place of one checkbox per
/// dashboard section: four groups, each standing for the sections listed.
enum ReportGroup {
  overview('Overview Summary', {DashboardSection.kpiSummary}),
  sales('Sales Analytics', {
    DashboardSection.salesOverview,
    DashboardSection.salesByCategory,
    DashboardSection.topSellingProducts,
  }),
  demandAndMarket('Demand & Market Analytics', {
    DashboardSection.priceTrend,
    DashboardSection.demandByBarangay,
    DashboardSection.liveCommodityPrices,
  }),
  verification('Verification & User Summary', {
    DashboardSection.newRegistrations,
    DashboardSection.verificationStatus,
    DashboardSection.recentVerificationRequests,
  });

  final String label;
  final Set<DashboardSection> sections;
  const ReportGroup(this.label, this.sections);
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
const _prefsKeyGroups = 'export_last_groups';
const _prefsKeyPreset = 'export_last_preset';
const _prefsKeyOrientation = 'export_last_orientation';
const _prefsKeyPaper = 'export_last_paper';
const _prefsKeyIncludeTables = 'export_last_include_tables';

class ExportOptionsDialog extends StatefulWidget {
  final AdminPalette palette;
  const ExportOptionsDialog({super.key, required this.palette});

  @override
  State<ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<ExportOptionsDialog> {
  ReportFormat _format = ReportFormat.pdf;
  final Set<ReportGroup> _groups = {...ReportGroup.values};
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
  String? _error;
  String? _successMessage;

  List<String> _availableCommodities = [];

  @override
  void initState() {
    super.initState();
    _loadCommodities();
    _loadLastChoices();
  }

  Future<void> _loadCommodities() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('market_prices')
          .get();
      final names =
          snap.docs.map((d) => (d.data()['name'] ?? d.id).toString()).toList()
            ..sort();
      if (mounted) setState(() => _availableCommodities = names);
    } catch (_) {
      // The dropdown just stays on "All Commodities" — never blocks the
      // dialog on this best-effort lookup.
    }
  }

  Future<void> _loadLastChoices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final formatName = prefs.getString(_prefsKeyFormat);
      final groupNames = prefs.getStringList(_prefsKeyGroups);
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
        if (groupNames != null && groupNames.isNotEmpty) {
          _groups
            ..clear()
            ..addAll(
              ReportGroup.values.where((g) => groupNames.contains(g.name)),
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
  }

  Future<void> _saveLastChoices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyFormat, _format.name);
      await prefs.setStringList(
        _prefsKeyGroups,
        _groups.map((g) => g.name).toList(),
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
    setState(() {
      _customRange = picked;
      _preset = DateRangePreset.custom;
    });
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _step = 'Starting…';
      _error = null;
      _successMessage = null;
    });

    try {
      final result = await ReportExportService.export(
        format: _format,
        sections: {for (final group in _groups) ...group.sections},
        selectedCommodities: _commodity == null
            ? _availableCommodities.toSet()
            : {_commodity!},
        range: _resolveRange(),
        reportTitle: _reportTitle,
        landscape: _landscape,
        paper: _paper,
        includeDataTables: _includeDataTables,
        notes: '',
        onProgress: (step) {
          if (mounted) setState(() => _step = step);
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
    final canExport = _groups.isNotEmpty && !_exporting;
    // The app's dark green on a light page; the portal's green on a dark one.
    final primary = adminActionColor(c);
    final onPrimary = adminOnActionColor(c);

    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAdminPopupRadius),
        side: BorderSide(color: c.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: _loadingPrefs
            ? Padding(
                padding: const EdgeInsets.all(48),
                child: const Center(child: AdminLoadingBar()),
              )
            // Never scrolls: the form fits a laptop screen as it is, and on
            // a window too short for it the whole of it shrinks to fit.
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 460,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                        child: Text(
                          'Export Report',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
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
                                    label: format == ReportFormat.pdf
                                        ? 'PDF'
                                        : 'Excel',
                                    selected: _format == format,
                                    onTap: () =>
                                        setState(() => _format = format),
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
                                    () => setState(
                                      () => _groups.addAll(ReportGroup.values),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  _link(
                                    c,
                                    'Clear All',
                                    c.textSecondary,
                                    () => setState(_groups.clear),
                                  ),
                                ],
                              ),
                            ),
                            for (final group in ReportGroup.values)
                              _check(
                                c,
                                label: group.label,
                                value: _groups.contains(group),
                                onChanged: (checked) => setState(() {
                                  if (checked) {
                                    _groups.add(group);
                                  } else {
                                    _groups.remove(group);
                                  }
                                }),
                              ),

                            _label(c, 'Commodity'),
                            AdminInputGlow(
                              child: AdminGreyMenu(
                                child: DropdownButtonFormField<String?>(
                                  key: ValueKey(
                                    '$_commodity-${_availableCommodities.length}',
                                  ),
                                  initialValue:
                                      _availableCommodities.contains(_commodity)
                                      ? _commodity
                                      : null,
                                  isExpanded: true,
                                  isDense: true,
                                  menuMaxHeight: 320,
                                  style: TextStyle(
                                    fontFamily: kAdminFontFamily,
                                    color: c.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  icon: Icon(
                                    Icons.expand_more_rounded,
                                    size: 18,
                                    color: c.textSecondary,
                                  ),
                                  dropdownColor: c.surface,
                                  borderRadius: BorderRadius.circular(
                                    kAdminPopupRadius,
                                  ),
                                  // About 40 high, as every dropdown.
                                  decoration: adminFieldDecoration(c).copyWith(
                                    contentPadding: const EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      8,
                                    ),
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: null,
                                      child: Text('All Commodities'),
                                    ),
                                    for (final name in _availableCommodities)
                                      DropdownMenuItem(
                                        value: name,
                                        child: Text(name),
                                      ),
                                  ],
                                  onChanged: (value) =>
                                      setState(() => _commodity = value),
                                ),
                              ),
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
                                    onTap: () =>
                                        setState(() => _preset = preset),
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
                              // The paper beside the heading, so choosing
                              // it takes no room of its own.
                              _label(
                                c,
                                'PDF Options',
                                trailing: _paperPicker(c),
                              ),
                              // The page and the tables on one row; the
                              // tables under them if the row is too narrow.
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
                                    onTap: () =>
                                        setState(() => _landscape = false),
                                  ),
                                  _choice(
                                    c,
                                    label: 'Landscape',
                                    selected: _landscape,
                                    radio: true,
                                    onTap: () =>
                                        setState(() => _landscape = true),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: _check(
                                      c,
                                      label: 'Include data tables',
                                      value: _includeDataTables,
                                      expand: false,
                                      onChanged: (checked) => setState(
                                        () => _includeDataTables = checked,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            if (_exporting) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  14,
                                  12,
                                ),
                                decoration: BoxDecoration(
                                  color: c.surfaceAlt,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        // Drawn by the browser, so it keeps
                                        // turning while the file is built.
                                        BusySpinner(color: c.textPrimary),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _step,
                                            style: TextStyle(
                                              color: c.textPrimary,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    BusyBar(
                                      color: c.textPrimary,
                                      trackColor: c.surface,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Please keep this window open. A report '
                                      'with charts can take a little while.',
                                      style: TextStyle(
                                        color: c.textSecondary,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: TextStyle(color: c.red, fontSize: 12.5),
                              ),
                            ],
                            if (_successMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _successMessage!,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 10, 22, 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _exporting
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              // Tertiary: near-black text alone; the
                              // main button is the dialog's only green.
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
                                // Stays green while exporting, so its
                                // "Exporting…" can be read.
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
                                  fontFamily: 'Montserrat',
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: Text(_exporting ? 'Exporting…' : 'Export'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // A section's heading, with room above it.
  Widget _label(AdminPalette c, String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: c.textPrimary,
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
        onSelected: (paper) => setState(() => _paper = paper),
        itemBuilder: (context) => [
          for (final paper in ReportPaper.values)
            PopupMenuItem(
              value: paper,
              height: 40,
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

  // A round tick box and its label. [expand]: the label takes the rest of
  // the row; false sizes it to the label, for a row it shares.
  Widget _check(
    AdminPalette c, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool expand = true,
  }) {
    final text = Text(
      label,
      style: TextStyle(color: c.textPrimary, fontSize: 13),
    );
    return Semantics(
      checked: value,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              // Square with a slight rounding, as every tick box in the
              // portal: black with a small white tick when ticked, an
              // empty grey outline when not.
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
                      color: value ? c.textPrimary : Colors.transparent,
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
