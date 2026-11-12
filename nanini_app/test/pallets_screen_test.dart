import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_pallets_screen.dart';
import 'package:nanini_app/features/delivery/delivery_repository.dart';
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
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DeliveryPalletsScreen(repo: _Repo()))));
    await tester.pumpAndSettle();
    expect(find.textContaining("the agent's pallet invoices"), findsNothing);

    await tester.tap(find.byKey(const Key('pallets_sent_Grow Green Network')));
    await tester.pumpAndSettle();
    expect(find.text('Sent -- Grow Green Network'), findsOneWidget);
    expect(find.text('Delivery note 261016 · Field 2'), findsOneWidget);
    expect(find.text('64 pallets'), findsOneWidget);
    Navigator.of(tester.element(find.text('Sent -- Grow Green Network'))).pop();
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
    expect(find.textContaining('13 pallets are still out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
