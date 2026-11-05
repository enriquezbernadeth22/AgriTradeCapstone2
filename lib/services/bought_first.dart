/// How many times a buyer has bought each product (by commodity, else by
/// product name, lower-cased), from their own [orders]. Rejected and
/// cancelled orders are not purchases.
Map<String, int> boughtCounts(Iterable<Map<String, dynamic>> orders) {
  final counts = <String, int>{};
  for (final order in orders) {
    final status = (order['status'] ?? '').toString().toLowerCase();
    if (status == 'rejected' || status == 'cancelled') continue;
    final key = productKey(order['commodity'] ?? order['productName']);
    if (key.isEmpty) continue;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

/// The product a listing or an order is about, for matching the two.
String productKey(dynamic value) =>
    (value ?? '').toString().trim().toLowerCase();

/// [items] with the products the buyer buys most first — the most often
/// bought first — and the rest after, each group keeping its order
/// ([items]' own ranking or shuffle). Nothing is left out. [dataOf] reads a
/// listing (its commodity, else its name).
List<T> boughtFirst<T>(
  List<T> items,
  Map<String, int> counts,
  Map<String, dynamic> Function(T item) dataOf,
) {
  if (counts.isEmpty) return items;
  int timesBought(T item) {
    final data = dataOf(item);
    return counts[productKey(data['commodity'] ?? data['name'])] ?? 0;
  }

  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final byBought = timesBought(b.$2).compareTo(timesBought(a.$2));
    return byBought != 0 ? byBought : a.$1.compareTo(b.$1);
  });
  return [for (final (_, item) in indexed) item];
}
