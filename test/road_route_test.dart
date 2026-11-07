// The Farm Location line along the roads: OSRM's answer read into points
// and a length, the line drawn bit by bit, and no route when the server
// fails (the map then draws a straight line).
import 'package:agritrade/screen/buyer_market_view.dart';
import 'package:agritrade/services/road_route_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const buyer = LatLng(14.07, 120.97);
  const farm = LatLng(14.008, 120.93);

  tearDown(() {
    RoadRouteService.client = null;
    RoadRouteService.clearCache();
  });

  test('decodes Google\'s encoded polyline', () {
    // The example in Google's own documentation.
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(points, hasLength(3));
    expect(points[0].latitude, closeTo(38.5, 1e-6));
    expect(points[0].longitude, closeTo(-120.2, 1e-6));
    expect(points[2].latitude, closeTo(43.252, 1e-6));
    expect(points[2].longitude, closeTo(-126.453, 1e-6));
  });

  test('the route runs from the buyer to the farm point, with its length', () {
    final route = RoadRouteService.parseOsrmRoute(
      '{"code":"Ok","routes":[{"distance":15092.5,'
      '"geometry":"_p~iF~ps|U_ulLnnqC"}]}',
      buyer,
      farm,
    )!;
    expect(route.points.first, buyer);
    expect(route.points.last, farm);
    expect(route.points, hasLength(4));
    expect(route.km, closeTo(15.09, 0.01));
  });

  test('no route in the answer gives none', () {
    expect(
      RoadRouteService.parseOsrmRoute('{"code":"NoRoute"}', buyer, farm),
      isNull,
    );
    expect(
      RoadRouteService.parseOsrmRoute('{"code":"Ok","routes":[]}', buyer, farm),
      isNull,
    );
  });

  test('asks OSRM once for the same two points', () async {
    var asked = 0;
    RoadRouteService.client = MockClient((request) async {
      asked++;
      expect(request.url.host, 'router.project-osrm.org');
      expect(request.url.path, contains('120.97,14.07;120.93,14.008'));
      return http.Response(
        '{"code":"Ok","routes":[{"distance":1200,'
        '"geometry":"_p~iF~ps|U_ulLnnqC"}]}',
        200,
      );
    });
    final first = await RoadRouteService.between(buyer, farm);
    final again = await RoadRouteService.between(buyer, farm);
    expect(first, isNotNull);
    expect(identical(first, again), isTrue);
    expect(asked, 1);
  });

  test('a server error gives no route, and is asked again later', () async {
    var asked = 0;
    RoadRouteService.client = MockClient((_) async {
      asked++;
      return http.Response('busy', 503);
    });
    expect(await RoadRouteService.between(buyer, farm), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(await RoadRouteService.between(buyer, farm), isNull);
    expect(asked, 2);
  });

  group('the line drawing itself', () {
    const a = LatLng(14.0, 121.0);
    const b = LatLng(14.0, 121.01);
    const c = LatLng(14.01, 121.01);

    test('nothing at the start, all of it at the end', () {
      expect(partOfLine([a, b, c], 0), [a]);
      expect(partOfLine([a, b, c], 1), [a, b, c]);
    });

    test('half way ends near the bend, on the line', () {
      final half = partOfLine([a, b, c], 0.5);
      expect(half.first, a);
      expect(half.last.latitude, closeTo(14.0, 0.0005));
      expect(half.last.longitude, closeTo(121.01, 0.0005));
    });

    test('a quarter stops part way along the first stretch', () {
      final quarter = partOfLine([a, b, c], 0.25);
      expect(quarter, hasLength(2));
      expect(quarter.last.latitude, 14.0);
      expect(quarter.last.longitude, greaterThan(121.0));
      expect(quarter.last.longitude, lessThan(121.01));
    });
  });

  test('a road distance says so', () {
    expect(approxDistanceLabel(15.09, byRoad: true), 'Approx. 15 km by road');
    expect(approxDistanceLabel(4.83, byRoad: true), 'Approx. 4.8 km by road');
    expect(approxDistanceLabel(4.83), 'Approx. 4.8 km away');
  });
}
