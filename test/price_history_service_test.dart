import 'package:agritrade/services/price_history_service.dart';
import 'package:flutter_test/flutter_test.dart';

PriceHistoryEntry _entry(
  double price,
  double? previous, {
  bool active = true,
}) => PriceHistoryEntry(
  commodity: 'Corn',
  category: 'Grains',
  unit: 'kg',
  price: price,
  previous: previous,
  effectiveDate: DateTime(2026, 10, 1),
  recordedAt: DateTime(2026, 10, 1, 9, 30),
  recordedBy: 'admin@agritrade.ph',
  isActive: active,
);

void main() {
  test('the change from the previous reference price', () {
    expect(_entry(42, 40).changeLabel, '+₱2.00 (+5.0%)');
    expect(_entry(38, 40).changeLabel, '−₱2.00 (−5.0%)');
    expect(_entry(40, 40).changeLabel, 'No change');
    expect(_entry(40, null).changeLabel, 'First price');
    expect(_entry(40, null).change, isNull);
  });

  test('the export table has every column, archived commodities marked', () {
    final section = PriceHistoryService.section([
      _entry(42, 40),
      _entry(40, null, active: false),
    ]);
    expect(section.headers, [
      'Effective Date',
      'Commodity',
      'Category',
      'Unit',
      'Price',
      'Previous Price',
      'Change',
      'Recorded',
      'Recorded By',
    ]);
    expect(section.rows.first, [
      'Oct 1, 2026',
      'Corn',
      'Grains',
      'kg',
      '₱42.00',
      '₱40.00',
      '+₱2.00 (+5.0%)',
      'Oct 1, 2026 · 9:30 AM',
      'admin@agritrade.ph',
    ]);
    expect(section.rows.last[1], 'Corn (archived)');
    expect(section.rows.last[5], '—');
  });
}
