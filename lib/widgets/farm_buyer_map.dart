import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../l10n/app_language.dart';
import '../services/firebase_refs.dart';
import '../services/road_route_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The farm and the buyer on a map, as the people they are (the user's
/// design, 2026-11-07): each is a round photo (initials without one) in
/// place of a pin, the farmer's ringed green and the buyer's blue, and
/// between them a dashed line along the roads (`RoadRouteService`; a
/// straight one when no route can be had) that draws itself from the buyer
/// to the farm when the map opens and when the buyer's position changes.
/// Around the farm, the wide circle of its approximate area, and a note on
/// the map that the line ends at the farmer's general area: the farm point
/// is the barangay's, never its pin.
///
/// The farmer's photo comes from their public profile ([farmerId]) unless
/// [farmerPhotoUrl] is given; the buyer is the signed-in account.
class FarmBuyerMap extends StatefulWidget {
  final LatLng farm;
  final LatLng? buyer;
  final String farmerId;
  final String farmerName;
  final String? farmerPhotoUrl;

  /// The area's name, under "Approximate Farm Location" on its marker.
  final String? farmArea;

  /// A still preview: nothing moves it.
  final bool preview;
  final double zoom;
  final EdgeInsets padding;
  final ValueChanged<GoogleMapController>? onMapCreated;

  /// The road route once known (null when there is none), for the
  /// distance by road.
  final ValueChanged<RoadRoute?>? onRoute;

  const FarmBuyerMap({
    super.key,
    required this.farm,
    required this.farmerId,
    required this.farmerName,
    this.buyer,
    this.farmerPhotoUrl,
    this.farmArea,
    this.preview = false,
    this.zoom = 13.5,
    this.padding = EdgeInsets.zero,
    this.onMapCreated,
    this.onRoute,
  });

  static const Color farmerRing = Color(0xFF2E7D32);
  static const Color buyerRing = Color(0xFF1E6FD9);

  /// The reminder at the top of the map while the line shows; without a
  /// line (no buyer position), [generalPhotoNote]. Said only there.
  static const String generalAreaNote =
      'The line ends at the farmer’s general area, not the exact farm.';
  static const String generalPhotoNote =
      'The farmer’s photo marks their general area, not the exact farm.';

  @override
  State<FarmBuyerMap> createState() => _FarmBuyerMapState();
}

class _FarmBuyerMapState extends State<FarmBuyerMap>
    with SingleTickerProviderStateMixin {
  // How many times the line grows while drawing: each step is one update
  // of the map, so not one per frame.
  static const int _drawSteps = 45;

  GoogleMapController? _controller;
  BitmapDescriptor? _farmerIcon;
  BitmapDescriptor? _buyerIcon;

  // The way from the buyer to the farm: the road, or a straight line.
  List<LatLng>? _way;
  int _step = 0;
  int _routeAsk = 0;

  // The line drawing itself from the buyer to the farm.
  late final AnimationController _line =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      )..addListener(() {
        final step = (Curves.easeInOutCubic.transform(_line.value) * _drawSteps)
            .round();
        if (step != _step) setState(() => _step = step);
      });

  @override
  void initState() {
    super.initState();
    _loadIcons();
    _findWay();
  }

  @override
  void didUpdateWidget(FarmBuyerMap old) {
    super.didUpdateWidget(old);
    if (old.buyer != widget.buyer || old.farm != widget.farm) _findWay();
    if (old.farmerPhotoUrl != widget.farmerPhotoUrl ||
        old.farmerId != widget.farmerId) {
      _loadIcons();
    }
  }

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  Future<void> _findWay() async {
    final ask = ++_routeAsk;
    final buyer = widget.buyer;
    final farm = widget.farm;
    if (buyer == null) {
      _line.stop();
      if (_way != null) setState(() => _way = null);
      return;
    }
    final route = await RoadRouteService.between(buyer, farm);
    if (!mounted || ask != _routeAsk) return;
    widget.onRoute?.call(route);
    setState(() {
      _way = route?.points ?? [buyer, farm];
      _step = 0;
    });
    if (WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      _line.value = 1;
      setState(() => _step = _drawSteps);
    } else {
      _line.forward(from: 0);
    }
  }

  Future<void> _loadIcons() async {
    String? farmerPhoto = widget.farmerPhotoUrl;
    String farmerName = widget.farmerName;
    if (farmerPhoto == null && widget.farmerId.isNotEmpty) {
      try {
        final profile = await FirebaseRefs.firestore
            .collection('publicProfiles')
            .doc(widget.farmerId)
            .get();
        farmerPhoto = profile.data()?['photoUrl']?.toString();
        final name = profile.data()?['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) farmerName = name;
      } catch (_) {}
    }
    String? buyerPhoto;
    var buyerName = '';
    try {
      final user = FirebaseRefs.auth.currentUser;
      if (user != null) {
        buyerPhoto = user.photoURL;
        buyerName = user.displayName ?? '';
        final me = await FirebaseRefs.firestore
            .collection('users')
            .doc(user.uid)
            .get();
        final data = me.data() ?? const <String, dynamic>{};
        buyerPhoto = data['photoUrl']?.toString() ?? buyerPhoto;
        buyerName = (data['name'] ?? data['fullName'] ?? buyerName)
            .toString()
            .trim();
      }
    } catch (_) {}
    final icons = await Future.wait([
      MapAvatarMarker.of(
        photoUrl: farmerPhoto,
        name: farmerName,
        ring: FarmBuyerMap.farmerRing,
      ),
      MapAvatarMarker.of(
        photoUrl: buyerPhoto,
        name: buyerName.isEmpty ? tl('You') : buyerName,
        ring: FarmBuyerMap.buyerRing,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _farmerIcon = icons[0];
      _buyerIcon = icons[1];
    });
  }

  @override
  Widget build(BuildContext context) {
    final farm = widget.farm;
    final buyer = widget.buyer;
    final way = buyer == null ? null : _way;
    final drawn = way == null || _step == 0
        ? const <LatLng>[]
        : partOfLine(way, _step / _drawSteps);
    final preview = widget.preview;
    final map = GoogleMap(
      initialCameraPosition: CameraPosition(target: farm, zoom: widget.zoom),
      onMapCreated: (controller) {
        _controller = controller;
        widget.onMapCreated?.call(controller);
      },
      padding: widget.padding,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      // Its own + and − instead (below): + zooms in on the farmer.
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      scrollGesturesEnabled: !preview,
      zoomGesturesEnabled: !preview,
      rotateGesturesEnabled: !preview,
      tiltGesturesEnabled: !preview,
      // On Android a preview is a still picture of the map (lite mode).
      liteModeEnabled:
          preview && defaultTargetPlatform == TargetPlatform.android,
      markers: {
        Marker(
          markerId: const MarkerId('farmer'),
          position: farm,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 2,
          icon:
              _farmerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: tl('Approximate Farm Location'),
            snippet: widget.farmArea,
          ),
        ),
        if (buyer != null)
          Marker(
            markerId: const MarkerId('buyer'),
            position: buyer,
            anchor: const Offset(0.5, 0.5),
            zIndexInt: 1,
            icon:
                _buyerIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
            infoWindow: InfoWindow(title: tl('You')),
          ),
      },
      polylines: {
        if (drawn.length >= 2) ...[
          // A white edge under the dashes, so they read on any map colour.
          Polyline(
            polylineId: const PolylineId('buyer_to_farm_edge'),
            points: drawn,
            color: Colors.white,
            width: 7,
            zIndex: 1,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
          Polyline(
            polylineId: const PolylineId('buyer_to_farm'),
            points: drawn,
            color: FarmBuyerMap.farmerRing,
            width: 5,
            zIndex: 2,
            jointType: JointType.round,
            patterns: [PatternItem.dash(20), PatternItem.gap(12)],
          ),
        ],
      },
      // A wide circle: this is a barangay, not an address.
      circles: {
        Circle(
          circleId: const CircleId('approximate_farm_area'),
          center: farm,
          radius: 700,
          fillColor: AppColors.brandFill.withValues(alpha: 0.12),
          strokeColor: AppColors.brand.withValues(alpha: 0.55),
          strokeWidth: 1,
        ),
      },
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        map,
        // Always, the preview too: the one place the page says the farm
        // point is only the general area (2026-11-08).
        Positioned(
          top: preview ? 8 : 12,
          left: preview ? 8 : 12,
          right: preview ? 8 : 12,
          child: Align(
            alignment: Alignment.topCenter,
            child: IgnorePointer(
              child: _GeneralAreaNote(
                compact: preview,
                text: way != null
                    ? FarmBuyerMap.generalAreaNote
                    : FarmBuyerMap.generalPhotoNote,
              ),
            ),
          ),
        ),
        if (!preview)
          Positioned(
            right: 12,
            bottom: widget.padding.bottom + 12,
            child: _ZoomButtons(onIn: _zoomInOnFarm, onOut: _zoomOut),
          ),
      ],
    );
  }

  // + : one step closer, with the farmer in the middle (the user's choice,
  // 2026-11-07), not wherever the map happens to be centred.
  Future<void> _zoomInOnFarm() async {
    final map = _controller;
    if (map == null) return;
    var zoom = widget.zoom;
    try {
      zoom = await map.getZoomLevel();
    } catch (_) {}
    if (!mounted) return;
    await map.animateCamera(
      CameraUpdate.newLatLngZoom(widget.farm, (zoom + 1).clamp(3, 19)),
    );
  }

  Future<void> _zoomOut() async {
    await _controller?.animateCamera(CameraUpdate.zoomOut());
  }
}

/// The map's + and −: two white rounded squares joined, on a soft shadow.
class _ZoomButtons extends StatelessWidget {
  final VoidCallback onIn;
  final VoidCallback onOut;

  const _ZoomButtons({required this.onIn, required this.onOut});

  @override
  Widget build(BuildContext context) {
    Widget button(Key key, IconData icon, String tip, VoidCallback onTap) =>
        Tooltip(
          message: tip,
          child: InkWell(
            key: key,
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 22, color: AppColors.text),
            ),
          ),
        );
    return Material(
      color: AppColors.surface,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(AppTheme.compactButtonRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            const Key('mapZoomIn'),
            Icons.add_rounded,
            tl('Zoom in on the farm'),
            onIn,
          ),
          Container(width: 28, height: 1, color: AppColors.grey(300)),
          button(
            const Key('mapZoomOut'),
            Icons.remove_rounded,
            tl('Zoom out'),
            onOut,
          ),
        ],
      ),
    );
  }
}

/// The reminder on the map: the line goes to the farmer's general area.
class _GeneralAreaNote extends StatelessWidget {
  final bool compact;
  final String text;

  const _GeneralAreaNote({required this.compact, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('generalAreaNote'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: compact ? 13 : 15,
            color: AppColors.brand,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              tl(text),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A person's photo as a round map marker: a coloured ring, a thin white
/// gap, then the photo — or their initials on the ring's colour when there
/// is none or it cannot be loaded. Made once per photo and colour.
class MapAvatarMarker {
  MapAvatarMarker._();

  static final Map<String, Future<BitmapDescriptor>> _made = {};

  /// The marker's size on the map, in logical pixels.
  static const double size = 52;

  static Future<BitmapDescriptor> of({
    String? photoUrl,
    required String name,
    required Color ring,
  }) {
    final key = '${photoUrl ?? ''}|$name|${ring.toARGB32()}';
    return _made.putIfAbsent(key, () => _draw(photoUrl, name, ring));
  }

  static String initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  static Future<BitmapDescriptor> _draw(
    String? photoUrl,
    String name,
    Color ring,
  ) async {
    const scale = 3.0; // drawn sharp, shown at [size]
    const px = size * scale;
    final photo = await _load(photoUrl, (px).round());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(px / 2, px / 2);
    const radius = px / 2;
    // A soft shadow under it, so it stands off the map.
    canvas.drawCircle(
      center.translate(0, 2 * scale),
      radius - 3 * scale,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2 * scale),
    );
    // A thin ring (2) and a thinner white gap (1.5), made thinner by the
    // user on 2026-11-07.
    canvas.drawCircle(center, radius - 3 * scale, Paint()..color = ring);
    canvas.drawCircle(
      center,
      radius - 5 * scale,
      Paint()..color = Colors.white,
    );
    const inner = radius - 6.5 * scale;
    final face = Rect.fromCircle(center: center, radius: inner);
    if (photo != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(face));
      paintImage(canvas: canvas, rect: face, image: photo, fit: BoxFit.cover);
      canvas.restore();
    } else {
      canvas.drawCircle(center, inner, Paint()..color = ring);
      final text = TextPainter(
        text: TextSpan(
          text: initialsOf(name),
          style: const TextStyle(
            fontFamily: 'Montserrat',
            color: Colors.white,
            fontSize: 17 * scale,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
      text.dispose();
    }
    final image = await recorder.endRecording().toImage(px.round(), px.round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: size,
      height: size,
    );
  }

  static Future<ui.Image?> _load(String? url, int width) async {
    if (url == null || url.trim().isEmpty) return null;
    try {
      final data = await NetworkAssetBundle(Uri.parse(url)).load(url);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: width,
      );
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }
}
