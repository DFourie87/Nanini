import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/bag_stock.dart';
import 'package:nanini_app/features/delivery/delivery_bags_screen.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_repository.dart';
import 'package:nanini_app/features/sales/potato_fields.dart';

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

BagPurchase _bought(String item, int qty,
        {String date = '2026-02-25', ProduceType produce = ProduceType.potato, String? key, BagEntryKind kind = BagEntryKind.bought, String? why, String at = ''}) =>
    BagPurchase(
        id: '$item$date$qty${kind.name}$at',
        date: date,
        produce: produce,
        item: item,
        qty: qty,
        kind: kind,
        reference: key?.split(':')[1],
        description: why,
        sourceKey: key,
        createdAt: at);

class _FakeRepo extends DeliveryRepository {
  _FakeRepo(this.purchases, this.notes, [this.unsent = const []]);
  final List<BagPurchase> purchases;
  final List<DeliveryNote> notes;
  final List<UnsentPallets> unsent;
  @override
  Future<List<UnsentPallets>> fetchUnsentPallets() async => unsent;
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
    // Before 1 Feb 2026: not counted.
    _note('2026-01-20', pallets: {'small10': 10}),
    _note('2026-03-03', produce: 'pepper', detail: {'5kgRed': 120, '4kgGreen': 8}),
    _note('2026-03-04', produce: 'butternut', detail: {'10kg': 300, '7kg': 0}),
  ];
  final purchases = [
    _bought('small10', 8000, key: 'crownbag:PSI32077:3'),
    _bought('med7', 17000, key: 'crownbag:PSI32077:4'),
    _bought('small10', -500, date: '2026-03-10'), // returned
    _bought('small10', 1000, date: '2025-10-03', key: 'crownbag:PSI31107:4'), // before 1 Feb 2026: left out
    _bought('5kgRed', 1000, produce: ProduceType.pepper),
  ];

  test('Potato bags: Baby and Small in the Small bag, mixed pallets by the bag, 0.5% losses', () {
    final b = bagBalances(ProduceType.potato, purchases, notes);
    expect(b['small10']!.bought, 7500);
    expect(b['small10']!.used, 3 * 110 + 40);
    expect(b['small10']!.losses, 38); // 0.5% of 7 500 = 37.5
    expect(b['small10']!.available, 7500 - 38 - 370);
    expect(b['largemed10']!.used, 25);
    expect(b['largemed10']!.available, -25); // used, none bought: shows short
    expect(b['med7']!.used, 3 * 140);
    expect(b['med7']!.available, 17000 - 85 - 420);
    expect(b.keys, kPotatoBags.map((k) => k.key));
  });

  test('Pepper boxes and butternut bags from the delivery notes', () {
    final p = bagBalances(ProduceType.pepper, purchases, notes);
    // Pepper boxes: 0.25% losses (1 000 x 0.25% = 2.5, rounded to 3).
    expect(bagLossesText(ProduceType.pepper), '0.25%');
    expect(bagLossesText(ProduceType.potato), '0.5%');
    expect(bagLossesText(ProduceType.butternut), '1%');
    expect(p['5kgRed']!.losses, 3);
    expect(p['5kgRed']!.available, 1000 - 3 - 120);
    expect(p['4kgGreen']!.used, 8);
    final b = bagBalances(ProduceType.butternut, purchases, notes);
    expect(b['10kg']!.used, 300);
    expect(b['7kg']!.used, 0);
  });

  test('Packed but not sent comes off too (potatoes), after the floor count like the rest', () {
    final unsent = [
      UnsentPallets(date: '2026-03-08', field: 'Field 1', pallets: {'small10': 1, 'baby10': 1}, bags: {'small10': 20, 'large10g2': 30}),
      UnsentPallets(date: '2024-11-01', field: 'Field 2', pallets: {'small10': 5}), // before the start
    ];
    final b = bagBalances(ProduceType.potato, purchases, notes, unsent: unsent);
    expect(b['small10']!.used, 370);
    expect(b['small10']!.packed, 240);
    expect(b['small10']!.available, 7500 - 38 - 370 - 240);
    expect(b['brown10']!.packed, 30);
    // Peppers: nothing packed-not-sent is kept for them.
    expect(bagBalances(ProduceType.pepper, purchases, notes, unsent: unsent)['5kgRed']!.packed, 0);
  });

  test('Every 2nd and 3rd grade goes in the one brown bag', () {
    final b = bagBalances(ProduceType.potato, [_bought('brown10', 5000)], [
      _note('2026-03-07', pallets: {'med10g2': 1, 'largemed10g2': 2, 'large10g2': 1}, mixed: [
        {'large10g2': 30},
      ]),
    ])['brown10']!;
    expect(b.used, 4 * 110 + 30);
    expect(b.available, 5000 - 25 - 470);
    expect(kPotatoBags.map((k) => k.key), ['large10', 'largemed10', 'med7', 'smallmed7', 'small10', 'brown10']);
  });

  test('Adjustments: plus or minus, no losses on them', () {
    final b = bagBalances(ProduceType.potato, [
      ...purchases,
      _bought('small10', 2000, date: '2026-02-01', kind: BagEntryKind.adjust, why: 'Opening stock'),
      _bought('small10', -100, date: '2026-04-01', kind: BagEntryKind.adjust, why: 'Rats'),
    ], notes);
    expect(b['small10']!.adjusted, 1900);
    expect(b['small10']!.losses, 38); // not on adjustments
    expect(b['small10']!.available, 7500 - 38 + 1900 - 370);
  });

  test('A floor count: the number starts from it, after its day', () {
    final more = [
      ...purchases,
      _bought('small10', 2000, date: '2026-02-01', kind: BagEntryKind.adjust, why: 'Opening stock'),
      // Counted 6 000 on 2 Mar (after that day's truck), then 3 000 more bought.
      _bought('small10', 5000, date: '2026-03-02', kind: BagEntryKind.count, at: '2026-03-02T10:00'),
      _bought('small10', 6000, date: '2026-03-02', kind: BagEntryKind.count, at: '2026-03-02T17:00'), // later the same day: this one
      _bought('small10', 3000, date: '2026-03-05'),
    ];
    final withTruck = [...notes, _note('2026-03-06', pallets: {'small10': 2})];
    final b = bagBalances(ProduceType.potato, more, withTruck)['small10']!;
    expect(b.counted, 6000);
    expect(b.countDate, '2026-03-02');
    // Before the count (the 8 000 bought, the opening stock, the 2 Mar truck) no longer count;
    // the -500 returned on 10 Mar does.
    expect(b.bought, 3000 - 500);
    expect(b.losses, 43); // 0.5% of the count and purchases: 8 500 x 0.5% = 42.5
    expect(b.adjusted, 0);
    expect(b.used, 220);
    expect(b.available, 6000 + 2500 - 43 - 220);
    // Other bags aren't touched by the Small bag's count.
    expect(bagBalances(ProduceType.potato, more, withTruck)['med7']!.counted, isNull);
    // A count of 0 is a count.
    final zero = bagBalances(ProduceType.potato, [_bought('med7', 0, date: '2026-03-04', kind: BagEntryKind.count)], notes)['med7']!;
    expect((zero.counted, zero.used, zero.available), (0, 0, 0));
  });

  testWidgets('A counted bag: Stock take with its date, then purchases and used after it', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final counted = [
      _bought('brown10', 7500, date: '2026-08-18', kind: BagEntryKind.count),
      _bought('brown10', 4000, date: '2026-09-10', key: 'crownbag:PSI33313:brown10:4000'),
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DeliveryBagsScreen(repo: _FakeRepo(counted, const [])))));
    await tester.pumpAndSettle();
    expect(find.text('11 442'), findsWidgets); // 7 500 + 4 000 - 58 (0.5% of 11 500); the brown bag, and the total
    await tester.tap(find.text('10kg 2nd/3rd grade (brown bag)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stock take 18'), findsOneWidget);
    expect(find.text('7 500'), findsOneWidget);
    expect(find.text('4 000'), findsOneWidget);
    expect(find.text('-58'), findsOneWidget);
    expect(find.text('Adjustments'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Adjust needs a reason; Floor count takes no minus', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DeliveryBagsScreen(repo: _FakeRepo(purchases, notes, [UnsentPallets(date: '2026-03-08', field: 'Field 1', bags: {'small10': 20})])))));
    await tester.pumpAndSettle();
    // Packed but not sent: in the bags used, taken off (7 500 - 38 - 370 - 20).
    expect(find.text('7 072'), findsOneWidget);
    await tester.tap(find.text('10kg 1st Small (Baby and Small)'));
    await tester.pumpAndSettle();
    expect(find.text('-390'), findsOneWidget);
    await tester.tap(find.text('Adjust'));
    await tester.pumpAndSettle();
    expect(find.text('Adjust bags'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('bags_qty')), '-200');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Say why (e.g. opening stock, losses)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Floor count'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bags_qty')), '-50');
    expect(find.text('50'), findsOneWidget); // the minus isn't taken
    expect(find.text('Save count'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bags/Boxes tab: on the floor per bag, then the boxes for peppers', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DeliveryBagsScreen(repo: _FakeRepo(purchases, notes)))));
    await tester.pumpAndSettle();
    expect(find.text('Potatoes (Bags)'), findsOneWidget);
    expect(find.text('10kg 1st Small (Baby and Small)'), findsOneWidget);
    expect(find.text('7 092'), findsOneWidget); // 7 500 - 38 - 370
    // Only the name and the number until tapped; then each part on its own line.
    expect(find.text('Add purchases'), findsNothing);
    await tester.tap(find.text('10kg 1st Small (Baby and Small)'));
    await tester.pumpAndSettle();
    expect(find.text('Stock take'), findsNothing); // not counted
    for (final (label, n) in [('Add purchases', '7 500'), ('Less losses (0.5%)', '-38'), ('Less used', '-370'), ('On the floor', '7 092')]) {
      expect(find.ancestor(of: find.text(label), matching: find.byType(Row)).evaluate().any((r) => find.descendant(of: find.byWidget(r.widget), matching: find.text(n)).evaluate().isNotEmpty),
          isTrue, reason: '$label $n');
    }
    // Only the bags and the buttons: no explanation on top, no list of what came in below.
    expect(find.text('On the floor to pack'), findsNothing);
    expect(find.textContaining('Crown Bag'), findsNothing);
    expect(find.text('Received, adjusted and counted'), findsNothing);
    await tester.scrollUntilVisible(find.text('Peppers (Boxes)'), -300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Peppers (Boxes)'));
    await tester.pumpAndSettle();
    expect(find.text('5kg Red'), findsOneWidget);
    expect(find.text('877'), findsWidgets); // 1 000 - 3 - 120
    expect(find.text('Add boxes received'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
