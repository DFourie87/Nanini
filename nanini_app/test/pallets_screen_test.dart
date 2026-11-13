import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_pallets_screen.dart';
import 'package:nanini_app/features/delivery/delivery_repository.dart';
import 'package:nanini_app/features/delivery/pallet_report_xlsx.dart';
import 'package:nanini_app/features/delivery/pallet_stock.dart';

class _Repo extends DeliveryRepository {
  @override
  Stream<List<DeliveryNote>> watchNotes() => Stream.value([
        DeliveryNote(id: 'a', noteNumber: 261013, agentName: 'Grow Green Network', noteDate: '2026-10-27', field: 'Field 2', pallets: const {}, mixedPallets: const [], produceType: 'potato', total: 32, createdAt: DateTime(2026)),
        DeliveryNote(id: 'b', noteNumber: 261016, agentName: 'Grow Green Network', noteDate: '2026-10-28', field: 'Field 2', pallets: const {}, mixedPallets: const [], produceType: 'potato', total: 32, createdAt: DateTime(2026)),
      ]);
  @override
  Stream<List<PalletPurchase>> watchPurchases() => Stream.value([PalletPurchase(id: '1', agentName: 'Grow Green Network', qty: 20, date: '2026-11-01', description: 'Truck back')]);
  @override
  Future<List<PalletsPaidFor>> fetchPalletsPaidFor() async =>
      const [PalletsPaidFor(agentName: 'Grow Green Network', qty: 31, date: '2026-11-01', document: 'IN161814', amount: 2015)];
  @override
  Future<List<MarketAgent>> fetchCustomerChoices() async => [];
}

void main() {
  testWidgets('Pallets: tap a number to see how it is made up; no invoice list below', (tester) async {
    final saved = <String, Uint8List>{};
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DeliveryPalletsScreen(
                repo: _Repo(),
                save: (n, b) async {
                  saved[n] = b;
                  return true;
                }))));
    await tester.pumpAndSettle();
    expect(find.textContaining("the agent's pallet invoices"), findsNothing);

    await tester.tap(find.byKey(const Key('pallets_returned_Grow Green Network')));
    await tester.pumpAndSettle();
    expect(find.text('Returned -- Grow Green Network'), findsOneWidget);
    expect(find.text('Delivery note 261016 · Field 2'), findsOneWidget);
    expect(find.text('64 pallets'), findsOneWidget);
    Navigator.of(tester.element(find.text('Returned -- Grow Green Network'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pallets_paid_all')));
    await tester.pumpAndSettle();
    expect(find.text('Pallet invoice IN161814 · R2015.00'), findsOneWidget);
    Navigator.of(tester.element(find.text('Paid for -- all agents'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pallets_difference_Grow Green Network')));
    await tester.pumpAndSettle();
    // 20 collected - 64 sent + 31 paid for = -13
    expect(find.text('= Difference'), findsOneWidget);
    expect(find.text('Grow Green Network owes Nanini 13 pallets.'), findsOneWidget);
    Navigator.of(tester.element(find.text('= Difference'))).pop();
    await tester.pumpAndSettle();

    // Columns: Collected, Returned, Paid for, Difference.
    final heads = ['Collected', 'Returned', 'Paid for', 'Difference'].map((h) => tester.getCenter(find.text(h)).dx).toList();
    expect(heads, [...heads]..sort());

    // Tap the agent: export its pallet movements.
    await tester.tap(find.byKey(const Key('pallets_agent_Grow Green Network')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pallets_export_all')));
    await tester.pumpAndSettle();
    expect(saved.keys.single, startsWith('Pallet movement reconciliation - Grow Green Network - to '));
    final x = Excel.decodeBytes(saved.values.single);
    final sheet = x.tables.values.single;
    String cell(int r, int c) => sheet.rows[r][c]?.value?.toString() ?? '';
    expect(cell(0, 0), 'Pallet movement reconciliation');
    expect(cell(1, 0), 'between Nanini Boerdery and Grow Green Network');
    // Summary: 20 collected - 64 sent back full + 31 paid for by the agent = -13: the agent owes Nanini 13.
    final all = [for (var r = 0; r < sheet.maxRows; r++) [for (var c = 0; c < 7; c++) cell(r, c)]];
    expect(all.any((r) => r[0] == 'Balance: pallets owed by Grow Green Network to Nanini' && r[6] == '13'), isTrue);
    expect(all.any((r) => r[0] == 'Total' && r[3] == '20' && r[4] == '64' && r[5] == '31' && r[6] == '-13'), isTrue);
    expect(all.any((r) => r.contains('Paid for by Nanini')), isFalse); // none bought: no column
    expect(all.any((r) => r[1] == 'Delivery note 261016' && r[4] == '32'), isTrue);
    expect(tester.takeException(), isNull);
  });

  test('The reconciliation report gets a "Paid for by Nanini" column only when some were bought', () {
    final r = palletReconciliation('Dapper',
        notes: [
          DeliveryNote(id: 'a', noteNumber: 26106, agentName: 'Dapper', noteDate: '2026-10-21', pallets: const {}, mixedPallets: const [], produceType: 'potato', total: 32, createdAt: DateTime(2026)),
        ],
        entries: [PalletPurchase(id: '1', agentName: 'Dapper', qty: 30, date: '2026-10-30', paidQty: 10, paidAmount: 650)],
        paid: const [],
        from: '2026-09-01',
        to: '2026-11-13');
    final sheet = Excel.decodeBytes(palletReconciliationXlsx(r, preparedOn: '2026-11-13')).tables.values.single;
    final all = [for (final row in sheet.rows) [for (final c in row) c?.value?.toString() ?? '']];
    final head = all.firstWhere((x) => x.isNotEmpty && x[0] == 'Date');
    expect(head, ['Date', 'Reference', 'Description', 'Collected', 'Paid for by Nanini', 'Returned', 'Paid for by agent', 'Due to agent']);
    // 30 collected - 10 paid for by Nanini - 32 sent back full = -12: Dapper owes Nanini 12.
    expect(all.firstWhere((x) => x.isNotEmpty && x[0] == 'Total').sublist(3), ['30', '10', '32', '0', '-12']);
    expect(all.any((x) => x.isNotEmpty && x[0].startsWith('Less: pallets paid for by Nanini') && x.last == '10'), isTrue);
    expect(all.any((x) => x.isNotEmpty && x[0] == 'Balance: pallets owed by Dapper to Nanini' && x.last == '12'), isTrue);
  });
}
