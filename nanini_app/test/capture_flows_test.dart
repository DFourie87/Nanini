import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/capture_app.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

RefData _ref({Map<String, double> clocked = const {}, Map<String, String> clockedFarms = const {}, List<RefPerson> members = const [], List<RefShopItem> moreShopItems = const []}) => RefData(
      clocked: clocked,
      members: members,
      clockedFarms: clockedFarms,
      farms: const [RefItem('f1', 'Farm Limpopodraai - Stockpoort'), RefItem('f2', 'Farm Haaskraal - Swartwater')],
      people: const [
        RefPerson(id: 'p1', name: 'Anna Mokoena', farmId: 'f1', groupId: 'g1'),
        RefPerson(
            id: 'p2', name: 'Ben Sithole', farmId: 'f1', groupId: 'g1', hasId: true, idOrPassport: '8505055009081', fullNames: 'Benjamin', surname: 'Sithole'),
        RefPerson(id: 'p3', name: 'Carl Nkosi', farmId: 'f2'),
      ],
      groups: const [
        RefItem('g1', 'Pack house', farmId: 'f1'),
        RefItem('g2', 'Orchard', farmId: 'f1'),
        // Haaskraal has no work groups: a leftover one is never shown.
        RefItem('g3', 'Old group', farmId: 'f2'),
      ],
      tanks: const [RefItem('t1', 'Main tank'), RefItem('t2', 'Haaskraal tank')],
      vehicles: const [RefItem('v1', 'JD 6110', unit: 'hours'), RefItem('v2', 'FAW truck', unit: 'km', lastReading: '88000')],
      activities: const [
        RefItem('a1', 'Spraying and Fertilizing'),
        RefItem('a2', 'Ploughing, planting, cultivating, harvesting, baling'),
        RefItem('a3', 'Night watch'),
        RefItem('a4', 'Irrigation pumps and generators'),
        RefItem('a5', 'Road and fence maintenance'),
        RefItem('a6', 'On-farm transport of products and inputs'),
      ],
      shopItems: [
        const RefShopItem(id: 'i1', name: 'Bread', farmId: 'f1', price: 20, stock: 10),
        const RefShopItem(id: 'i2', name: 'Cooldrink', farmId: 'f1', price: 15, stock: 2),
        const RefShopItem(id: 'i3', name: 'Soap', farmId: 'f1', price: 12, stock: 0),
        const RefShopItem(id: 'i4', name: 'Mealie meal', farmId: 'f2', price: 90, stock: 3),
        ...moreShopItems,
      ],
    );

Future<CaptureStore> _pump(WidgetTester tester, Widget flow, {RefData? ref}) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final store = CaptureStore.forTest(ref ?? _ref());
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

/// Group hours: the hours box at the top of the "Who worked?" list.
Future<void> _hours(WidgetTester tester, String digits) async {
  await _tap(tester, 'TAP TO ENTER THE HOURS');
  await _type(tester, digits);
  await _tap(tester, 'OK');
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await _tap(tester, d == '.' ? ',' : d);
  }
}

void main() {
  testWidgets('Diesel out: every step, then saved', (tester) async {
    final store = await _pump(tester, const DieselFlow());
    // DIESEL - OUT is the first choice, above DIESEL - IN.
    expect(tester.getTopLeft(find.text('DIESEL - OUT', findRichText: true)).dy,
        lessThan(tester.getTopLeft(find.text('DIESEL - IN', findRichText: true)).dy));
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
    // Litres and the tank on lines of their own.
    expect(find.text('45,5 L'), findsOneWidget);
    expect(find.text('Main tank'), findsOneWidget);
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

  testWidgets('Diesel: the meter starts from the last reading and needs a new one', (tester) async {
    final store = await _pump(tester, const DieselFlow());
    await _tap(tester, 'DIESEL - OUT');
    await _tap(tester, 'Main tank');
    await _tap(tester, 'FAW truck');
    await _tap(tester, 'Anna Mokoena');
    await _tap(tester, 'Land work');
    expect(find.text('Kilometre reading (km)?'), findsOneWidget);
    expect(find.text('88000 km'), findsOneWidget);
    expect(find.text('This is the last reading. Type the new one.'), findsOneWidget);
    // Not changed: NEXT is refused.
    await _tap(tester, 'NEXT');
    expect(find.text('Type the new reading, or tap NO METER'), findsOneWidget);
    expect(find.text('Kilometre reading (km)?'), findsOneWidget);
    // The first key starts a new number.
    await _type(tester, '88250');
    expect(find.text('88250 km'), findsOneWidget);
    expect(find.text('Last reading: 88000 km'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('How many litres?'), findsOneWidget);
    await _type(tester, '60');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect(store.queue.single.payload['reading'], '88250');
  });

  testWidgets('Diesel: NO METER goes on without a reading', (tester) async {
    final store = await _pump(tester, const DieselFlow());
    await _tap(tester, 'DIESEL - OUT');
    await _tap(tester, 'Main tank');
    await _tap(tester, 'FAW truck');
    await _tap(tester, 'Anna Mokoena');
    await _tap(tester, 'Land work');
    await _tap(tester, "NO METER / CAN'T READ IT");
    expect(find.text('How many litres?'), findsOneWidget);
    await _type(tester, '60');
    await _tap(tester, 'NEXT');
    expect(find.text('No meter reading'), findsOneWidget);
    await _tap(tester, 'SAVE');
    expect(store.queue.single.payload['reading'], '');
  });

  testWidgets('Diesel: litres are required', (tester) async {
    await _pump(tester, const DieselFlow());
    await _tap(tester, 'DIESEL - IN');
    await _tap(tester, 'Main tank');
    await _tap(tester, 'NEXT');
    expect(find.text('Type the litres'), findsOneWidget);
    expect(find.text('How many litres were delivered?'), findsOneWidget);
  });

  testWidgets('Group hours: farm first, work, hours, one person absent', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    expect(find.text('Which farm did you work on?'), findsOneWidget);
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'CAPTURE HOURS');
    expect(find.text('What work did you do?'), findsOneWidget);
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _hours(tester, '8');
    expect(find.text('8h00min each'), findsOneWidget);
    await _tap(tester, 'Ben Sithole'); // untick
    await _tap(tester, 'ABSENT');
    expect(find.text('ABSENT'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    final p = store.queue.single.payload;
    expect(p['mode'], 'group');
    expect((p['entries'] as List).single['employee_id'], 'p1');
  });

  testWidgets('Group hours: NONE unticks everyone, then tap who worked; ALL ticks them again', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'CAPTURE HOURS');
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _hours(tester, '8');
    await _tap(tester, 'ALL');
    await _tap(tester, 'NONE');
    expect(find.text('ABSENT'), findsNWidgets(2));
    await _tap(tester, 'Ben Sithole'); // ticked again
    expect(find.text('ABSENT'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect((store.queue.single.payload['entries'] as List).map((e) => (e as Map)['employee_id']), ['p2']);
  });

  testWidgets('Group hours: typed as XhXXmin', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'CAPTURE HOURS');
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _tap(tester, 'TAP TO ENTER THE HOURS');
    await _type(tester, '8');
    expect(find.text('8h00min'), findsOneWidget);
    await _tap(tester, 'min');
    expect(find.text('8h__min'), findsOneWidget);
    await _type(tester, '3');
    expect(find.text('8h3_min'), findsOneWidget);
    await _type(tester, '0');
    expect(find.text('8h30min'), findsOneWidget);
    await _tap(tester, 'OK');
    expect(find.text('8h30min each'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('Anna Mokoena: 8h30min'), findsOneWidget);
    await _tap(tester, 'SAVE');
    expect((store.queue.single.payload['entries'] as List).map((e) => (e as Map)['hours']), [8.5, 8.5]);
  });

  testWidgets('Hours pad: 15 / 30 / 45 min buttons set the minutes in one tap', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'CAPTURE HOURS');
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _tap(tester, 'TAP TO ENTER THE HOURS');
    await _type(tester, '9');
    await _tap(tester, '30 min');
    expect(find.text('9h30min'), findsOneWidget);
    await _tap(tester, '45 min');
    expect(find.text('9h45min'), findsOneWidget);
    await _tap(tester, '00 min');
    expect(find.text('9h00min'), findsOneWidget);
    await _tap(tester, '15 min');
    await _tap(tester, 'OK');
    expect(find.text('9h15min each'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect((store.queue.single.payload['entries'] as List).map((e) => (e as Map)['hours']), [9.25, 9.25]);
  });

  test('Hours as XhXXmin', () {
    expect(fmtHm(8), '8h00min');
    expect(fmtHm(8.5), '8h30min');
    expect(fmtHm(7.75), '7h45min');
    expect(fmtHm(1 / 3), '0h20min');
    expect(hmValue('8h30'), 8.5);
    expect(hmValue('8h'), 8.0);
    expect(hmValue('9'), 9.0);
    expect(hmValue(''), isNull);
    expect(hmString(8.5), '8h30');
    expect(hmString(8), '8');
    expect(hmTyped(''), '0h00min');
    expect(hmTyped('8h'), '8h__min');
    expect(hmTyped('8h3'), '8h3_min');
  });

  testWidgets('Hours: saved on the farm worked; workers from other farms can be added', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'CAPTURE HOURS');
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _hours(tester, '8');
    // Carl is on Haaskraal's books but worked here today.
    await _tap(tester, 'ADD SOMEONE ELSE');
    await _tap(tester, 'Carl Nkosi');
    expect(find.text('Carl Nkosi'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    final p = store.queue.single.payload;
    expect(p['farm_id'], 'f1');
    expect((p['entries'] as List).map((e) => (e as Map)['employee_id']), containsAll(['p1', 'p2', 'p3']));
  });

  testWidgets('FIX HOURS: the right hours replace what is captured that day', (tester) async {
    final today = dayStr(DateTime.now());
    final store = await _pump(tester, const HoursFlow(),
        ref: _ref(clocked: {'p1|$today': 8}, clockedFarms: {'p1|$today': 'Farm Limpopodraai - Stockpoort'}));
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'FIX HOURS');
    await _tap(tester, 'TODAY');
    expect(find.text('Whose hours?'), findsOneWidget);
    await _tap(tester, 'Anna Mokoena');
    expect(find.text('Anna Mokoena: right hours for today?'), findsOneWidget);
    expect(find.text('Captured now: 8h00min. Type the right hours (0 = none).'), findsOneWidget);
    await _type(tester, '6');
    await _tap(tester, 'NEXT');
    expect(find.text('6h00min (was 8h00min)'), findsOneWidget);
    await _tap(tester, 'SAVE');
    final p = store.queue.single.payload;
    expect(p['fix'], isTrue);
    expect((p['entries'] as List).single['hours'], 6.0);
    expect(p['replace'], ['p1']); // her 8 h become 6 h
  });

  testWidgets('FIX HOURS: 0 takes the hours off', (tester) async {
    final today = dayStr(DateTime.now());
    final store = await _pump(tester, const HoursFlow(), ref: _ref(clocked: {'p1|$today': 8}));
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'FIX HOURS');
    await _tap(tester, 'TODAY');
    await _tap(tester, 'Anna Mokoena');
    await _type(tester, '0');
    await _tap(tester, 'NEXT');
    expect(find.text('No hours (taken off)'), findsOneWidget);
    await _tap(tester, 'SAVE');
    final p = store.queue.single.payload;
    expect(p['entries'], isEmpty);
    expect(p['replace'], ['p1']);
  });

  testWidgets('FIX HOURS: 0 needs hours there that day', (tester) async {
    await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    await _tap(tester, 'FIX HOURS');
    await _tap(tester, 'TODAY');
    await _tap(tester, 'Carl Nkosi');
    expect(find.text('Nothing captured for that day yet'), findsOneWidget);
    await _type(tester, '0');
    await _tap(tester, 'NEXT');
    expect(find.text('Nothing captured that day -- nothing to take off'), findsOneWidget);
  });

  testWidgets('FIX HOURS: captured at another farm -- the fix puts them at this farm', (tester) async {
    final today = dayStr(DateTime.now());
    final store = await _pump(tester, const HoursFlow(),
        ref: _ref(clocked: {'p1|$today': 8}, clockedFarms: {'p1|$today': 'Farm Haaskraal - Swartwater'}));
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'FIX HOURS');
    await _tap(tester, 'TODAY');
    await _tap(tester, 'Anna Mokoena');
    expect(find.text('Captured now: 8h00min at Haaskraal. These go in at Farm Limpopodraai - Stockpoort instead (0 = none).'), findsOneWidget);
    await _type(tester, '8');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    final p = store.queue.single.payload;
    expect(p['farm_id'], 'f1');
    expect(p['replace'], ['p1']);
  });

  testWidgets('FIX HOURS: hours typed on this phone and not sent yet count too', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await store.add(CaptureModule.hours, {
      'mode': 'individual',
      'date': dayStr(DateTime.now()),
      'farm_id': 'f2',
      'entries': [
        {'employee_id': 'p3', 'employee_name': 'Carl Nkosi', 'hours': 7},
      ],
    }, 'Hours');
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    await _tap(tester, 'FIX HOURS');
    await _tap(tester, 'TODAY');
    await _tap(tester, 'Carl Nkosi');
    expect(find.textContaining('Captured now: 7h00min'), findsOneWidget);
  });

  testWidgets('Group hours: someone clocked at another farm is left out', (tester) async {
    final today = dayStr(DateTime.now());
    final store = await _pump(tester, const HoursFlow(),
        ref: _ref(clocked: {'p2|$today': 9}, clockedFarms: {'p2|$today': 'Farm Haaskraal - Swartwater'}));
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'CAPTURE HOURS');
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _hours(tester, '8');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect(find.text('Clocked at another farm'), findsOneWidget);
    expect(find.textContaining('Ben Sithole: 9h00min (clocked by Haaskraal)'), findsOneWidget);
    await _tap(tester, 'LEAVE THEM OUT');
    final p = store.queue.single.payload;
    expect((p['entries'] as List).map((e) => (e as Map)['employee_id']), ['p1']);
    expect(p.containsKey('replace'), isFalse);
  });

  testWidgets('Group hours: someone already sent for that day can be left out', (tester) async {
    final today = dayStr(DateTime.now());
    final store = await _pump(tester, const HoursFlow(), ref: _ref(clocked: {'p2|$today': 9}));
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'CAPTURE HOURS');
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _hours(tester, '8');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect(find.textContaining('Ben Sithole: 9h00min'), findsOneWidget);
    await _tap(tester, 'LEAVE THEIRS');
    final p = store.queue.single.payload;
    expect((p['entries'] as List).map((e) => (e as Map)['employee_id']), ['p1']);
    expect(p.containsKey('replace'), isFalse);
  });

  testWidgets('FIX HOURS: anyone, on the farm worked', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    await _tap(tester, 'FIX HOURS');
    await _tap(tester, 'TODAY');
    // Haaskraal's workers first; Limpopodraai's under FROM OTHER FARM.
    expect(find.text('Anna Mokoena'), findsNothing);
    await _tap(tester, 'FROM OTHER FARM');
    await _tap(tester, 'Anna Mokoena'); // Limpopodraai worker
    await _type(tester, '6');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect(store.queue.single.payload['farm_id'], 'f2');
    expect((store.queue.single.payload['entries'] as List).single['employee_id'], 'p1');
  });

  testWidgets('Group hours: someone worked on another farm -- that farm is told to clock them', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'CAPTURE HOURS');
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _hours(tester, '8');
    await _tap(tester, 'Ben Sithole');
    await _tap(tester, 'WORKED ON OTHER FARM');
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    expect(find.text('AT FARM HAASKRAAL - SWARTWATER'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('Ben Sithole: at Farm Haaskraal - Swartwater -- clock there'), findsOneWidget);
    await _tap(tester, 'SAVE');
    final p = store.queue.single.payload;
    expect((p['entries'] as List).map((e) => (e as Map)['employee_id']), ['p1']);
    expect((p['moved'] as List).single['farm_id'], 'f2');

    // Haaskraal's clocking (same phone here) shows Ben as sent there.
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(key: ValueKey(2), home: HoursFlow())));
    await tester.pumpAndSettle();
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    await _tap(tester, 'FIX HOURS');
    await _tap(tester, 'TODAY');
    expect(find.text('Sent here from Farm Limpopodraai - Stockpoort -- clock here'), findsOneWidget);
    await _tap(tester, 'Ben Sithole');
    expect(find.text('Ben Sithole: right hours for today?'), findsOneWidget);
  });

  testWidgets('Group hours: everyone their own hours -- no hours at the top needed', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'CAPTURE HOURS');
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    // Not yet: someone still has the group's hours.
    await _tap(tester, 'NEXT');
    expect(find.text('Enter the hours at the top, or tap each name for their own hours'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    for (final (name, hours) in [('Anna Mokoena', '7'), ('Ben Sithole', '5')]) {
      await _tap(tester, name);
      await _tap(tester, 'OTHER HOURS');
      await _type(tester, hours);
      await _tap(tester, 'OK');
    }
    expect(find.text('Everyone has their own hours'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('Anna Mokoena: 7h00min'), findsOneWidget);
    await _tap(tester, 'SAVE');
    final entries = (store.queue.single.payload['entries'] as List).cast<Map>();
    expect({for (final e in entries) e['employee_id']: e['hours']}, {'p1': 7.0, 'p2': 5.0});
  });

  testWidgets('Group hours: someone worked other hours', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'CAPTURE HOURS');
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _hours(tester, '8');
    await _tap(tester, 'Ben Sithole');
    await _tap(tester, 'OTHER HOURS');
    expect(find.text('How many hours did Ben Sithole work?'), findsOneWidget);
    await _type(tester, '5');
    await _tap(tester, 'OK');
    expect(find.text('5h00min'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('Ben Sithole: 5h00min'), findsOneWidget);
    await _tap(tester, 'SAVE');
    final entries = (store.queue.single.payload['entries'] as List).cast<Map>();
    expect({for (final e in entries) e['employee_id']: e['hours']}, {'p1': 8.0, 'p2': 5.0});
  });

  testWidgets('Hours: CAPTURE HOURS / FIX HOURS, ADD TIMESHEET at the bottom, no kg', (tester) async {
    await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    expect(find.text('Hours:'), findsOneWidget);
    expect(find.text('CAPTURE HOURS'), findsOneWidget);
    expect(find.text('A work group (packhouse, field, ...)'), findsOneWidget);
    expect(find.text('FIX HOURS'), findsOneWidget);
    expect(find.text('Group'), findsNothing);
    expect(find.text('Person'), findsNothing);
    // The chosen farm's timesheet, below the two.
    expect(find.text('ADD TIMESHEET'), findsOneWidget);
    expect(find.text("Photo of Farm Limpopodraai - Stockpoort's timesheet"), findsOneWidget);
    expect(tester.getTopLeft(find.text('FIX HOURS')).dy, lessThan(tester.getTopLeft(find.text('ADD TIMESHEET')).dy));
    expect(find.text('KG PICKED'), findsNothing);
  });

  testWidgets('Diesel: the tank farm people first, others under FROM OTHER FARM', (tester) async {
    await _pump(tester, const DieselFlow());
    await _tap(tester, 'DIESEL - OUT');
    await _tap(tester, 'Haaskraal tank');
    await _tap(tester, 'JD 6110');
    expect(find.text('Who filled the diesel?'), findsOneWidget);
    expect(find.text('Carl Nkosi'), findsOneWidget);
    expect(find.text('Anna Mokoena'), findsNothing);
    await _tap(tester, 'FROM OTHER FARM');
    expect(find.text('Anna Mokoena'), findsOneWidget);
  });

  testWidgets('Diesel: the members are on every farm\'s list (names only, not in hours)', (tester) async {
    final ref = _ref(members: const [RefPerson(id: 'm1', name: 'Dereck', surname: 'Fourie', farmId: 'f1')]);
    final store = await _pump(tester, const DieselFlow(), ref: ref);
    await _tap(tester, 'DIESEL - OUT');
    await _tap(tester, 'Haaskraal tank');
    await _tap(tester, 'JD 6110');
    // On Haaskraal's list straight away, though Dereck's farm is Limpopodraai.
    expect(find.text('Carl Nkosi'), findsOneWidget);
    expect(find.text('Dereck Fourie'), findsOneWidget);
    await _tap(tester, 'Dereck Fourie');
    expect(find.text('Who filled the diesel?'), findsNothing);
    expect(store.queue, isEmpty);
    // Never among the people for hours, pay or the tuck shop.
    expect(ref.people.map((p) => p.id), isNot(contains('m1')));
    expect(RefData.fromJson(ref.toJson()).members.single.name, 'Dereck Fourie');
  });

  testWidgets('Work groups: make a group, put people in it, clock it straight away', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    // Not on the first screen: WORK GROUPS is on the group step of a farm
    // that has groups.
    expect(find.text('WORK GROUPS'), findsNothing);
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'CAPTURE HOURS');
    await _tap(tester, 'WORK GROUPS');
    expect(find.text('Work groups at Farm Limpopodraai - Stockpoort'), findsOneWidget);
    await _tap(tester, 'NEW GROUP');
    await tester.enterText(find.byType(TextField), 'Picking');
    await _tap(tester, 'OK');
    expect(find.text('Who is in Picking?'), findsOneWidget);
    await _tap(tester, 'Ben Sithole');
    await _tap(tester, 'SAVE');
    final e = store.queue.single;
    expect(e.module, CaptureModule.workGroups);
    expect(e.payload['group_id'], isNull);
    expect(e.payload['group_name'], 'Picking');
    expect((e.payload['members'] as List).single['employee_id'], 'p2');
    expect(find.text('1 people · new'), findsOneWidget);
    await _tap(tester, 'DONE');
    // Hours uses the new group before the office has approved it.
    await _tap(tester, 'Picking');
    await _tap(tester, 'TODAY');
    await _hours(tester, '6');
    expect(find.text('Ben Sithole'), findsOneWidget);
    expect(find.text('Anna Mokoena'), findsNothing);
  });

  testWidgets('A group made on the phone goes once the office has dealt with it', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await store.rememberGroups(newGroup: const RefItem('new-x', 'Picking', farmId: 'f1'), set: const {});
    // Not waiting on the office (never sent, or approved/rejected): not shown.
    await tester.pumpAndSettle();
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'CAPTURE HOURS');
    expect(find.text('Pack house'), findsOneWidget);
    expect(find.text('Picking'), findsNothing);
  });

  testWidgets('Haaskraal: no groups, Group clocks everyone at the farm', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    await _tap(tester, 'CAPTURE HOURS');
    expect(find.text('Old group'), findsNothing);
    expect(find.text('WORK GROUPS'), findsNothing); // no groups to make here
    expect(find.text('Which day?'), findsOneWidget);
    await _tap(tester, 'TODAY');
    await _hours(tester, '7');
    expect(find.text('Carl Nkosi'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect(store.queue.single.payload['group_id'], isNull);
    expect((store.queue.single.payload['entries'] as List).single['employee_id'], 'p3');
  });

  testWidgets('Group with nobody in it yet: add everyone from the farm', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'CAPTURE HOURS');
    await _tap(tester, 'Orchard');
    await _tap(tester, 'TODAY');
    await _hours(tester, '5');
    expect(find.text('Nobody is in Orchard yet. Add the people who worked:'), findsOneWidget);
    expect(find.textContaining('Connect the phone'), findsNothing);
    await _tap(tester, 'EVERYONE FROM FARM LIMPOPODRAAI - STOCKPOORT');
    expect(find.text('Anna Mokoena'), findsOneWidget);
    expect(find.text('Ben Sithole'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect((store.queue.single.payload['entries'] as List).map((e) => (e as Map)['employee_id']), unorderedEquals(['p1', 'p2']));
  });

  testWidgets('Tuck shop: workers from any farm can buy at any shop', (tester) async {
    final store = await _pump(tester, const TuckshopFlow());
    // The fridge sheet photo is at the bottom of the shops, below the last one.
    expect(find.text('Which shop?'), findsOneWidget);
    expect(tester.getTopLeft(find.text('FRIDGE SHEET')).dy, greaterThan(tester.getTopLeft(find.text('Farm Haaskraal - Swartwater')).dy));
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    // The shop's own farm first; Limpopodraai workers under FROM OTHER FARM.
    expect(find.text('Carl Nkosi'), findsOneWidget);
    expect(find.text('Anna Mokoena'), findsNothing);
    await _tap(tester, 'FROM OTHER FARM');
    expect(find.text('Anna Mokoena'), findsOneWidget);
    await _tap(tester, 'Anna Mokoena');
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect(store.queue.single.payload['employee_id'], 'p1');
    expect(store.queue.single.payload['farm_id'], 'f2');
  });

  testWidgets('Fridge count: under FRIDGE SHEET, each fridge item counted, then saved', (tester) async {
    final store = await _pump(tester, const TuckshopFlow(),
        ref: _ref(moreShopItems: const [
          RefShopItem(id: 'i5', name: 'Wors', farmId: 'f1', price: 35, stock: 20),
          RefShopItem(id: 'i6', name: 'Chicken pieces', farmId: 'f1', price: 25, stock: 10),
        ]));
    expect(tester.getTopLeft(find.text('FRIDGE COUNT')).dy, greaterThan(tester.getTopLeft(find.text('FRIDGE SHEET')).dy));
    await _tap(tester, 'FRIDGE COUNT');
    // One shop with a fridge: straight to counting, item by item.
    expect(find.text('How many Chicken pieces are in the fridge now?'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('Type how many (0 for none)'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.text('NEXT'))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('0').last); // the key, not the empty display's 0
    await tester.pumpAndSettle();
    await _tap(tester, 'NEXT');
    expect(find.text('How many Wors are in the fridge now?'), findsOneWidget);
    await _type(tester, '12');
    await _tap(tester, 'NEXT');
    expect(find.text('Wors: 12'), findsOneWidget);
    expect(find.text('Chicken pieces: 0'), findsOneWidget);
    expect(find.textContaining('Bread'), findsNothing);
    await _tap(tester, 'SAVE');
    final e = store.queue.single;
    expect(e.module, CaptureModule.fridgeSheet);
    expect(e.payload['kind'], 'count');
    expect(e.payload['farm_id'], 'f1');
    expect({for (final c in (e.payload['counts'] as List).cast<Map>()) c['item_id']: c['qty']}, {'i5': 12, 'i6': 0});
  });

  testWidgets('Tuck shop item sales: Limpopodraai and Haaskraal alike', (tester) async {
    final store = await _pump(tester, const TuckshopFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Anna Mokoena');
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    await _tap(tester, 'NEXT');
    expect(find.text('Total R40'), findsOneWidget);
    await _tap(tester, 'SAVE');
    expect((store.queue.single.payload['lines'] as List).single['qty'], 2);

    await _tap(tester, 'ANOTHER SALE');
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    await _tap(tester, 'Carl Nkosi');
    // Only Haaskraal's own stock, per item like Limpopodraai.
    expect(find.text('Mealie meal'), findsOneWidget);
    expect(find.text('Bread'), findsNothing);
    expect(find.text('In stock: 3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    await _tap(tester, 'NEXT');
    expect(find.text('1 × Mealie meal'), findsOneWidget);
    expect(find.text('Total R90'), findsOneWidget);
    await _tap(tester, 'SAVE');
    final p = store.queue.last.payload;
    expect(p['manual_total'], isNull);
    expect(p['farm_id'], 'f2');
    expect((p['lines'] as List).single, {'item_id': 'i4', 'item_name': 'Mealie meal', 'qty': 1, 'price': 90.0});
  });

  testWidgets('Butternuts: typed per bag size, numbers kept', (tester) async {
    final store = await _pump(tester, const DeliveryFlow());
    await _tap(tester, 'BUTTERNUTS');
    expect(find.text('How many bags?'), findsOneWidget);
    expect(find.text('10 kg  BAGS'), findsOneWidget);
    await _type(tester, '150');
    await _tap(tester, 'NEXT');
    expect(find.text('7 kg  BAGS'), findsOneWidget);
    await _type(tester, '30');
    await _tap(tester, 'BACK');
    expect(find.text('150'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('30'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('180 bags of butternut'), findsOneWidget);
    expect(find.byType(ButternutIcon), findsNWidgets(2)); // one per bag size on the check screen
    await _tap(tester, 'SAVE');
    expect(store.queue.single.payload['butternuts'], {'10kg': 150, '7kg': 30});
    expect(store.queue.single.payload['total'], 180);
  });

  testWidgets('Peppers: one screen per size and colour, typed numbers kept', (tester) async {
    final store = await _pump(tester, const DeliveryFlow());
    await _tap(tester, 'PEPPERS');
    expect(find.text('How many boxes?'), findsOneWidget);
    expect(find.text('5 kg  RED'), findsOneWidget);
    expect(tester.widget<PepperIcon>(find.byType(PepperIcon)).colour, PepperColour.red);
    await _type(tester, '120');
    await _tap(tester, 'NEXT');
    expect(find.text('5 kg  YELLOW'), findsOneWidget);
    expect(tester.widget<PepperIcon>(find.byType(PepperIcon)).colour, PepperColour.yellow);
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
    // One pepper per line, in the line's colour (5kg red, 5kg green, 4kg red).
    expect(tester.widgetList<PepperIcon>(find.byType(PepperIcon)).map((p) => p.colour), [PepperColour.red, PepperColour.green, PepperColour.red]);
    await _tap(tester, 'SAVE');
    final p = store.queue.single.payload;
    expect(p['total'], 168);
    // Dated the day it's sent off.
    expect(p['date'], dayStr(DateTime.now()));
    expect(p['peppers'], {'5kgRed': 120, '5kgYellow': 0, '5kgGreen': 40, '4kgRed': 8, '4kgYellow': 0, '4kgGreen': 0});
  });

  testWidgets('Mixed pallet: bags typed, with the running bag total', (tester) async {
    final store = await _pump(tester, const DeliveryFlow());
    await _tap(tester, 'POTATOES');
    await _tap(tester, 'NEXT');
    await tester.scrollUntilVisible(find.text('MIXED PALLET'), 300, scrollable: find.byType(Scrollable).first);
    await _tap(tester, 'MIXED PALLET');
    expect(find.text('Total: 0 bags'), findsOneWidget);
    // Bags are typed, no +/- counters.
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.byIcon(Icons.add_circle)), findsNothing);
    await tester.enterText(find.byKey(const Key('mixed_baby10')), '40');
    await tester.enterText(find.byKey(const Key('mixed_small10')), '25');
    await tester.pumpAndSettle();
    expect(find.text('Total: 65 bags'), findsOneWidget);
    await _tap(tester, 'ADD');
    await tester.scrollUntilVisible(find.text('Mixed pallet 1'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Mixed pallet 1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('1 of 32 pallets'), -300, scrollable: find.byType(Scrollable).first);
    expect(find.text('1 of 32 pallets'), findsOneWidget);
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
    expect(find.textContaining('R20'), findsNothing);
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
    // The truck being counted is kept on the phone (as in the app).
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = CaptureStore.forTest(_ref(), prefs);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: DeliveryFlow())));
    await tester.pumpAndSettle();
    await _tap(tester, 'POTATOES');
    // Pallets per truck has its own screen, before the counter.
    expect(find.text('How many pallets does this truck take?'), findsOneWidget);
    expect(find.text('32'), findsOneWidget);
    await _tap(tester, '⌫');
    await _tap(tester, '⌫');
    await _type(tester, '2');
    await _tap(tester, 'NEXT');
    expect(find.text('Count the pallets'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    // Out of the app and in again: the same truck, with its 2 pallets.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: DeliveryFlow())));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 pallets'), findsOneWidget);
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
    // Each line and the total with its approximate weight (2 x 110 bags x 10kg + 1%).
    expect(find.text('About 2 222 kg altogether'), findsOneWidget);
    final line = find.ancestor(of: find.text('2 × ${kPalletSizes.first.label}  (≈ 2 222 kg)'), matching: find.byType(CheckLine));
    expect(tester.widget<CheckLine>(line).color, Color(kPalletSizes.first.color));
    await _tap(tester, 'SAVE');
    expect(store.queue.single.payload['total'], 2);
    expect(store.queue.single.payload['target'], 2);
    expect(store.queue.single.payload['pallets']['baby10'], 2);

    // Sent to the hub: the next truck starts again -- 32 pallets (whatever
    // the last one took, no "Usually" hint) and nothing counted.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: DeliveryFlow())));
    await tester.pumpAndSettle();
    await _tap(tester, 'POTATOES');
    expect(find.text('How many pallets does this truck take?'), findsOneWidget);
    expect(find.text('32'), findsOneWidget);
    expect(find.textContaining('Usually'), findsNothing);
    await _tap(tester, 'NEXT');
    expect(find.text('0 of 32 pallets'), findsOneWidget);
  });

  testWidgets('home: logo, Data Capturing, phone name in red, tick/cross, one-line buttons', (tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final store = CaptureStore.forTest(_ref())
      ..deviceId = 'x'
      ..deviceName = 'Phone Piet'
      ..deviceApproved = true;
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: CaptureHomeScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Data Capturing'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Phone Piet')).style?.color, NaniniColors.red);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Everything is sent'), findsNothing);
    expect(find.textContaining('Wi-Fi'), findsNothing);
    for (final label in ['DIESEL', 'PACKAGING', 'HOURS', 'TUCK SHOP']) {
      await tester.scrollUntilVisible(find.text(label), 200, scrollable: find.byType(Scrollable).first);
      expect(tester.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines, isFalse, reason: label);
    }
    // Payslips and employee details are done in the hub (Employees), not on the phone.
    expect(find.text('PAYSLIPS'), findsNothing);
    expect(find.text('EMPLOYEES'), findsNothing);
    store.deviceId = null; // keeps add() from trying to send
    await store.add(CaptureModule.dieselUsage, {}, 'x');
    await tester.pump();
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh)).color, NaniniColors.ink);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Number keys are not cut off on a short phone', (tester) async {
    tester.view.physicalSize = const Size(720, 1300);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    // The hub theme pads outlined buttons; that used to squash the digits.
    final theme = ThemeData(
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14))),
    );
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: CaptureStore.forTest(_ref()),
      child: MaterialApp(theme: theme, home: const DeliveryFlow()),
    ));
    await tester.pumpAndSettle();
    await _tap(tester, 'PEPPERS');
    for (final k in ['1', '5', '8', '0']) {
      final p = tester.renderObject<RenderParagraph>(find.descendant(of: find.byType(OutlinedButton), matching: find.text(k)));
      final full = TextPainter(text: p.text, textDirection: TextDirection.ltr)..layout();
      expect(p.size.height, greaterThanOrEqualTo(full.height - 0.5), reason: 'key $k is clipped');
    }
  });
}
