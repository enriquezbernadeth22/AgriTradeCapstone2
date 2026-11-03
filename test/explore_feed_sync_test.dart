// A farmer's new post reaches the buyer's Explore: it is never mistaken for
// a "new" post just because the first look came from the phone's saved
// copy, and it comes in at once when the buyer is at the top of the feed;
// only a buyer scrolled down gets the "new posts" pill instead.
import 'package:agritrade/screen/buyer_explore_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the saved copy does not settle the list: everything shows', () {
    final feed = exploreFeed(
      fixed: null,
      latest: {'a'},
      fromCache: true,
      atTop: true,
    );
    expect(feed.fixed, isNull);
    expect(feed.shown, {'a'});
  });

  test('a post the saved copy missed shows once the server answers', () {
    // First the saved copy (without "b"), then the server (with it).
    final first = exploreFeed(
      fixed: null,
      latest: {'a'},
      fromCache: true,
      atTop: false,
    );
    final server = exploreFeed(
      fixed: first.fixed,
      latest: {'a', 'b'},
      fromCache: false,
      atTop: false,
    );
    expect(server.shown, {'a', 'b'});
    expect(server.fixed, {'a', 'b'});
  });

  test('at the top of the feed a new post comes in at once, first', () {
    final feed = exploreFeed(
      fixed: {'a'},
      latest: {'a', 'new'},
      fromCache: false,
      atTop: true,
    );
    expect(feed.shown, contains('new'));
    expect(feed.fresh, {'new'});
    expect(feed.fixed, {'a', 'new'});
  });

  test('scrolled down, a new post waits for the pill', () {
    final feed = exploreFeed(
      fixed: {'a'},
      latest: {'a', 'new'},
      fromCache: false,
      atTop: false,
    );
    expect(feed.shown, {'a'});
    expect(feed.fresh, isEmpty);
    expect(feed.fixed, {'a'});
  });
}
