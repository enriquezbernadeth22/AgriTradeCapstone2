/// When a list's filters above it hide and come back as the list scrolls
/// (Explore's category pills and location dropdown): scrolling down hides
/// them; they come back only after a deliberate scroll back up — at least
/// [showAfterUp] in one go, about two short swipes, so a small wobble while
/// reading does not bring them back — or on reaching the top.
class FiltersOnScroll {
  FiltersOnScroll({this.showAfterUp = 140, this.hideAfter = 40});

  /// How far back up, in one go, brings the filters back.
  final double showAfterUp;

  /// How far down the list must be before scrolling hides them.
  final double hideAfter;

  // How far the list has gone up since it last went down.
  double _scrolledUp = 0;

  /// One step of scrolling: [delta] (positive going down), the list's
  /// position [pixels] afterwards, and whether a finger is on it
  /// ([dragging]; a fling that is still going does not hide them). Returns
  /// true to hide the filters, false to show them, null to leave them.
  bool? update({
    required double delta,
    required double pixels,
    required bool dragging,
  }) {
    bool? hide;
    if (delta > 0) {
      // Going down: the way back up is counted afresh.
      _scrolledUp = 0;
      if (pixels > hideAfter && dragging) hide = true;
    } else if (delta < 0) {
      _scrolledUp += -delta;
      if (_scrolledUp >= showAfterUp) hide = false;
    }
    if (pixels <= 0) hide = false;
    return hide;
  }

  /// The filters were shown some other way (back to the top, new posts).
  void reset() => _scrolledUp = 0;
}
