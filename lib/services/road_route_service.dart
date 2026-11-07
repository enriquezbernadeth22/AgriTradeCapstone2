import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// A way along the roads from one point to another: the points to draw and
/// its length in metres.
class RoadRoute {
  final List<LatLng> points;
  final double meters;

  const RoadRoute({required this.points, required this.meters});

  double get km => meters / 1000;
}

/// The road route between the buyer and the farmer's general area, for the
/// line on the Farm Location map (the user's design, 2026-11-07).
///
/// It comes from OSRM's public server on OpenStreetMap roads: it needs no
/// key (the app's Google key is limited to the web, so Google's Directions
/// refuses it). Each pair of points is asked once per app run, and a failure
/// or a slow answer gives null, so the map falls back to a straight line.
/// The destination is the barangay's reference point, never the farm's pin.
class RoadRouteService {
  RoadRouteService._();

  static const String _host = 'router.project-osrm.org';
  static const Duration timeout = Duration(seconds: 8);

  static final Map<String, Future<RoadRoute?>> _asked = {};

  /// Swapped for a fake in tests.
  @visibleForTesting
  static http.Client? client;

  @visibleForTesting
  static void clearCache() => _asked.clear();

  /// The driving route from [from] to [to], or null when there is none.
  static Future<RoadRoute?> between(LatLng from, LatLng to) {
    // About 10 m: a buyer standing still asks only once.
    String key(LatLng p) =>
        '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}';
    final id = '${key(from)}>${key(to)}';
    final asked = _asked.putIfAbsent(id, () => _fetch(from, to));
    // A failure is not kept: the next opening tries again.
    asked.then((route) {
      if (route == null) _asked.remove(id);
    });
    return asked;
  }

  static Future<RoadRoute?> _fetch(LatLng from, LatLng to) async {
    try {
      final uri = Uri.https(
        _host,
        '/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
        {'overview': 'full', 'geometries': 'polyline'},
      );
      final get = client?.get ?? http.get;
      final res = await get(uri).timeout(timeout);
      if (res.statusCode != 200) return null;
      return parseOsrmRoute(res.body, from, to);
    } catch (_) {
      return null;
    }
  }

  /// The first route in an OSRM answer, joined to [from] and [to] at its
  /// ends (the road starts and stops at the nearest street, the photos sit
  /// on the points themselves).
  @visibleForTesting
  static RoadRoute? parseOsrmRoute(String body, LatLng from, LatLng to) {
    final json = jsonDecode(body);
    if (json is! Map || json['code'] != 'Ok') return null;
    final routes = json['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final route = routes.first;
    if (route is! Map) return null;
    final geometry = route['geometry'];
    final meters = (route['distance'] as num?)?.toDouble();
    if (geometry is! String || meters == null) return null;
    final road = decodePolyline(geometry);
    if (road.length < 2) return null;
    return RoadRoute(points: [from, ...road, to], meters: meters);
  }
}

/// Google's encoded polyline format (precision 5), as OSRM sends it.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;
  int next() {
    var result = 0;
    var shift = 0;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  }

  try {
    while (index < encoded.length) {
      lat += next();
      lng += next();
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
  } catch (_) {
    // A cut-off string: what was read so far.
  }
  return points;
}

/// The first [fraction] (0 to 1) of the line through [points], by length:
/// the line drawing itself along the road.
List<LatLng> partOfLine(List<LatLng> points, double fraction) {
  if (points.length < 2 || fraction >= 1) return List.of(points);
  if (fraction <= 0) return [points.first];
  final lengths = <double>[];
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    final d = _flatDistance(points[i - 1], points[i]);
    lengths.add(d);
    total += d;
  }
  if (total == 0) return List.of(points);
  var left = total * fraction;
  final part = <LatLng>[points.first];
  for (var i = 1; i < points.length; i++) {
    final d = lengths[i - 1];
    if (left >= d) {
      part.add(points[i]);
      left -= d;
      continue;
    }
    final a = points[i - 1];
    final b = points[i];
    final t = d == 0 ? 0.0 : left / d;
    part.add(
      LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      ),
    );
    break;
  }
  return part;
}

// Good enough over a few dozen kilometres for splitting a line by length.
double _flatDistance(LatLng a, LatLng b) {
  final dLat = b.latitude - a.latitude;
  final dLng =
      (b.longitude - a.longitude) * math.cos(a.latitude * math.pi / 180);
  return math.sqrt(dLat * dLat + dLng * dLng);
}
