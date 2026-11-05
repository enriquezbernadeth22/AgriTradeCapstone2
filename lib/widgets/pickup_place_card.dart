import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_language.dart';
import '../services/order_contact_service.dart';
import '../theme/app_colors.dart';
import 'app_scaffold_messenger.dart';

/// Where the buyer picks up a confirmed pick-up order: the farm's address,
/// a small map of the farm's pin (when the farmer has set one) and Get
/// Directions, which opens Google Maps. Shared by the farmer when they
/// confirm (OrderContactService.shareFarmerContact). Until it is there —
/// or for an older order without it — the farmer's general [area] and a
/// note to agree the place in Messages.
class PickupPlaceCard extends StatefulWidget {
  final String orderId;

  /// The farmer's barangay and town, from their public profile.
  final String area;

  /// Reads the shared place (tests); OrderContactService by default.
  final Future<PickupPlace?> Function(String orderId)? load;

  const PickupPlaceCard({
    super.key,
    required this.orderId,
    required this.area,
    this.load,
  });

  @override
  State<PickupPlaceCard> createState() => _PickupPlaceCardState();
}

class _PickupPlaceCardState extends State<PickupPlaceCard> {
  late final Future<PickupPlace?> _place =
      (widget.load ?? OrderContactService.instance.pickupPlace)(widget.orderId);

  Future<void> _directions(PickupPlace place) async {
    final opened = await launchUrl(
      place.directionsUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      showAppMessage(
        context,
        tl('Could not open the map. Check that Google Maps is installed.'),
        kind: MessageKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(fontSize: 12.5, color: AppColors.grey(700));
    final value = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    );
    final note = TextStyle(fontSize: 12, color: AppColors.grey(600));

    return FutureBuilder<PickupPlace?>(
      future: _place,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        final place = snapshot.data;
        if (place == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.area.isNotEmpty) ...[
                Text(tl('Pick-up area'), style: label),
                const SizedBox(height: 2),
                Text(widget.area, style: value),
                const SizedBox(height: 6),
              ],
              Text(
                tl('Arrange the exact pick-up point and time in Messages.'),
                style: note,
              ),
            ],
          );
        }
        final pin = place.hasPin
            ? LatLng(place.latitude!, place.longitude!)
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tl('Pick-up address'), style: label),
            const SizedBox(height: 2),
            SelectableText(
              place.address.isNotEmpty ? place.address : widget.area,
              style: value,
            ),
            if (pin != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                key: const Key('pickupMap'),
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  // A still picture of the spot; Get Directions opens the
                  // real map.
                  child: IgnorePointer(
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: pin,
                        zoom: 15,
                      ),
                      liteModeEnabled:
                          defaultTargetPlatform == TargetPlatform.android,
                      zoomControlsEnabled: false,
                      myLocationButtonEnabled: false,
                      mapToolbarEnabled: false,
                      scrollGesturesEnabled: false,
                      zoomGesturesEnabled: false,
                      markers: {
                        Marker(
                          markerId: const MarkerId('pickup'),
                          position: pin,
                        ),
                      },
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('pickupDirections'),
              onPressed: () => _directions(place),
              icon: const Icon(Icons.directions_outlined, size: 18),
              label: Text(tl('Get Directions')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brand,
                side: BorderSide(color: AppColors.brand),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tl('Agree the pick-up time with the farmer in Messages.'),
              style: note,
            ),
          ],
        );
      },
    );
  }
}
