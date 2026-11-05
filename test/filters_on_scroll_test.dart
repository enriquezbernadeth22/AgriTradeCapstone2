// Explore's filters (category pills, location dropdown) hide while the
// products scroll down, and come back only after a deliberate scroll back
// up — about two short swipes — or at the top.
import 'package:agritrade/services/filters_on_scroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scrolling down with a finger hides them, past the first rows', () {
    final f = FiltersOnScroll();
    expect(f.update(delta: 20, pixels: 20, dragging: true), isNull);
    expect(f.update(delta: 30, pixels: 50, dragging: true), isTrue);
  });

  test('a small scroll up does not bring them back', () {
    final f = FiltersOnScroll();
    f.update(delta: 400, pixels: 800, dragging: true);
    expect(f.update(delta: -60, pixels: 740, dragging: true), isNull);
  });

  test('a deliberate scroll up does — about two swipes', () {
    final f = FiltersOnScroll();
    f.update(delta: 400, pixels: 800, dragging: true);
    expect(f.update(delta: -70, pixels: 730, dragging: true), isNull);
    expect(f.update(delta: -80, pixels: 650, dragging: true), isFalse);
  });

  test('going down again starts the count afresh', () {
    final f = FiltersOnScroll();
    f.update(delta: 400, pixels: 800, dragging: true);
    f.update(delta: -100, pixels: 700, dragging: true);
    f.update(delta: 10, pixels: 710, dragging: true);
    expect(f.update(delta: -100, pixels: 610, dragging: true), isNull);
  });

  test('reaching the top always shows them', () {
    final f = FiltersOnScroll();
    f.update(delta: 400, pixels: 800, dragging: true);
    expect(f.update(delta: -10, pixels: 0, dragging: false), isFalse);
  });

  test('a fling still going does not hide them by itself', () {
    final f = FiltersOnScroll();
    expect(f.update(delta: 50, pixels: 300, dragging: false), isNull);
  });
}
