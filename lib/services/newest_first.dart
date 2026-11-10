import 'package:cloud_firestore/cloud_firestore.dart';

/// When a listing was posted, in milliseconds. A listing just posted whose
/// server time has not come back yet (no 'createdAt' on the phone's copy)
/// counts as the newest of all.
int postedAtMillis(Map<String, dynamic> data) {
  final created = data['createdAt'];
  if (created is Timestamp) return created.millisecondsSinceEpoch;
  if (created is DateTime) return created.millisecondsSinceEpoch;
  return 8640000000000000; // The latest time a DateTime can hold.
}

/// [items] from the newest post to the oldest, by when each was posted
/// ([postedAtMillis]): Explore's order (system testing, 2026-11-09). Two
/// posted at the same moment keep the order they came in.
List<T> newestFirst<T>(
  Iterable<T> items,
  Map<String, dynamic> Function(T item) dataOf,
) {
  final indexed = items.toList().asMap().entries.toList();
  indexed.sort((a, b) {
    final byTime = postedAtMillis(
      dataOf(b.value),
    ).compareTo(postedAtMillis(dataOf(a.value)));
    return byTime != 0 ? byTime : a.key.compareTo(b.key);
  });
  return [for (final e in indexed) e.value];
}
