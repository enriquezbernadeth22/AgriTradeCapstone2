import 'dart:js_interop';

// Set by web/index.html the moment the page opens, when its own loading bar
// (drawn in HTML while Flutter downloads) begins to fill.
@JS('agriTradeSplashStart')
external JSNumber? get _splashStart;

@JS('agriTradeSplashStart')
external set _splashStart(JSNumber? value);

/// When the web page's own loading bar began filling, so Flutter's bar can
/// carry on from the same point instead of starting over. Taken once: it
/// is cleared as it is read, so a hot restart (which keeps the page, but
/// not its bar) starts a fresh fill instead of thinking the bar is full.
/// Null when the page did not set it.
DateTime? takePageSplashStart() {
  final ms = _splashStart?.toDartDouble;
  _splashStart = null;
  if (ms == null || ms.isNaN) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms.round());
}
