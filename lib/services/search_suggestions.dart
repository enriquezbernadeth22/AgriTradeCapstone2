/// Suggested searches while a buyer types [typed]: supported commodity
/// names, listing names and farmer names that contain it — those starting
/// with it first — without repeats (whatever their capitals), at most
/// [limit]. Nothing while the field is empty.
List<String> suggestedSearchTerms(
  String typed, {
  Iterable<String> commodities = const [],
  Iterable<Map<String, dynamic>> listings = const [],
  int limit = 8,
}) {
  final q = typed.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final candidates = <String>[
    ...commodities,
    for (final listing in listings) ...[
      (listing['name'] ?? '').toString(),
      (listing['farmerName'] ?? '').toString(),
    ],
  ];
  final seen = <String>{};
  final starts = <String>[];
  final contains = <String>[];
  for (final raw in candidates) {
    final term = raw.trim();
    final key = term.toLowerCase();
    if (term.isEmpty || !key.contains(q) || !seen.add(key)) continue;
    (key.startsWith(q) ? starts : contains).add(term);
  }
  return [...starts, ...contains].take(limit).toList();
}
