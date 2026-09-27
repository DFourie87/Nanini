import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/capture_store.dart';
import 'package:nanini_app/capture_app/flows/delivery_flow.dart';
import 'package:nanini_app/capture_app/flows/diesel_flow.dart';
import 'package:nanini_app/capture_app/flows/hours_flow.dart';
import 'package:nanini_app/capture_app/flows/tuckshop_flow.dart';
import 'package:nanini_app/capture_app/ref_data.dart';
import 'package:nanini_app/features/capture/capture_models.dart';
import 'package:provider/provider.dart';

RefData _ref() => RefData(
      farms: const [RefItem('f1', 'Farm Limpopodraai - Stockpoort'), RefItem('f2', 'Farm Haaskraal - Swartwater')],
      people: const [
        RefPerson(id: 'p1', name: 'Anna Mokoena', farmId: 'f1', groupId: 'g1'),
        RefPerson(id: 'p2', name: 'Ben Sithole', farmId: 'f1', groupId: 'g1'),
        RefPerson(id: 'p3', name: 'Carl Nkosi', farmId: 'f2'),
      ],
      groups: const [RefItem('g1', 'Pack house', farmId: 'f1')],
      tanks: const [RefItem('t1', 'Main tank')],
      vehicles: const [RefItem('v1', 'JD 6110', unit: 'hours'), RefItem('v2', 'FAW truck', unit: 'km')],
      activities: const [RefItem('a1', 'Spraying and Fertilizing')],
      shopItems: const [RefShopItem(id: 'i1', name: 'Bread', farmId: 'f1', price: 20, stock: 10)],
    );

Future<CaptureStore> _pump(WidgetTester tester, Widget flow) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final store = CaptureStore.forTest(_ref());
  await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: MaterialApp(home: flow)));
  await tester.pumpAndSettle();
  return store;
}

Future<void> _tap(WidgetTester tester, String text) async {
  final f = find.text(text, findRichText: true);
  await tester.ensureVisible(f.first);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await _tap(tester, d == '.' ? ',' : d);
  }
}

void main() {
  testWidgets('Diesel out: every step, then saved', (tester) async {
    final store = await _pump(tester, const DieselFlow());
    await _tap(tester, 'DIESEL - OUT');
    await _tap(tester, 'Main tank');
    await _tap(tester, 'JD 6110');
    await _type(tester, '45.5');
    await _tap(tester, 'NEXT');
    await _type(tester, '1234');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'Spraying and Fertilizing');
    await _tap(tester, 'SKIP');
    expect(find.text('Is this right?'), findsOneWidget);
    expect(find.text('45,5 L from Main tank'), findsOneWidget);
    await _tap(tester, 'SAVE');
    expect(find.text('SAVED'), findsOneWidget);
    expect(store.queue.single.module, CaptureModule.dieselUsage);
    expect(store.queue.single.payload['litres'], 45.5);
    expect(store.queue.single.payload['vehicle_id'], 'v1');
  });

  testWidgets('Diesel: litres are required', (tester) async {
    await _pump(tester, const DieselFlow());
    await _tap(tester, 'DIESEL - IN');
    await _tap(tester, 'Main tank');
    await _tap(tester, 'NEXT');
    expect(find.text('Type the litres'), findsOneWidget);
    expect(find.text('How many litres were delivered?'), findsOneWidget);
  });

  testWidgets('Group hours with one person absent', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'HOURS FOR A GROUP');
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _type(tester, '8');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'Ben Sithole');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    final p = store.queue.single.payload;
    expect(p['mode'], 'group');
    expect((p['entries'] as List).single['employee_id'], 'p1');
  });

  testWidgets('Kg picked for two people', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'KG PICKED');
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'YESTERDAY');
    await _tap(tester, 'Anna Mokoena');
    await _type(tester, '120');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'ADD ANOTHER PERSON');
    await _tap(tester, 'Ben Sithole');
    await _type(tester, '95');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect(store.queue.single.module, CaptureModule.kg);
    expect((store.queue.single.payload['entries'] as List).length, 2);
  });

  testWidgets('Tuck shop item sale and Haaskraal amount', (tester) async {
    final store = await _pump(tester, const TuckshopFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Anna Mokoena');
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    await _tap(tester, 'NEXT');
    expect(find.text('Total R 40'), findsOneWidget);
    await _tap(tester, 'SAVE');
    expect((store.queue.single.payload['lines'] as List).single['qty'], 2);

    await _tap(tester, 'ANOTHER SALE');
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    await _tap(tester, 'Carl Nkosi');
    await _type(tester, '55');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect(store.queue.last.payload['manual_total'], 55);
  });

  testWidgets('BACK and NEXT fit on a narrow phone', (tester) async {
    // 320dp wide -- smaller than most phones in use.
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: CaptureStore.forTest(_ref()),
      child: const MaterialApp(home: DeliveryFlow()),
    ));
    await tester.pumpAndSettle();
    await _tap(tester, 'POTATOES');
    // Widest label in the app sits next to BACK here.
    for (final label in ['BACK', 'TRUCK FULL']) {
      final p = tester.renderObject<RenderParagraph>(find.text(label));
      // One line, nothing cut: a squeezed label wraps ("BAC" / "K") and the
      // fixed-height button hides the rest.
      expect(p.didExceedMaxLines, isFalse, reason: label);
      expect(p.size.height, lessThan(40), reason: '$label wrapped onto a second line');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Potato truck must reach its pallet target', (tester) async {
    final store = await _pump(tester, const DeliveryFlow());
    await _tap(tester, 'POTATOES');
    await _tap(tester, 'Truck takes a different number? Tap here');
    await _tap(tester, '⌫');
    await _tap(tester, '⌫');
    await _type(tester, '2');
    await _tap(tester, 'OK');
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    await _tap(tester, 'TRUCK FULL');
    expect(find.text('1 of 2 pallets. The truck must have 2.'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    await _tap(tester, 'TRUCK FULL');
    await _tap(tester, 'SAVE');
    expect(store.queue.single.payload['total'], 2);
    expect(store.queue.single.payload['pallets']['baby10'], 2);
  });
}
