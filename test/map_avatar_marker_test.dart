// The map's people markers: a round photo (initials without one) with a
// coloured ring, in place of a pin (FarmBuyerMap).
import 'dart:io';

import 'package:agritrade/widgets/farm_buyer_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('initials: first and last name, or the one name', () {
    expect(MapAvatarMarker.initialsOf('Juan Dela Cruz'), 'JC');
    expect(MapAvatarMarker.initialsOf('maria'), 'M');
    expect(MapAvatarMarker.initialsOf('  '), '?');
  });

  testWidgets('without a photo it is drawn with the initials, at its size', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final marker = await MapAvatarMarker.of(
        photoUrl: null,
        name: 'Juan Santos',
        ring: FarmBuyerMap.farmerRing,
      );
      expect(marker, isA<BytesMapBitmap>());
      final bytes = marker as BytesMapBitmap;
      expect(bytes.width, MapAvatarMarker.size);
      expect(bytes.byteData.lengthInBytes, greaterThan(1000));
      final out = Platform.environment['MARKER_OUT'];
      if (out != null) File(out).writeAsBytesSync(bytes.byteData);
      // Made once: the same marker comes back.
      expect(
        identical(
          marker,
          await MapAvatarMarker.of(
            photoUrl: null,
            name: 'Juan Santos',
            ring: FarmBuyerMap.farmerRing,
          ),
        ),
        isTrue,
      );
    });
  });
}
