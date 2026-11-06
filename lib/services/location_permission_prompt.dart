import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../l10n/app_language.dart';
import '../widgets/permission_rationale_dialog.dart';

/// Explains why (if the OS hasn't decided yet) and then requests location
/// access. Shared by every screen that wants to ask for location contextually
/// — the buyer map view, the post-registration buyer prompt, and the farmer
/// registration's barangay picker — so the rationale wording and flow stay
/// consistent no matter where it's triggered from.
///
/// If the OS has already permanently denied the permission, this shows a
/// "go to Settings" dialog instead of calling Geolocator.requestPermission()
/// again — that call would never show a system dialog at that point, so
/// retrying it would just silently fail with no way for the user to fix it.
///
/// Returns true if permission ends up granted (whileInUse or always).
Future<bool> maybeRequestLocationPermission(
  BuildContext context, {
  required String title,
  required String message,
  List<String>? bullets,
  String denyLabel = 'Not now',
  String allowLabel = 'Continue',
}) async {
  var permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.deniedForever) {
    if (!context.mounted) return false;
    final openSettings = await showPermissionRationale(
      context,
      icon: Icons.location_off_outlined,
      title: title,
      message:
          'Location access for AgriTrade+ is currently turned off in your '
          'device settings. Please enable it there to use this feature.',
      denyLabel: 'Not now',
      allowLabel: 'Open Settings',
    );
    if (openSettings) await Geolocator.openAppSettings();
    return false;
  }

  if (permission == LocationPermission.denied) {
    if (!context.mounted) return false;
    final proceed = await showPermissionRationale(
      context,
      icon: Icons.location_on_outlined,
      title: title,
      message: message,
      bullets: bullets,
      denyLabel: denyLabel,
      allowLabel: allowLabel,
    );
    if (!proceed) return false;
    if (!context.mounted) return false;
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}

/// Why a farmer is asked for location, in one sentence: kept short so a
/// farmer reads it all (the full wording is PrivacyPolicyScreen section E).
const kFarmerLocationMessage =
    'AgriTrade+ uses your location to show buyers how far your farm is, '
    'help with delivery or pick-up, and give area-based market insights.';

/// The two things a farmer needs to know about who sees their location.
const kFarmerLocationPoints = [
  'Buyers see only your barangay, town and province.',
  'Your exact location stays private unless an order needs it.',
];

/// The one canonical "why we need your location" explanation for Farmer
/// accounts — same title/wording everywhere a farmer screen asks for
/// location, per AgriTrade+'s location-privacy policy (see PrivacyPolicyScreen
/// section E). It is asked right after the farmer taps something that needs
/// location, so it does not repeat what that was.
Future<bool> requestFarmerLocationPermission(BuildContext context) {
  return maybeRequestLocationPermission(
    context,
    title: tl('Set Your Farm Location'),
    message: kFarmerLocationMessage,
    bullets: [for (final point in kFarmerLocationPoints) tl(point)],
    denyLabel: 'Not Now',
    allowLabel: 'Allow Location',
  );
}

/// The one canonical "why we need your location" explanation for Buyer
/// accounts — see PrivacyPolicyScreen section E for the written policy this
/// wording matches.
Future<bool> requestBuyerLocationPermission(BuildContext context) {
  return maybeRequestLocationPermission(
    context,
    title: 'Allow Location Access',
    message:
        'AgriTrade+ uses your location to estimate distance, support '
        'delivery or pick-up, and show nearby marketplace information. Your '
        'exact location is not shown publicly.',
    denyLabel: 'Not Now',
    allowLabel: 'Allow Location',
  );
}
