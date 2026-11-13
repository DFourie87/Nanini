import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/pallet_stock.dart';

DeliveryNote _note(String agent, int pallets, String date, {String produce = 'potato'}) => DeliveryNote(
    id: '$agent$date', agentName: agent, noteDate: date, pallets: const {}, mixedPallets: const [], produceType: produce, total: pallets, createdAt: DateTime(2026));

void main() {
  test('Pallets sent to each agent: this season and all', () {
    final sent = palletsSentByAgent([
      _note('B', 32, '2026-10-01'),
      _note('A', 30, '2026-10-02'),
      _note('B', 20, '2026-04-01'),
      _note('A', 500, '2026-10-03', produce: 'pepper'),
    ], from: '2026-09-01');
    expect(sent.keys, ['A', 'B']);
    expect(sent['A'], (30, 30));
    expect(sent['B'], (32, 52));
  });

  test('Pallets collected and paid for, per agent, and the difference', () {
    expect(palletCount('Pallets paid for: 31 PALLET @ R65 INCL (IN160836)'), 31);
    expect(palletInvoiceNumber('Pallets paid for: 31 PALLET @ R65 INCL (IN160836)'), 'IN160836');
    final rows = palletsCollectedAndPaidFor({'Grow Green Network': 450, 'Grow Botha Roodt': 300}, [
      PalletPurchase(id: '1', agentName: 'Grow Green Network', qty: 400, date: '2026-10-20'),
      PalletPurchase(id: '2', agentName: 'Grow Botha Roodt', qty: 180, date: '2026-10-21'),
      PalletPurchase(id: '3', agentName: 'Grow Green Network', qty: 5, date: '2026-10-22', kind: PalletEntryKind.adjust),
      PalletPurchase(id: '4', agentName: 'Grow Botha Roodt', qty: 50, date: '2026-01-10'), // last season
    ], const [
      PalletsPaidFor(agentName: 'Grow Green Network', qty: 31, date: '2026-10-22', document: 'IN160836', amount: 2015),
      PalletsPaidFor(agentName: 'Dapper Market Agents', qty: 10, date: '2026-10-23', document: 'IN1', amount: 650),
    ], from: '2026-09-01');
    expect(rows.keys, ['Dapper Market Agents', 'Grow Botha Roodt', 'Grow Green Network']);
    // collected - sent + paid for
    expect(rows['Grow Green Network'], (450, 400, 31, -19));
    expect(rows['Grow Botha Roodt'], (300, 180, 0, -120));
    expect(rows['Dapper Market Agents'], (0, 0, 10, 10));
  });

  test('What a figure is made of: the notes, collected entries or pallet invoices behind it', () {
    final notes = [_note('GN', 31, '2026-10-22'), _note('GN', 32, '2026-10-27'), _note('B', 32, '2026-10-22'), _note('GN', 30, '2026-04-01')];
    final entries = [
      PalletPurchase(id: '1', agentName: 'GN', qty: 40, date: '2026-10-30', description: 'Truck back'),
      PalletPurchase(id: '2', agentName: 'GN', qty: -2, date: '2026-10-31'),
      PalletPurchase(id: '3', agentName: 'GN', qty: 5, date: '2026-10-31', kind: PalletEntryKind.adjust),
    ];
    const paid = [PalletsPaidFor(agentName: 'GN', qty: 31, date: '2026-11-01', document: 'IN161814', amount: 2015)];
    List<PalletLine> lines(PalletFigure f, {String? agent}) => palletLines(f, notes: notes, entries: entries, paid: paid, from: '2026-09-01', agent: agent);

    final sent = lines(PalletFigure.sent, agent: 'GN');
    expect([for (final l in sent) (l.date, l.pallets)], [('2026-10-27', 32), ('2026-10-22', 31)]); // newest first, not last season's
    final collected = lines(PalletFigure.collected, agent: 'GN');
    expect([for (final l in collected) (l.what, l.pallets)], [('Returned empty', -2), ('Collected · Truck back', 40)]); // not the adjustment
    expect(lines(PalletFigure.paidFor, agent: 'GN').single.what, 'Pallet invoice IN161814 · R2015.00');
    expect(lines(PalletFigure.sent).length, 3); // every agent
    // They add up to the figures.
    final rows = palletsCollectedAndPaidFor(
        {for (final e in palletsSentByAgent(notes, from: '2026-09-01').entries) e.key: e.value.$1}, entries, paid, from: '2026-09-01');
    expect(rows['GN'], (sent.fold(0, (s, l) => s + l.pallets), collected.fold(0, (s, l) => s + l.pallets), 31, 38 - 63 + 31));
  });

  test("Pallet reconciliation with an agent: oldest first, balance at the agent after each", () {
    final r = palletReconciliation('GN',
        notes: [_note('GN', 31, '2026-10-22'), _note('GN', 32, '2026-10-27'), _note('B', 5, '2026-10-22'), _note('GN', 9, '2026-12-01')],
        entries: [PalletPurchase(id: '1', agentName: 'GN', qty: 40, date: '2026-10-30', description: 'Truck back')],
        paid: const [PalletsPaidFor(agentName: 'GN', qty: 31, date: '2026-11-01', document: 'IN161814', amount: 2015)],
        from: '2026-09-01',
        to: '2026-11-13');
    expect([for (final l in r.lines) (l.date, l.reference, l.balance)], [
      ('2026-10-22', 'Delivery note -', 31),
      ('2026-10-27', 'Delivery note -', 63),
      ('2026-10-30', '', 23),
      ('2026-11-01', 'IN161814', -8),
    ]); // not after [to], not another agent's
    expect(r.lines[2].description, 'Empty pallets collected · Truck back');
    expect((r.returned, r.collected, r.paidFor, r.balance), (63, 40, 31, -8));
  });

  test('Collected pallets Nanini paid for: bought, so they do not take the agent down', () {
    final entries = [
      PalletPurchase(id: '1', agentName: 'GN', qty: 40, date: '2026-10-30', paidQty: 10, paidAmount: 650),
    ];
    final rows = palletsCollectedAndPaidFor({'GN': 63}, entries, const [], from: '2026-09-01');
    expect(rows['GN'], (63, 40, 0, 40 - 10 - 63));
    expect(palletsPaidByNanini(entries, from: '2026-09-01', agent: 'GN'), 10);
    final lines = palletLines(PalletFigure.collected, notes: const [], entries: entries, paid: const [], from: '2026-09-01');
    expect(lines.single.what, 'Collected · 10 paid for by Nanini (R650.00)');
    final r = palletReconciliation('GN',
        notes: [_note('GN', 63, '2026-10-22')], entries: entries, paid: const [], from: '2026-09-01', to: '2026-11-13');
    expect((r.returned, r.collected, r.paidByNanini, r.balance), (63, 40, 10, 33));
    expect(r.lines.last.description, 'Empty pallets collected (10 paid for by Nanini, R650.00 incl. VAT)');
  });
}
