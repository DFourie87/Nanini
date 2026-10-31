import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/bag_stock.dart';
import 'package:nanini_app/features/delivery/delivery_bags_screen.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_repository.dart';

DeliveryNote _note(String date, {String produce = 'potato', Map<String, dynamic> pallets = const {}, List<dynamic> mixed = const [], Map<String, dynamic>? detail}) =>
    DeliveryNote(
      id: 'n$date$produce',
      noteDate: date,
      pallets: pallets,
      mixedPallets: mixed,
      produceType: produce,
      produceDetail: detail,
      total: 0,
      createdAt: DateTime(2026),
    );

BagPurchase _bought(String item, int qty, {String date = '2026-02-25', ProduceType produce = ProduceType.potato, String? key}) =>
    BagPurchase(id: '$item$date$qty', date: date, produce: produce, item: item, qty: qty, reference: key == null ? null : 'PSI32077', sourceKey: key);

class _FakeRepo extends DeliveryRepository {
  _FakeRepo(this.purchases, this.notes);
  final List<BagPurchase> purchases;
  final List<DeliveryNote> notes;
  @override
  Stream<List<BagPurchase>> watchBagPurchases() => Stream.value(purchases);
  @override
  Stream<List<DeliveryNote>> watchNotes() => Stream.value(notes);
}

void main() {
  final notes = [
    // 2 pallets Baby + 1 Small (110 bags each, all in the Small bag), a mixed
    // pallet with 40 Small and 25 Large/Medium bags, 3 pallets of 7kg Medium.
    _note('2026-03-02', pallets: {'baby10': 2, 'small10': 1, 'med7': 3}, mixed: [
      {'small10': 40, 'largemed10': 25},
    ]),
    // Before 1 Feb 2025: not counted.
    _note('2025-01-20', pallets: {'small10': 10}),
    _note('2026-03-03', produce: 'pepper', detail: {'5kgRed': 120, '4kgGreen': 8}),
    _note('2026-03-04', produce: 'butternut', detail: {'10kg': 300, '7kg': 0}),
  ];
  final purchases = [
    _bought('small10', 8000, key: 'crownbag:PSI32077:3'),
    _bought('med7', 17000, key: 'crownbag:PSI32077:4'),
    _bought('small10', -500, date: '2026-03-10'), // returned
    _bought('small10', 1000, date: '2024-12-01'), // before the start
    _bought('5kgRed', 1000, produce: ProduceType.pepper),
  ];

  test('Potato bags: Baby and Small in the Small bag, mixed pallets by the bag, 1% losses', () {
    final b = bagBalances(ProduceType.potato, purchases, notes);
    expect(b['small10']!.bought, 7500);
    expect(b['small10']!.used, 3 * 110 + 40);
    expect(b['small10']!.losses, 75);
    expect(b['small10']!.available, 7500 - 75 - 370);
    expect(b['largemed10']!.used, 25);
    expect(b['largemed10']!.available, -25); // used, none bought: shows short
    expect(b['med7']!.used, 3 * 140);
    expect(b['med7']!.available, 17000 - 170 - 420);
    expect(b.keys, kPotatoBags.map((k) => k.key));
  });

  test('Pepper boxes and butternut bags from the delivery notes', () {
    final p = bagBalances(ProduceType.pepper, purchases, notes);
    expect(p['5kgRed']!.available, 1000 - 10 - 120);
    expect(p['4kgGreen']!.used, 8);
    final b = bagBalances(ProduceType.butternut, purchases, notes);
    expect(b['10kg']!.used, 300);
    expect(b['7kg']!.used, 0);
  });

  testWidgets('Bags/Boxes tab: on the floor per bag, then the boxes for peppers', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DeliveryBagsScreen(repo: _FakeRepo(purchases, notes)))));
    await tester.pumpAndSettle();
    expect(find.text('Potatoes (Bags)'), findsOneWidget);
    expect(find.text('10kg 1st Small (Baby and Small)'), findsOneWidget);
    expect(find.text('7 055'), findsOneWidget); // 7 500 - 75 - 370
    expect(find.text('Bought 7 500 · losses 75 · used 370'), findsOneWidget);
    // From email: Crown Bag's invoice, can't be deleted here; typed in: can.
    expect(find.textContaining('Crown Bag PSI32077'), findsNWidgets(2));
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
    await tester.tap(find.text('Peppers (Boxes)'));
    await tester.pumpAndSettle();
    expect(find.text('5kg Red'), findsOneWidget);
    expect(find.text('870'), findsWidgets);
    expect(find.text('Add boxes received'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
