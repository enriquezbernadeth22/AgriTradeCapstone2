import '../widgets/agri_app_bar.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../widgets/farm_buyer_map.dart';
import '../services/firebase_refs.dart';
import '../services/location_permission_prompt.dart';
import '../services/road_route_service.dart';
import '../services/public_farm_location.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/agri_empty_state.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

/// "Approx. 4.8 km away" — never presented as exact: one decimal below
/// 10 km, whole kilometres beyond that. [byRoad] (measured along the
/// roads) reads "Approx. 4.8 km by road". Null (no buyer location, or no
/// farm area to measure to) reads "Distance unavailable".
String approxDistanceLabel(double? km, {bool byRoad = false}) {
  if (km == null) return 'Distance unavailable';
  final tail = byRoad ? 'by road' : 'away';
  if (km < 0.1) return 'Approx. less than 0.1 km $tail';
  return km < 10
      ? 'Approx. ${km.toStringAsFixed(1)} km $tail'
      : 'Approx. ${km.round()} km $tail';
}

/// Whether the buyer is close enough to the farm area for one map view to
/// usefully hold both. Beyond this the map stays on the farm area (fitting
/// both would zoom out to a whole-country or whole-world view).
bool shouldFitBuyerAndFarm(double? distanceKm) =>
    distanceKm != null && distanceKm <= 150;

/// Farm Location — the map opened from a product's details. It is about
/// that one farmer only: the general area their farm is in, the buyer's
/// own position (if they allow it), and roughly how far apart the two are.
///
/// The farm marker is the farmer's public, barangay-level location (see
/// public_farm_location.dart) — the same point every time for the same
/// barangay, never the farm's exact pin and never anything derived from
/// the buyer. The buyer's position is only ever the origin of the
/// distance; it stays on this device and is not written anywhere here.
///
/// Camera: the map is created only once the farm point is known, already
/// centred on it. The single later move is to bring the buyer into view,
/// once, when their position arrives. Nothing re-centres on rebuilds.
class BuyerMapView extends StatefulWidget {
  final String farmerId;

  /// Shown until the farmer's public profile loads (and if it can't).
  final String farmerName;

  const BuyerMapView({
    super.key,
    required this.farmerId,
    required this.farmerName,
  });

  @override
  State<BuyerMapView> createState() => _BuyerMapViewState();
}

class _BuyerMapViewState extends State<BuyerMapView> {
  // Close enough to read a barangay and its surroundings.
  static const double _farmZoom = 13.5;

  GoogleMapController? _map;

  bool _loadingFarm = true;
  PublicFarmLocation? _farm;

  Position? _myPosition;
  // The buyer's saved position (Delivery & Pick-up), used when the phone
  // cannot give its own.
  LatLng? _savedPoint;
  // The road from the buyer to the farm area, once known.
  RoadRoute? _road;
  // Why there is no distance, when the buyer could do something about it.
  String? _locationNotice;
  bool _fittedBoth = false;
  // A GPS fix is being taken.
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _loadFarm();
    _loadSavedPoint();
    // Asked for here — when the buyer opens a location feature — and not
    // at login, registration or app start.
    _determinePosition();
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  LatLng? get _farmPoint {
    final farm = _farm;
    return farm == null || !farm.hasPoint
        ? null
        : LatLng(farm.latitude!, farm.longitude!);
  }

  Future<void> _loadFarm() async {
    PublicFarmLocation? farm;
    try {
      farm = await loadPublicFarmLocation(
        widget.farmerId,
        fallbackName: widget.farmerName,
      );
    } catch (_) {
      farm = null;
    }
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint(
        'FarmLocation[debug]: farmer ${widget.farmerId} area = '
        '"${farm?.area}", public point = '
        '(${farm?.latitude}, ${farm?.longitude})',
      );
    }
    setState(() {
      _farm = farm;
      _loadingFarm = false;
    });
  }

  Future<void> _loadSavedPoint() async {
    final uid = FirebaseRefs.auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final geo =
          (await FirebaseRefs.firestore
                  .collection('users')
                  .doc(uid)
                  .collection('private')
                  .doc('geo')
                  .get())
              .data();
      final lat = (geo?['latitude'] as num?)?.toDouble();
      final lng = (geo?['longitude'] as num?)?.toDouble();
      // Outside the Philippines (an emulator's default) is not used.
      if (!mounted || !isValidPublicCoordinate(lat, lng)) return;
      setState(() => _savedPoint = LatLng(lat!, lng!));
      _fitBuyerOnce();
    } catch (_) {
      // Only the fallback is lost.
    }
  }

  /// Where the distance and the line start: the phone's position, else the
  /// buyer's saved one.
  LatLng? get _origin {
    final me = _myPosition;
    return me == null ? _savedPoint : LatLng(me.latitude, me.longitude);
  }

  bool get _fromSavedPoint => _myPosition == null && _savedPoint != null;

  Future<void> _determinePosition() async {
    try {
      // The AgriTrade+ explanation first, then the system prompt.
      if (!mounted) return;
      final granted = await requestBuyerLocationPermission(context);
      if (kDebugMode) {
        debugPrint(
          'FarmLocation: buyer location permission '
          '${granted ? 'granted' : 'not granted'}',
        );
      }
      if (!mounted) return;
      if (!granted) {
        setState(
          () => _locationNotice = tl('Allow location to see the distance.'),
        );
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        setState(
          () => _locationNotice = tl(
            'Turn on location services to see the distance.',
          ),
        );
        return;
      }

      // A fresh GPS fix can take a while the first time; meanwhile the
      // phone's last known position gives the distance at once.
      if (mounted) setState(() => _locating = true);
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (mounted &&
            last != null &&
            isValidPublicCoordinate(last.latitude, last.longitude)) {
          setState(() {
            _myPosition = last;
            _locationNotice = null;
          });
          _fitBuyerOnce();
        }
      } catch (_) {
        // Not available on every device: the fresh fix below.
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (mounted) setState(() => _locating = false);
      // Debug builds only — never compiled into a release.
      if (kDebugMode) {
        debugPrint(
          'FarmLocation[debug]: buyer position = '
          '(${position.latitude}, ${position.longitude})',
        );
      }
      if (!mounted) return;
      // A device position that is not in the Philippines (an emulator's
      // default location, a mock location, a bad fix) is not a usable
      // origin: it would give a distance of thousands of kilometres. It
      // is discarded rather than shown.
      if (!isValidPublicCoordinate(position.latitude, position.longitude)) {
        setState(() {
          _myPosition = null;
          _locationNotice = 'Your device location could not be confirmed.';
        });
        return;
      }
      setState(() {
        _myPosition = position;
        _locationNotice = null;
      });
      _fitBuyerOnce();
    } catch (_) {
      if (kDebugMode) debugPrint('FarmLocation: buyer position NOT found');
      if (!mounted) return;
      setState(() {
        _locating = false;
        // The last known position, if there was one, still stands.
        if (_myPosition == null) {
          _locationNotice = tl('Could not get your location right now.');
        }
      });
    }
  }

  /// Refresh: the farm's area and the buyer's position again, for an
  /// up-to-date distance.
  Future<void> _refresh() async {
    if (_locating) return;
    setState(() {
      _fittedBoth = false;
      _locationNotice = null;
    });
    await Future.wait([_loadFarm(), _determinePosition()]);
  }

  /// The buyer -> the farmer's public barangay point: along the roads once
  /// the route is known, else in a straight line.
  double? get _distanceKm {
    final me = _origin;
    final farm = _farmPoint;
    if (me == null || farm == null) return null;
    final road = _road;
    if (road != null) return road.km;
    return Geolocator.distanceBetween(
          me.latitude,
          me.longitude,
          farm.latitude,
          farm.longitude,
        ) /
        1000;
  }

  // The one camera move after the map opens: bring the buyer into view
  // alongside the farm area. Runs once, whichever of "map ready" and
  // "buyer position ready" happens last, and only when the two are near
  // enough to share a view. The farm marker itself never moves.
  void _fitBuyerOnce() {
    final map = _map;
    final farm = _farmPoint;
    final me = _origin;
    if (_fittedBoth || map == null || farm == null || me == null) return;
    _fittedBoth = true;

    final km = _distanceKm;
    if (kDebugMode) {
      debugPrint(
        'FarmLocation[debug]: distance = ${km?.toStringAsFixed(2)} km; '
        '${shouldFitBuyerAndFarm(km) ? "camera fits buyer + farm" : "camera stays on farm point"}',
      );
    }
    if (!shouldFitBuyerAndFarm(km)) return;

    final south = me.latitude < farm.latitude ? me.latitude : farm.latitude;
    final north = me.latitude > farm.latitude ? me.latitude : farm.latitude;
    final west = me.longitude < farm.longitude ? me.longitude : farm.longitude;
    final east = me.longitude > farm.longitude ? me.longitude : farm.longitude;
    map.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        64,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final farm = _farmPoint;

    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AgriAppBar(
        title: tl('Farm Location'),
        // Returns to the Product Details this map was opened from.
        onBack: () => Navigator.of(context).pop(),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _loadingFarm
                ? Center(
                    child: CircularProgressIndicator(color: AppColors.brand),
                  )
                : farm == null
                ? _unavailable()
                : _mapFor(farm),
          ),
          Positioned(left: 12, right: 12, bottom: 12, child: _infoCard()),
        ],
      ),
    );
  }

  // Built only when the farm point is known, so the very first frame of
  // the map is already on the farmer's barangay — there is no default
  // position for it to open on.
  Widget _mapFor(LatLng farm) {
    // The farmer and the buyer as their photos, with a line along the roads
    // drawing itself from the buyer to the farm area (FarmBuyerMap).
    return FarmBuyerMap(
      farm: farm,
      buyer: _origin,
      onRoute: (route) {
        if (mounted) setState(() => _road = route);
      },
      farmerId: widget.farmerId,
      farmerName: _farm?.farmerName ?? widget.farmerName,
      farmerPhotoUrl: _farm?.photoUrl,
      farmArea: _farm?.area,
      zoom: _farmZoom,
      // Keeps the zoom buttons and the Google logo clear of the card.
      padding: const EdgeInsets.only(bottom: 150),
      onMapCreated: (controller) {
        _map = controller;
        if (kDebugMode) {
          debugPrint(
            'FarmLocation[debug]: map created, camera target = farm point '
            '(${farm.latitude}, ${farm.longitude}), zoom $_farmZoom',
          );
        }
        _fitBuyerOnce();
      },
    );
  }

  // No resolvable public point: say so, rather than draw a map of
  // somewhere else. The saved area text is still shown in the card.
  Widget _unavailable() {
    return Container(
      color: AppColors.surfaceAlt,
      alignment: const Alignment(0, -0.35),
      child: AgriEmptyState(
        icon: Icons.location_off_outlined,
        title: tl('Farm location unavailable'),
        subtitle: tl('We could not place this farmer’s area on the map.'),
        padding: EdgeInsets.all(32),
      ),
    );
  }

  // How the distance was measured: by road or straight, from the phone or
  // from the saved location. That it ends at the general area is said once,
  // on the map (FarmBuyerMap's note), not again here.
  String _distanceNote() {
    final road = _road != null;
    if (_fromSavedPoint) {
      return road
          ? tl('Estimated by road from your saved location.')
          : tl('Estimated from your saved location.');
    }
    return road
        ? tl('Estimated by road from where you are.')
        : tl('Estimated in a straight line from where you are.');
  }

  // Compact floating card — not a sheet: the map stays in view above it.
  Widget _infoCard() {
    final farm = _farm;
    final name = farm?.farmerName ?? widget.farmerName;
    final area = farm?.area ?? '';
    final distanceKm = _distanceKm;
    final hasDistance = distanceKm != null;
    final notice = _locationNotice;
    // Without a farm point there is nothing to measure to, whatever the
    // buyer's permission is.
    final canRetry = !hasDistance && notice != null && _farmPoint != null;

    return SafeArea(
      top: false,
      child: Material(
        color: AppColors.surface,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProfileAvatar(
                    photoUrl: farm?.photoUrl,
                    name: name,
                    radius: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? tl('Farmer') : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          area.isNotEmpty
                              ? area
                              : (_loadingFarm
                                    ? tl('Loading farm area…')
                                    : tl('General location not set')),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            color: AppColors.grey(800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    hasDistance
                        ? Icons.near_me_outlined
                        : Icons.location_disabled_outlined,
                    size: 16,
                    color: hasDistance ? AppColors.brand : AppColors.grey(700),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      !hasDistance && _locating
                          ? tl('Finding your location…')
                          : approxDistanceLabel(
                              distanceKm,
                              byRoad: _road != null && hasDistance,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: hasDistance
                            ? AppColors.brand
                            : AppColors.grey(800),
                      ),
                    ),
                  ),
                  // Refresh the distance (and the farm area); spins while
                  // the location is being found.
                  if (!canRetry)
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: _locating
                          ? Padding(
                              padding: const EdgeInsets.all(9),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.brand,
                              ),
                            )
                          : IconButton(
                              key: const Key('refreshDistance'),
                              tooltip: tl('Refresh distance'),
                              padding: EdgeInsets.zero,
                              iconSize: 20,
                              onPressed: _refresh,
                              icon: Icon(
                                Icons.refresh_rounded,
                                color: AppColors.brand,
                              ),
                            ),
                    ),
                  if (canRetry)
                    TextButton(
                      onPressed: _determinePosition,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.brand,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        tl('Try Again'),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                hasDistance
                    ? _distanceNote()
                    : (canRetry
                          ? notice
                          : tl('Farm area could not be mapped.')),
                style: TextStyle(fontSize: 11, color: AppColors.grey(700)),
              ),
              // That the farm point is only the general area is said once,
              // at the top of the map (the user's choice, 2026-11-07).
            ],
          ),
        ),
      ),
    );
  }
}
