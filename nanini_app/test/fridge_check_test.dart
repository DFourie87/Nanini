import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/capture/fridge_sheet_capture.dart';
import 'package:nanini_app/features/tuckshop/fridge_check.dart';
import 'package:nanini_app/features/tuckshop/tuckshop_models.dart';

TuckshopItem _item(String id, String name) => TuckshopItem(id: id, name: name, profitPct: 0, lastCostPrice: 30, fixedSellPrice: 35);
TuckshopCount _count(String item, String date, double qty, {String at = '2026-01-01T00:00:00Z'}) =>
    TuckshopCount(id: '$item$date$at', itemId: item, date: date, qty: qty, createdAt: at);
TuckshopPurchase _sale(String item, String date, double qty) =>
    TuckshopPurchase(id: '$item$date$qty', employeeId: 'e1', itemId: item, qty: qty, revenue: qty * 35, cogs: 0, date: date);
TuckshopStockPurchase _bought(String item, String date, double qty) =>
    TuckshopStockPurchase(id: '$item$date', itemId: item, qty: qty, costPrice: 30, total: qty * 30, date: date);

void main() {
  final wors = _item('w', 'Wors'), chicken = _item('c', 'Chicken pieces');

  test('Fridge items: wors and chicken', () {
    expect(isFridgeItemName('Boerewors'), isTrue);
    expect(isFridgeItemName('Chicken pieces'), isTrue);
    expect(isFridgeItemName('Bread'), isFalse);
  });

  test('Opening + bought - taken - written off = should be; less the count = short', () {
    final checks = fridgeChecks(
      items: [wors, chicken],
      counts: [_count('w', '2026-10-31', 20), _count('w', '2026-11-30', 8), _count('c', '2026-11-30', 15)],
      bought: [
        _bought('w', '2026-10-31', 50), // restocked on pay day after the count: this period
        _bought('w', '2026-11-30', 40), // restocked after this count: the next period
      ],
      sales: [
        _sale('w', '2026-10-31', 5), // on the opening count's day: the period before
        _sale('w', '2026-11-12', 3), // a phone sale
        _sale('w', '2026-11-30', 55), // the fridge sheet, dated pay day
      ],
      writeoffs: [
        TuckshopWriteoff(id: 'x1', itemId: 'w', qty: 1, cogs: 30, reason: 'Gone off', date: '2026-11-20'),
        TuckshopWriteoff(id: 'x2', itemId: 'w', qty: 2, cogs: 60, reason: shortWriteoffReason('2026-10-31'), date: '2026-11-02'),
      ],
    );
    // Newest first; chicken's first count only starts its check.
    expect(checks.map((c) => '${c.item.name} ${c.closeDate}'), ['Chicken pieces 2026-11-30', 'Wors 2026-11-30', 'Wors 2026-10-31']);
    expect(checks.first.isFirst, isTrue);
    expect(checks.first.short, 0);
    final w = checks[1];
    expect(w.opening, 20);
    expect(w.bought, 50);
    expect(w.taken, 58);
    expect(w.writtenOff, 1); // a shortage write-off is not counted again
    expect(w.shouldBe, 11);
    expect(w.counted, 8);
    expect(w.short, 3);
    expect(w.shortWrittenOff, isFalse);
  });

  test('A recount the same day replaces the count; a written-off shortage says so', () {
    final checks = fridgeChecks(
      items: [wors],
      counts: [
        _count('w', '2026-10-31', 10),
        _count('w', '2026-11-30', 2, at: '2026-11-30T10:00:00Z'),
        _count('w', '2026-11-30', 4, at: '2026-11-30T11:00:00Z'),
      ],
      bought: const [],
      sales: [_sale('w', '2026-11-15', 5)],
      writeoffs: [TuckshopWriteoff(id: 'x', itemId: 'w', qty: 1, cogs: 30, reason: shortWriteoffReason('2026-11-30'), date: '2026-12-01')],
    );
    expect(checks.length, 2);
    expect(checks.first.counted, 4);
    expect(checks.first.short, 1);
    expect(checks.first.shortWrittenOff, isTrue);
  });
}
