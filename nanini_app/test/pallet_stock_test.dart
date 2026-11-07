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
}
