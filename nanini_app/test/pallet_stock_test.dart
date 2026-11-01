import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/pallet_stock.dart';

PalletPurchase _e(String agent, int qty, String date, [PalletEntryKind kind = PalletEntryKind.collected]) =>
    PalletPurchase(id: '$agent$date$qty', agentName: agent, qty: qty, date: date, kind: kind);
DeliveryNote _note(String agent, int pallets, String date, {String produce = 'potato'}) => DeliveryNote(
    id: '$agent$date', agentName: agent, noteDate: date, pallets: const {}, mixedPallets: const [], produceType: produce, total: pallets, createdAt: DateTime(2026));

void main() {
  test('Pallets on the floor per agent: count + collected - 8% not useable + adjusted - returned loaded, after the count', () {
    const gn = 'Grow Green Network', br = 'Grow Botha Roodt Johannesburg', dapper = 'Dapper Market Agents';
    final b = palletBalances([
      _e(br, 180, '2026-09-01'), // before the count: not counted
      for (final a in [gn, br, dapper]) _e(a, 0, '2026-09-19', PalletEntryKind.count),
      _e(gn, 400, '2026-09-20'),
      _e(br, 100, '2026-10-10'),
      _e(gn, -2, '2026-10-12', PalletEntryKind.adjust),
    ], [
      _note(gn, 32, '2026-10-05'),
      _note(dapper, 30, '2026-10-01'), // no pallets collected there: its pallets came from the others
      _note(br, 20, '2026-09-10'), // before the count
      _note(gn, 500, '2026-10-06', produce: 'pepper'), // boxes, not pallets
    ]);
    expect(b.keys, [dapper, br, gn]);
    expect(b[gn]!.counted, 0);
    expect(b[gn]!.collected, 400);
    expect(b[gn]!.losses, 32); // 8% of 400 not useable
    expect(b[gn]!.adjusted, -2);
    expect(b[gn]!.returned, 32);
    expect(b[gn]!.onFloor, 334);
    expect(b[br]!.losses, 8);
    expect(b[br]!.onFloor, 92);
    expect(b[dapper]!.losses, 0);
    expect(b[dapper]!.onFloor, -30);
    expect(PalletBalance.total(b.values).losses, 40);
    expect(PalletBalance.total(b.values).onFloor, 396);
  });

  test('Never counted: everything counts', () {
    final b = palletBalances([_e('A', 10, '2026-01-01')], [_note('A', 4, '2026-01-02')]);
    expect(b['A']!.counted, isNull);
    expect(b['A']!.losses, 1); // 8% of 10, rounded
    expect(b['A']!.onFloor, 5);
  });
}
