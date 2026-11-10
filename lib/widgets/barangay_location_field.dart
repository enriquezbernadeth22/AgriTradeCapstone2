import 'package:flutter/material.dart';
import 'app_scaffold_messenger.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/laurel_barangays.dart';
import '../screen/confirm_farm_location_screen.dart';
import '../services/geocoding_service.dart';
import '../services/location_permission_prompt.dart';
import '../theme/app_theme.dart';
import 'agri_dialog.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

/// Farmer-only barangay picker (buyers use BuyerLocationField instead, since
/// buyer registration isn't restricted to Laurel): a field that opens a
/// searchable list (kLaurelBarangays, see [showBarangayPicker]) plus a
/// "Use my location" action that gets a GPS fix and, when its looked-up
/// address clearly names one of Laurel's barangays, sets it at once with
/// nothing to confirm; otherwise it opens a map on the fix
/// (ConfirmFarmLocationScreen) for the farmer to confirm or pick. It is
/// never taken from which barangay happens to be nearest, since the
/// barangay points in laurel_barangays.dart are placeholders, not
/// surveyed centers. [onLocationDetected] additionally hands
/// back the raw coordinates, for callers that want to store a precise
/// point alongside the barangay name (the way a farmer's real GPS pin
/// already works).
class BarangayLocationField extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final void Function(double lat, double lng)? onLocationDetected;
  final String label;
  final String? errorText;

  const BarangayLocationField({
    super.key,
    required this.value,
    required this.onChanged,
    this.onLocationDetected,
    this.label = 'Barangay (Laurel)',
    this.errorText,
    this.askLocation,
    this.lookup,
  });

  /// Stands in for requestFarmerLocationPermission in tests.
  @visibleForTesting
  final Future<bool> Function(BuildContext context)? askLocation;

  /// Stands in for the address lookup in tests.
  @visibleForTesting
  final Future<ResolvedAddress?> Function(double lat, double lng)? lookup;

  @override
  State<BarangayLocationField> createState() => _BarangayLocationFieldState();
}

class _BarangayLocationFieldState extends State<BarangayLocationField> {
  bool _locating = false;
  bool _dropdownPromptShown = false;

  // Opening the list is the clearest signal they've reached the
  // location-relevant part of the form, so the first tap asks for location
  // first, on its own: the list opens only once it is allowed. Not Now just
  // closes the question, and the next tap opens the list, since a barangay
  // can always be picked by hand.
  Future<void> _openPicker() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_dropdownPromptShown) {
      _dropdownPromptShown = true;
      final ask = widget.askLocation ?? requestFarmerLocationPermission;
      final allowed = await ask(context);
      if (!allowed) return;
    }
    if (!mounted) return;
    final picked = await showBarangayPicker(context, selected: widget.value);
    if (picked != null && mounted) widget.onChanged(picked);
  }

  // "Use my location": get one GPS fix (nothing is tracked afterwards). A
  // barangay the address clearly names is set at once; otherwise the map
  // opens on the fix for the farmer to confirm or pick. Never a guess from
  // which barangay is nearest.
  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    // The reason for location is shown here, so "Select Manually" after it
    // opens the list straight away.
    _dropdownPromptShown = true;
    try {
      final granted = await requestFarmerLocationPermission(context);
      if (!mounted) return;
      if (!granted) {
        // The permission helper has just explained this (and offered
        // Settings), so no second dialog — only the way to carry on.
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar(
            tl('Location permission is needed to detect your barangay.'),
            kind: MessageKind.warning,
            action: SnackBarAction(
              label: tl('Select Manually'),
              onPressed: _openPicker,
            ),
          ),
        );
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        await _locationProblem(
          title: tl('Location Is Turned Off'),
          message: tl(
            'Turn on Location (GPS) on your phone and try again, or select your barangay from the list instead.',
          ),
        );
        return;
      }

      final Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        await _locationProblem(
          title: tl('Could Not Find Your Location'),
          message: tl(
            'Your phone could not get a GPS position. Try again outdoors or near a window, or select your barangay from the list instead.',
          ),
        );
        return;
      }
      if (!mounted) return;

      // The address clearly names one of Laurel's barangays: that is the
      // farmer's location, with nothing more to tap (the user, 2026-11-09).
      // Only when it can't be told (no address, no clear barangay, or not
      // Laurel) does the map open for them to confirm or pick.
      final lookup = widget.lookup ?? GeocodingService.reverseGeocode;
      final reading = readFarmLocation(
        await lookup(position.latitude, position.longitude),
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      final found = reading.inLaurel ? reading.barangay : null;
      if (found != null) {
        widget.onChanged(found);
        widget.onLocationDetected?.call(position.latitude, position.longitude);
        showAppMessage(
          context,
          tl('Location set: Barangay {0}', [found]),
          kind: MessageKind.success,
        );
        return;
      }

      final result = await Navigator.push<FarmLocationResult>(
        context,
        MaterialPageRoute(
          builder: (_) => ConfirmFarmLocationScreen(
            initialLat: position.latitude,
            initialLng: position.longitude,
          ),
        ),
      );
      if (result == null || !mounted) return;
      widget.onChanged(result.barangay);
      widget.onLocationDetected?.call(result.lat, result.lng);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // Says what stopped the location from being found, with a way to try
  // again and a way to carry on without it.
  Future<void> _locationProblem({
    required String title,
    required String message,
  }) async {
    final choice = await showAgriDialog<String>(
      context: context,
      builder: (dialogContext) => AgriDialog(
        icon: Icons.location_off_outlined,
        tone: AgriTone.warning,
        title: Text(title),
        content: Text(tl(message)),
        actions: [
          AgriDialogButton(
            label: tl('Select Manually'),
            onPressed: () => Navigator.pop(dialogContext, 'manual'),
          ),
          AgriDialogButton(
            label: tl('Retry'),
            kind: AgriButtonKind.primary,
            onPressed: () => Navigator.pop(dialogContext, 'retry'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'retry') {
      await _useMyLocation();
    } else if (choice == 'manual') {
      await _openPicker();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Each gives way on a narrow phone, where the Tagalog is longer.
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.label(),
              ),
            ),
            TextButton.icon(
              onPressed: _locating ? null : _useMyLocation,
              icon: _locating
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.mid,
                      ),
                    )
                  : const Icon(Icons.my_location, size: 16),
              label: Text(
                tl('Use my location'),
                style: TextStyle(fontSize: 12.5),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.mid,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.formLabelGap),
        // Looks like the form's other dropdowns (AppTheme
        // .formDropdownDecoration), but opens the searchable list instead.
        Semantics(
          button: true,
          label: widget.value == null
              ? tl('Select your barangay')
              : 'Barangay, ${widget.value}',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.dropdownRadius),
              hoverColor: AppColors.adapt(Colors.grey.shade200),
              splashColor: AppColors.adapt(Colors.grey.shade300),
              onTap: _openPicker,
              child: Ink(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppTheme.dropdownRadius),
                  border: Border.fromBorderSide(
                    AppTheme.registrationDropdownBorder().borderSide,
                  ),
                ),
                child: SizedBox(
                  height: AppTheme.formFieldHeight,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 18, right: 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          color: AppTheme.formIconColor,
                          size: AppTheme.formIconSize,
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 1,
                          height: 22,
                          color: AppColors.hairline,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.value ?? tl('Select your barangay'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: widget.value == null
                                ? AppTheme.formHint()
                                : GoogleFonts.montserrat(
                                    fontSize: AppTheme.formTextSize,
                                    color: AppColors.text,
                                  ),
                          ),
                        ),
                        Icon(
                          Icons.expand_more_rounded,
                          color: AppTheme.formIconColor,
                          size: AppTheme.formIconSize,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                size: 14,
                color: AppColors.tone(Colors.red, 700),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.errorText!,
                  style: TextStyle(
                    color: AppColors.tone(Colors.red, 700),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppTheme.formFieldGap),
      ],
    );
  }
}

/// The searchable "Select Barangay" bottom sheet. Returns the barangay
/// tapped, or null if the sheet was closed without choosing one. Nothing
/// is ever picked on the user's behalf.
Future<String?> showBarangayPicker(BuildContext context, {String? selected}) {
  // The app's frosted panel sheet and dimmed background, like every other.
  return showAgriPanelSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BarangayPickerSheet(selected: selected),
  );
}

class _BarangayPickerSheet extends StatefulWidget {
  final String? selected;

  const _BarangayPickerSheet({this.selected});

  @override
  State<_BarangayPickerSheet> createState() => _BarangayPickerSheetState();
}

class _BarangayPickerSheetState extends State<_BarangayPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return kLaurelBarangays;
    return kLaurelBarangays.where((b) => b.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final matches = _matches;
    return Padding(
      // Lifts the sheet above the keyboard while searching.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.78),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tl('Select Barangay'),
                          style: GoogleFonts.montserrat(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Laurel, Batangas',
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: tl('Close'),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                textCapitalization: TextCapitalization.words,
                onChanged: (value) => setState(() => _query = value),
                style: GoogleFonts.montserrat(fontSize: 14),
                decoration: InputDecoration(
                  hintText: tl('Search barangay'),
                  hintStyle: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppColors.mid,
                    size: 20,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: tl('Clear search'),
                          icon: const Icon(Icons.cancel_rounded, size: 18),
                          color: AppColors.textMuted,
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.adapt(const Color(0xFFF4F6F4)),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: const PillInputBorder(borderSide: BorderSide.none),
                  enabledBorder: const PillInputBorder(
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: AppTheme.fieldFocusBorder,
                ),
              ),
            ),
            Divider(height: 1, color: AppColors.adapt(const Color(0xFFE8EDE8))),
            Flexible(
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                      child: Text(
                        tl('No barangay in Laurel matches "{0}".', [
                          _query.trim(),
                        ]),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          fontSize: 13.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.only(
                        top: 4,
                        bottom: 12 + media.viewPadding.bottom,
                      ),
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 56,
                        endIndent: 20,
                        color: AppColors.adapt(const Color(0xFFEEF1EE)),
                      ),
                      itemBuilder: (context, index) {
                        final name = matches[index];
                        final isSelected = name == widget.selected;
                        return ListTile(
                          onTap: () => Navigator.pop(context, name),
                          selected: isSelected,
                          selectedTileColor: AppColors.accent.withValues(
                            alpha: 0.35,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                          ),
                          horizontalTitleGap: 12,
                          minLeadingWidth: 24,
                          leading: Icon(
                            isSelected
                                ? Icons.location_on
                                : Icons.location_on_outlined,
                            color: isSelected
                                ? AppColors.mid
                                : AppColors.textMuted,
                            size: 21,
                          ),
                          title: Text(
                            name,
                            style: GoogleFonts.montserrat(
                              fontSize: 14.5,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.brand
                                  : AppColors.text,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.mid,
                                  size: 20,
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
