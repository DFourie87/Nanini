import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/capture_store.dart';
import 'package:nanini_app/capture_app/capture_widgets.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/theme/nanini_theme.dart';
import 'package:nanini_app/capture_app/flows/delivery_flow.dart';
import 'package:nanini_app/capture_app/flows/diesel_flow.dart';
import 'package:nanini_app/capture_app/flows/hours_flow.dart';
import 'package:nanini_app/capture_app/flows/tuckshop_flow.dart';
import 'package:nanini_app/capture_app/ref_data.dart';
import 'package:nanini_app/capture_app/farm_icons.dart';
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
      activities: const [
        RefItem('a1', 'Spraying and Fertilizing'),
        RefItem('a2', 'Ploughing, planting, cultivating, harvesting, baling'),
        RefItem('a3', 'Night watch'),
        RefItem('a4', 'Irrigation pumps and generators'),
        RefItem('a5', 'Road and fence maintenance'),
        RefItem('a6', 'On-farm transport of products and inputs'),
      ],
      shopItems: const [
        RefShopItem(id: 'i1', name: 'Bread', farmId: 'f1', price: 20, stock: 10),
        RefShopItem(id: 'i2', name: 'Cooldrink', farmId: 'f1', price: 15, stock: 2),
        RefShopItem(id: 'i3', name: 'Soap', farmId: 'f1', price: 12, stock: 0),
      ],
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
    // Order: what happened, tank, machine, who filled, work, reading, litres.
    await _tap(tester, 'DIESEL - OUT');
    await _tap(tester, 'Main tank');
    await _tap(tester, 'JD 6110');
    expect(find.text('Who filled the diesel?'), findsOneWidget);
    expect(find.text('SKIP'), findsNothing);
    await _tap(tester, 'Anna Mokoena');
    // Short wording on the phone; spraying keeps its name (with the sprayer
    // picture); an activity with no short name shows in full.
    expect(find.text('Land work'), findsOneWidget);
    expect(find.text('Night watch'), findsOneWidget);
    expect(find.byType(SprayerIcon), findsOneWidget);
    expect(find.text('Generator'), findsOneWidget);
    expect(find.byType(GeneratorIcon), findsOneWidget);
    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.byType(FenceIcon), findsOneWidget);
    expect(find.text('Transport on farm'), findsOneWidget);
    expect(find.byType(TractorTrailerIcon), findsOneWidget);
    expect(find.textContaining('Ploughing'), findsNothing);
    await _tap(tester, 'Land work');
    expect(find.text('Hour meter reading?'), findsOneWidget);
    await _type(tester, '1234');
    await _tap(tester, 'NEXT');
    expect(find.text('How many litres?'), findsOneWidget);
    await _type(tester, '45.5');
    await _tap(tester, 'NEXT');
    expect(find.text('Is this right?'), findsOneWidget);
    expect(find.text('45,5 L from Main tank'), findsOneWidget);
    expect(find.text('JD 6110'), findsOneWidget);
    expect(find.text('Anna Mokoena'), findsOneWidget);
    expect(find.text('Land work'), findsOneWidget);
    expect(find.textContaining('Into'), findsNothing);
    expect(find.textContaining('Filled by'), findsNothing);
    await _tap(tester, 'SAVE');
    expect(find.text('SAVED'), findsOneWidget);
    expect(store.queue.single.module, CaptureModule.dieselUsage);
    expect(store.queue.single.payload['litres'], 45.5);
    expect(store.queue.single.payload['vehicle_id'], 'v1');
    expect(store.queue.single.payload['employee_id'], 'p1');
    expect(store.queue.single.payload['reading'], '1234');
    // The hub still gets the full activity.
    expect(store.queue.single.payload['activity_id'], 'a2');
    expect(store.queue.single.payload['activity_name'], 'Ploughing, planting, cultivating, harvesting, baling');
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
    expect(find.text('R 0'), findsOneWidget);
    await _type(tester, '55');
    expect(find.text('R 55'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect(store.queue.last.payload['manual_total'], 55);
  });

  testWidgets('Peppers: one screen per size and colour, typed numbers kept', (tester) async {
    final store = await _pump(tester, const DeliveryFlow());
    await _tap(tester, 'PEPPERS');
    expect(find.text('How many boxes?'), findsOneWidget);
    expect(find.text('5 kg  RED'), findsOneWidget);
    await _type(tester, '120');
    await _tap(tester, 'NEXT');
    expect(find.text('5 kg  YELLOW'), findsOneWidget);
    await _tap(tester, 'NEXT'); // none of these
    expect(find.text('5 kg  GREEN'), findsOneWidget);
    await _type(tester, '40');
    // Back twice to red and forward again: the numbers are still there.
    await _tap(tester, 'BACK');
    await _tap(tester, 'BACK');
    expect(find.text('5 kg  RED'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    expect(find.text('40'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('4 kg  RED'), findsOneWidget);
    await _type(tester, '8');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    expect(find.text('4 kg  GREEN'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('Is this right?'), findsOneWidget);
    expect(find.text('168 boxes of pepper'), findsOneWidget);
    await _tap(tester, 'SAVE');
    final p = store.queue.single.payload;
    expect(p['total'], 168);
    expect(p['peppers'], {'5kgRed': 120, '5kgYellow': 0, '5kgGreen': 40, '4kgRed': 8, '4kgYellow': 0, '4kgGreen': 0});
  });

  testWidgets('Mixed pallet shows the running bag total', (tester) async {
    final store = await _pump(tester, const DeliveryFlow());
    await _tap(tester, 'POTATOES');
    await _tap(tester, 'NEXT');
    await tester.scrollUntilVisible(find.text('MIXED PALLET'), 300, scrollable: find.byType(Scrollable).first);
    await _tap(tester, 'MIXED PALLET');
    expect(find.text('Total: 0 bags'), findsOneWidget);
    final plus = find.descendant(of: find.byType(AlertDialog), matching: find.byIcon(Icons.add_circle));
    await tester.tap(plus.at(0));
    await tester.tap(plus.at(0));
    await tester.tap(plus.at(1));
    await tester.pumpAndSettle();
    expect(find.text('Total: 3 bags'), findsOneWidget);
    await _tap(tester, 'ADD');
    await tester.scrollUntilVisible(find.text('Mixed pallet 1'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Mixed pallet 1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('1 of 30 pallets'), -300, scrollable: find.byType(Scrollable).first);
    expect(find.text('1 of 30 pallets'), findsOneWidget);
    expect(store.queue, isEmpty);
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
    await _tap(tester, 'NEXT');
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

  testWidgets('Tuck shop: stock level only, and no selling past it', (tester) async {
    final store = await _pump(tester, const TuckshopFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Anna Mokoena');
    // No unit prices; stock in green, or red when there's none.
    expect(find.textContaining('R 20'), findsNothing);
    expect(find.text('In stock: 10'), findsOneWidget);
    expect(find.text('In stock: 2'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    Color colourOf(String t) => tester.widget<Text>(find.text(t)).style!.color!;
    expect(colourOf('In stock: 2'), NaniniColors.green);
    expect(colourOf('Out of stock'), NaniniColors.red);

    // Cooldrink: only 2 -- a third + is refused.
    final plus = find.byIcon(Icons.add_circle);
    for (var n = 0; n < 3; n++) {
      await tester.tap(plus.at(1));
      await tester.pumpAndSettle();
    }
    expect(find.text('Only 2 Cooldrink in stock'), findsOneWidget);
    // Soap: none at all.
    await tester.tap(plus.at(2));
    await tester.pumpAndSettle();
    expect(find.text('Soap is out of stock'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));
    await _tap(tester, 'NEXT');
    expect(find.text('2 × Cooldrink'), findsOneWidget);
    await _tap(tester, 'SAVE');
    expect((store.queue.single.payload['lines'] as List).single['qty'], 2);

    // The next sale on this phone already counts those 2 as gone.
    await _tap(tester, 'ANOTHER SALE');
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Ben Sithole');
    expect(find.text('Out of stock'), findsNWidgets(2));
    expect(find.text('In stock: 10'), findsOneWidget);
  });

  testWidgets('Potato truck must reach its pallet target', (tester) async {
    final store = await _pump(tester, const DeliveryFlow());
    await _tap(tester, 'POTATOES');
    // Pallets per truck has its own screen, before the counter.
    expect(find.text('How many pallets does this truck take?'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    await _tap(tester, '⌫');
    await _tap(tester, '⌫');
    await _type(tester, '2');
    await _tap(tester, 'NEXT');
    expect(find.text('Count the pallets'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    await _tap(tester, 'TRUCK FULL');
    expect(find.text('1 of 2 pallets. The truck must have 2.'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));

    // Back to the pallets screen and forward again: both are remembered.
    await _tap(tester, 'BACK');
    expect(find.text('How many pallets does this truck take?'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    await _tap(tester, 'NEXT');
    expect(find.text('1 of 2 pallets'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    await _tap(tester, 'TRUCK FULL');
    // Check screen: the bag icon has the size's counter colour, text stays black.
    final line = find.ancestor(of: find.text('2 × ${kPalletSizes.first.label}'), matching: find.byType(CheckLine));
    expect(tester.widget<CheckLine>(line).color, Color(kPalletSizes.first.color));
    await _tap(tester, 'SAVE');
    expect(store.queue.single.payload['total'], 2);
    expect(store.queue.single.payload['target'], 2);
    expect(store.queue.single.payload['pallets']['baby10'], 2);
  });
}
