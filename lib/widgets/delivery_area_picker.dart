import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/ph_locations_service.dart';
import '../services/delivery_coverage.dart';
import 'agri_dialog.dart';
import 'app_search_bar.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

/// The farmer's delivery areas picker (redesigned after system testing,
/// 2026-11-09): Luzon's cities and municipalities only, listed under their
/// provinces. A province opens to its towns; its box ticks or clears all of
/// them at once; the search finds a town or a province. Resolves to the new
/// selection, or null if dismissed without Done.
///
/// [originProvince] (the farm's own) is listed first and starts open.
Future<List<DeliveryArea>?> showDeliveryAreaPicker(
  BuildContext context, {
  required List<DeliveryArea> initial,
  String originProvince = '',
}) {
  return showAgriPanelSheet<List<DeliveryArea>>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        DeliveryAreaPicker(initial: initial, originProvince: originProvince),
  );
}

/// One province (or, for a city independent of any, its region) and its
/// towns, in the order they are listed.
@visibleForTesting
class DeliveryAreaGroup {
  final String name;
  final List<DeliveryArea> areas;
  const DeliveryAreaGroup(this.name, this.areas);
}

/// [places] under their provinces: [originProvince] first, then the rest
/// from A to Z, each province's towns from A to Z.
@visibleForTesting
List<DeliveryAreaGroup> groupDeliveryAreas(
  List<LuzonPlace> places, {
  String originProvince = '',
}) {
  final byGroup = <String, List<DeliveryArea>>{};
  for (final p in places) {
    byGroup
        .putIfAbsent(p.group, () => [])
        .add(DeliveryArea(p.name, p.province));
  }
  final origin = normalizeProvince(originProvince);
  final names = byGroup.keys.toList()
    ..sort((a, b) {
      final aFirst = origin.isNotEmpty && normalizeProvince(a) == origin;
      final bFirst = origin.isNotEmpty && normalizeProvince(b) == origin;
      if (aFirst != bFirst) return aFirst ? -1 : 1;
      return a.compareTo(b);
    });
  return [
    for (final name in names)
      DeliveryAreaGroup(
        name,
        byGroup[name]!..sort((a, b) => a.name.compareTo(b.name)),
      ),
  ];
}

/// The groups and towns a search shows: a province whose name matches
/// shows all its towns; otherwise only the towns whose name matches.
@visibleForTesting
List<DeliveryAreaGroup> searchDeliveryAreas(
  List<DeliveryAreaGroup> groups,
  String query,
) {
  final q = normalizePlace(query);
  if (q.isEmpty) return groups;
  return [
    for (final g in groups)
      if (normalizePlace(g.name).contains(q))
        g
      else if (g.areas.any((a) => normalizePlace(a.name).contains(q)))
        DeliveryAreaGroup(g.name, [
          for (final a in g.areas)
            if (normalizePlace(a.name).contains(q)) a,
        ]),
  ];
}

/// The picker's body (public for tests; open it with
/// [showDeliveryAreaPicker]).
class DeliveryAreaPicker extends StatefulWidget {
  final List<DeliveryArea> initial;
  final String originProvince;

  /// The list to show instead of loading Luzon's (tests).
  final List<LuzonPlace>? places;

  const DeliveryAreaPicker({
    super.key,
    required this.initial,
    this.originProvince = '',
    this.places,
  });

  @override
  State<DeliveryAreaPicker> createState() => _DeliveryAreaPickerState();
}

class _DeliveryAreaPickerState extends State<DeliveryAreaPicker> {
  late final List<DeliveryArea> _selected = [...widget.initial];
  final _search = TextEditingController();
  List<DeliveryAreaGroup> _groups = const [];
  final Set<String> _open = {};
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final given = widget.places;
    if (given != null) {
      _setPlaces(given);
      return;
    }
    try {
      final places = await PhLocationsService.instance
          .fetchLuzonCitiesMunicipalities();
      if (!mounted) return;
      setState(() => _setPlaces(places));
    } catch (_) {
      if (!mounted) return;
      // Offline: the towns around the farm (all in Luzon).
      setState(() {
        _offline = true;
        _setPlaces([
          for (final a in kFallbackDeliveryAreas)
            LuzonPlace(name: a.name, province: a.province, group: a.province),
        ]);
      });
    }
  }

  void _setPlaces(List<LuzonPlace> places) {
    _groups = groupDeliveryAreas(places, originProvince: widget.originProvince);
    _loading = false;
    // The farm's province, and every province already chosen from, start
    // open.
    for (final g in _groups) {
      final isOrigin =
          widget.originProvince.isNotEmpty &&
          normalizeProvince(g.name) == normalizeProvince(widget.originProvince);
      if (isOrigin || g.areas.any(_selected.contains)) _open.add(g.name);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(DeliveryArea area) {
    setState(() {
      if (!_selected.remove(area)) _selected.add(area);
    });
  }

  // The province's box: all of its towns, or none.
  void _toggleGroup(DeliveryAreaGroup group) {
    final all = group.areas.every(_selected.contains);
    setState(() {
      if (all) {
        _selected.removeWhere(group.areas.contains);
      } else {
        for (final a in group.areas) {
          if (!_selected.contains(a)) _selected.add(a);
        }
      }
    });
  }

  // Areas chosen before that are not on the list any more (outside Luzon).
  List<DeliveryArea> get _outsideList {
    if (_loading || _offline) return const [];
    final listed = {for (final g in _groups) ...g.areas};
    return [
      for (final a in _selected)
        if (!listed.contains(a)) a,
    ];
  }

  TextStyle _text(double size, FontWeight weight, Color color) =>
      GoogleFonts.montserrat(fontSize: size, fontWeight: weight, color: color);

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.86;
    final searching = _search.text.trim().isNotEmpty;
    final groups = searchDeliveryAreas(_groups, _search.text);
    final provincesChosen = {
      for (final g in _groups)
        if (g.areas.any(_selected.contains)) g.name,
    }.length;

    // One row per province, then its towns while it is open (always while
    // searching).
    final rows = <Widget Function()>[];
    for (final g in groups) {
      final open = searching || _open.contains(g.name);
      final full = _groups.firstWhere((x) => x.name == g.name, orElse: () => g);
      rows.add(() => _groupHeader(full, open: open, searching: searching));
      if (open) {
        for (final a in g.areas) {
          rows.add(() => _townRow(a));
        }
      }
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tl('Delivery areas'),
                        style: _text(15, FontWeight.bold, AppColors.brand),
                      ),
                    ),
                    _luzonBadge(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Text(
                  tl(
                    'Open a province and tick each town or city you deliver to, or tick the province for all of them.',
                  ),
                  style: _text(12, FontWeight.w400, AppColors.textSecondary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AppSearchBar(
                  hint: tl('Search a town, city or province'),
                  controller: _search,
                  onClear: _search.clear,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 10, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selected.isEmpty
                            ? tl('No areas chosen yet')
                            : tl('{0} towns/cities in {1} provinces', [
                                _selected.length,
                                provincesChosen,
                              ]),
                        key: const Key('deliveryAreaSummary'),
                        style: _text(12, FontWeight.w600, AppColors.text),
                      ),
                    ),
                    if (_selected.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(_selected.clear),
                        child: Text(
                          tl('Clear all'),
                          style: _text(12, FontWeight.w600, AppColors.brand),
                        ),
                      ),
                  ],
                ),
              ),
              if (_outsideList.isNotEmpty) _outsideNotice(),
              if (_offline)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                  child: Text(
                    tl(
                      'Couldn\'t load the full list — showing nearby areas only.',
                    ),
                    style: _text(
                      11.5,
                      FontWeight.w400,
                      AppColors.tone(Colors.orange, 800),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Divider(height: 1, color: AppColors.hairline),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: AppColors.brand,
                        ),
                      )
                    : rows.isEmpty
                    ? Center(
                        child: Text(
                          tl('No matching town, city or province in Luzon.'),
                          textAlign: TextAlign.center,
                          style: _text(
                            12.5,
                            FontWeight.w400,
                            AppColors.grey(600),
                          ),
                        ),
                      )
                    : ListView.builder(
                        key: const Key('deliveryAreaList'),
                        itemCount: rows.length,
                        itemBuilder: (context, i) => rows[i](),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: AgriDialogButton(
                  label: _selected.isEmpty
                      ? tl('Done')
                      : tl('Done ({0} selected)', [_selected.length]),
                  kind: AgriButtonKind.primary,
                  onPressed: () => Navigator.pop(context, _selected),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _luzonBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.adapt(const Color(0xFFE8F3E3)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.map_outlined, size: 13, color: AppColors.brand),
        const SizedBox(width: 4),
        Text(
          tl('Luzon only'),
          style: _text(10.5, FontWeight.w600, AppColors.brand),
        ),
      ],
    ),
  );

  // A province: its box (all or none of its towns), its name, how many are
  // chosen, and a chevron that opens or closes it.
  Widget _groupHeader(
    DeliveryAreaGroup group, {
    required bool open,
    required bool searching,
  }) {
    final chosen = group.areas.where(_selected.contains).length;
    final value = chosen == 0
        ? false
        : chosen == group.areas.length
        ? true
        : null;
    return InkWell(
      key: Key('deliveryGroup_${group.name}'),
      onTap: searching
          ? null
          : () => setState(() {
              if (!_open.remove(group.name)) _open.add(group.name);
            }),
      child: Container(
        color: AppColors.adapt(const Color(0xFFF6F8F3)),
        padding: const EdgeInsets.fromLTRB(6, 2, 12, 2),
        child: Row(
          children: [
            Checkbox(
              key: Key('deliveryGroupAll_${group.name}'),
              value: value,
              tristate: true,
              activeColor: AppColors.brand,
              onChanged: (_) => _toggleGroup(group),
            ),
            Expanded(
              child: Text(
                group.name,
                style: _text(13, FontWeight.w700, AppColors.text),
              ),
            ),
            Text(
              chosen == 0
                  ? (group.areas.length == 1
                        ? tl('1 town')
                        : tl('{0} towns', [group.areas.length]))
                  : tl('{0} of {1}', [chosen, group.areas.length]),
              style: _text(
                11.5,
                chosen == 0 ? FontWeight.w400 : FontWeight.w600,
                chosen == 0 ? AppColors.grey(600) : AppColors.brand,
              ),
            ),
            if (!searching) ...[
              const SizedBox(width: 4),
              Icon(
                open ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: AppColors.grey(600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _townRow(DeliveryArea area) => CheckboxListTile(
    key: Key('deliveryTown_${area.label}'),
    dense: true,
    contentPadding: const EdgeInsets.only(left: 40, right: 12),
    controlAffinity: ListTileControlAffinity.leading,
    activeColor: AppColors.brand,
    value: _selected.contains(area),
    onChanged: (_) => _toggle(area),
    title: Text(area.name, style: _text(13, FontWeight.w500, AppColors.text)),
  );

  // Chosen before, but outside Luzon: still listed so they can be taken
  // off; none can be added.
  Widget _outsideNotice() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          tl('Outside Luzon:'),
          style: _text(11.5, FontWeight.w600, AppColors.grey(700)),
        ),
        for (final area in _outsideList)
          InputChip(
            label: Text(
              area.label,
              style: _text(11.5, FontWeight.w600, AppColors.grey(800)),
            ),
            onDeleted: () => _toggle(area),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
      ],
    ),
  );
}
