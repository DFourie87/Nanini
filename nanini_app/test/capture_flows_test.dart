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
import 'package:nanini_app/capture_app/flows/employee_flow.dart';
import 'package:nanini_app/capture_app/flows/hours_flow.dart';
import 'package:nanini_app/capture_app/flows/tuckshop_flow.dart';
import 'package:nanini_app/capture_app/ref_data.dart';
import 'package:nanini_app/capture_app/farm_icons.dart';
import 'package:nanini_app/features/capture/capture_models.dart';
import 'package:provider/provider.dart';

RefData _ref({Map<String, double> clocked = const {}}) => RefData(
      clocked: clocked,
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
      shopItems: const [
        RefShopItem(id: 'i1', name: 'Bread', farmId: 'f1', price: 20, stock: 10),
        RefShopItem(id: 'i2', name: 'Cooldrink', farmId: 'f1', price: 15, stock: 2),
        RefShopItem(id: 'i3', name: 'Soap', farmId: 'f1', price: 12, stock: 0),
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
    await _tap(tester, 'Group');
    expect(find.text('What work did you do?'), findsOneWidget);
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _hours(tester, '8');
    expect(find.text('8 hours each'), findsOneWidget);
    await _tap(tester, 'Ben Sithole'); // untick
    await _tap(tester, 'ABSENT');
    expect(find.text('ABSENT'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    final p = store.queue.single.payload;
    expect(p['mode'], 'group');
    expect((p['entries'] as List).single['employee_id'], 'p1');
  });

  testWidgets('Hours: saved on the farm worked; workers from other farms can be added', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Group');
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

  testWidgets('Hours already sent for that day: asked to change them', (tester) async {
    final today = dayStr(DateTime.now());
    final store = await _pump(tester, const HoursFlow(), ref: _ref(clocked: {'p1|$today': 8}));
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Person');
    await _tap(tester, 'TODAY');
    await _tap(tester, 'Anna Mokoena');
    expect(find.text('Already submitted'), findsOneWidget);
    expect(find.textContaining('Anna Mokoena: 8 h'), findsOneWidget);
    // BACK: not changed, still choosing who worked.
    await _tap(tester, 'BACK');
    expect(find.text('Who worked?'), findsOneWidget);
    await _tap(tester, 'Anna Mokoena');
    await _tap(tester, 'CHANGE');
    await _type(tester, '6');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    final p = store.queue.single.payload;
    expect((p['entries'] as List).single['hours'], 6.0);
    expect(p['replace'], ['p1']); // the office replaces her 8 h with 6 h
  });

  testWidgets('Hours per person can be taken off (negative), not below what is there', (tester) async {
    final today = dayStr(DateTime.now());
    final store = await _pump(tester, const HoursFlow(), ref: _ref(clocked: {'p1|$today': 8}));
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Person');
    await _tap(tester, 'TODAY');
    await _tap(tester, 'Anna Mokoena');
    await _tap(tester, 'CHANGE');
    await _tap(tester, 'TAKE OFF (−)');
    await _type(tester, '9');
    await _tap(tester, 'NEXT');
    expect(find.text('Only 8 h on that day -- you can take off at most that'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.text('NEXT'))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await _tap(tester, '⌫');
    await _type(tester, '8');
    await _tap(tester, 'NEXT');
    expect(find.text('Take off 8 hours'), findsOneWidget);
    await _tap(tester, 'SAVE');
    final p = store.queue.single.payload;
    expect((p['entries'] as List).single['hours'], -8.0);
    expect(p.containsKey('replace'), isFalse); // taken off, not replaced
  });

  testWidgets('Taking off hours needs hours there that day', (tester) async {
    await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    await _tap(tester, 'Person');
    await _tap(tester, 'TODAY');
    await _tap(tester, 'Carl Nkosi');
    await _tap(tester, 'TAKE OFF (−)');
    await _type(tester, '4');
    await _tap(tester, 'NEXT');
    expect(find.text('No hours for Carl Nkosi on that day to take off'), findsOneWidget);
  });

  testWidgets('Hours typed on this phone and not sent yet count too', (tester) async {
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
    await _tap(tester, 'Person');
    await _tap(tester, 'TODAY');
    await _tap(tester, 'Carl Nkosi');
    expect(find.textContaining('Carl Nkosi: 7 h'), findsOneWidget);
  });

  testWidgets('Group hours: someone already sent for that day can be left out', (tester) async {
    final today = dayStr(DateTime.now());
    final store = await _pump(tester, const HoursFlow(), ref: _ref(clocked: {'p2|$today': 9}));
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Group');
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _hours(tester, '8');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect(find.textContaining('Ben Sithole: 9 h'), findsOneWidget);
    await _tap(tester, 'LEAVE THEIRS');
    final p = store.queue.single.payload;
    expect((p['entries'] as List).map((e) => (e as Map)['employee_id']), ['p1']);
    expect(p.containsKey('replace'), isFalse);
  });

  testWidgets('Group hours can be taken off, never below what each one has', (tester) async {
    final today = dayStr(DateTime.now());
    final store = await _pump(tester, const HoursFlow(), ref: _ref(clocked: {'p1|$today': 8, 'p2|$today': 3}));
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Group');
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _tap(tester, 'TAP TO ENTER THE HOURS');
    await _tap(tester, 'TAKE OFF (−)');
    await _type(tester, '4');
    await _tap(tester, 'OK');
    expect(find.text('TAKE OFF 4 hours each'), findsOneWidget);
    await _tap(tester, 'NEXT');
    // Ben has only 3 h that day.
    expect(find.text('Not that many hours on that day to take off for: Ben Sithole (has 3 h)'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.text('NEXT'))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await _tap(tester, 'Ben Sithole'); // untick
    await _tap(tester, 'OTHER HOURS');
    await _tap(tester, 'TAKE OFF (−)');
    await _type(tester, '3');
    await _tap(tester, 'OK');
    expect(find.text('take off 3 hours'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('Anna Mokoena: take off 4 h'), findsOneWidget);
    expect(find.text('Ben Sithole: take off 3 h'), findsOneWidget);
    await _tap(tester, 'SAVE');
    // No "already submitted" question: taking off is meant for their hours.
    final p = store.queue.single.payload;
    final entries = (p['entries'] as List).cast<Map>();
    expect({for (final e in entries) e['employee_id']: e['hours']}, {'p1': -4.0, 'p2': -3.0});
    expect(p.containsKey('replace'), isFalse);
  });

  testWidgets('Hours per person: anyone, on the farm worked', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    await _tap(tester, 'Person');
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
    await _tap(tester, 'Group');
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
    await _tap(tester, 'Person');
    await _tap(tester, 'TODAY');
    expect(find.text('Sent here from Farm Limpopodraai - Stockpoort -- clock here'), findsOneWidget);
    await _tap(tester, 'Ben Sithole');
    expect(find.text('How many hours did Ben Sithole work?'), findsOneWidget);
  });

  testWidgets('Group hours: someone worked other hours', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Group');
    await _tap(tester, 'Pack house');
    await _tap(tester, 'TODAY');
    await _hours(tester, '8');
    await _tap(tester, 'Ben Sithole');
    await _tap(tester, 'OTHER HOURS');
    expect(find.text('How many hours did Ben Sithole work?'), findsOneWidget);
    await _type(tester, '5');
    await _tap(tester, 'OK');
    expect(find.text('5 hours'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('Ben Sithole: 5 h'), findsOneWidget);
    await _tap(tester, 'SAVE');
    final entries = (store.queue.single.payload['entries'] as List).cast<Map>();
    expect({for (final e in entries) e['employee_id']: e['hours']}, {'p1': 8.0, 'p2': 5.0});
  });

  testWidgets('Hours: "Hours for:" Group / Person only, no kg', (tester) async {
    await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    expect(find.text('Hours for:'), findsOneWidget);
    expect(find.text('Group'), findsOneWidget);
    expect(find.text('Person'), findsOneWidget);
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

  testWidgets('Work groups: make a group, put people in it, clock it straight away', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    // Not on the first screen: WORK GROUPS is on the group step of a farm
    // that has groups.
    expect(find.text('WORK GROUPS'), findsNothing);
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Group');
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
    await _tap(tester, 'Group');
    expect(find.text('Pack house'), findsOneWidget);
    expect(find.text('Picking'), findsNothing);
  });

  testWidgets('Haaskraal: no groups, Group clocks everyone at the farm', (tester) async {
    final store = await _pump(tester, const HoursFlow());
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    await _tap(tester, 'Group');
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
    await _tap(tester, 'Group');
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
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    // The shop's own farm first; Limpopodraai workers under FROM OTHER FARM.
    expect(find.text('Carl Nkosi'), findsOneWidget);
    expect(find.text('Anna Mokoena'), findsNothing);
    await _tap(tester, 'FROM OTHER FARM');
    expect(find.text('Anna Mokoena'), findsOneWidget);
    await _tap(tester, 'Anna Mokoena');
    await _type(tester, '30');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect(store.queue.single.payload['employee_id'], 'p1');
    expect(store.queue.single.payload['farm_id'], 'f2');
  });

  testWidgets('Tuck shop item sale and Haaskraal amount', (tester) async {
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
    expect(find.text('R0'), findsOneWidget);
    await _type(tester, '55');
    expect(find.text('R55'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SAVE');
    expect(store.queue.last.payload['manual_total'], 55);
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
    for (final label in ['DIESEL', 'PACKAGING', 'HOURS', 'TUCK SHOP', 'EMPLOYEES', 'PAYSLIPS']) {
      await tester.scrollUntilVisible(find.text(label), 200, scrollable: find.byType(Scrollable).first);
      expect(tester.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines, isFalse, reason: label);
    }
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

  group('Employee details', () {
    Future<void> enter(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pumpAndSettle();
    }

    testWidgets('new worker without ID: name and farm only, rest later', (tester) async {
      final store = await _pump(tester, const EmployeeFlow());
      // The farm first: the new worker is added there.
      expect(find.text('Which farm?'), findsOneWidget);
      await _tap(tester, 'Farm Haaskraal - Swartwater');
      await _tap(tester, 'NEW WORKER');
      await _tap(tester, 'NEXT'); // no name yet
      expect(find.text('Name?'), findsOneWidget);
      await enter(tester, 'Sipho');
      await _tap(tester, 'NEXT');
      await _tap(tester, 'ADD LATER'); // ID
      await _tap(tester, 'ADD LATER'); // full names
      await _tap(tester, 'ADD LATER'); // surname
      expect(find.text('How are they paid?'), findsOneWidget); // no farm question again
      await _tap(tester, 'CASH');
      expect(find.text('Is this right?'), findsOneWidget);
      expect(find.text('Paid in cash'), findsOneWidget);
      await _tap(tester, 'SAVE');
      final e = store.queue.single;
      expect(e.module, CaptureModule.employee);
      expect(e.payload, {'action': 'add', 'name': 'Sipho', 'farm_id': 'f2', 'farm_name': 'Farm Haaskraal - Swartwater', 'payment_method': 'cash'});
      expect(e.summary, 'New worker: Sipho');
    });

    testWidgets('with an ID, full names and surname are required', (tester) async {
      final store = await _pump(tester, const EmployeeFlow());
      await _tap(tester, 'Farm Limpopodraai - Stockpoort');
      await _tap(tester, 'NEW WORKER');
      await enter(tester, 'Sipho');
      await _tap(tester, 'NEXT');
      await enter(tester, '900101500908'); // 12 digits
      await _tap(tester, 'NEXT');
      expect(find.text('ID or passport number?'), findsOneWidget); // blocked
      await enter(tester, '9001015009087');
      await _tap(tester, 'NEXT');
      expect(find.text('ADD LATER'), findsNothing); // not skippable with an ID
      await _tap(tester, 'NEXT');
      expect(find.text('Full names (as on the ID)?'), findsOneWidget); // blocked
      await enter(tester, 'Sipho Johannes');
      await _tap(tester, 'NEXT');
      await _tap(tester, 'NEXT');
      expect(find.text('Surname (as on the ID)?'), findsOneWidget); // blocked
      await enter(tester, 'Mokoena');
      await _tap(tester, 'NEXT');
      // Paid by bank: the bank and account number.
      await _tap(tester, 'BANK TRANSFER');
      expect(find.text('Which bank?'), findsOneWidget);
      await _tap(tester, 'Capitec');
      expect(find.text('Account number?'), findsOneWidget);
      await enter(tester, '12AB');
      await _tap(tester, 'NEXT');
      expect(find.text('Account number?'), findsOneWidget); // numbers only
      await enter(tester, '1234567890');
      await _tap(tester, 'NEXT');
      expect(find.text('Bank transfer: Capitec 1234567890'), findsOneWidget);
      await _tap(tester, 'SAVE');
      expect(store.queue.single.payload, {
        'action': 'add',
        'name': 'Sipho',
        'id_or_passport': '9001015009087',
        'full_names': 'Sipho Johannes',
        'surname': 'Mokoena',
        'farm_id': 'f1',
        'farm_name': 'Farm Limpopodraai - Stockpoort',
        'payment_method': 'bank',
        'bank_name': 'Capitec',
        'bank_account_no': '1234567890',
      });
    });

    testWidgets('change: only what changed is sent', (tester) async {
      final store = await _pump(tester, const EmployeeFlow());
      await _tap(tester, 'Farm Limpopodraai - Stockpoort');
      await _tap(tester, 'CHANGE DETAILS');
      // The farm's workers; Carl (Haaskraal) only under FROM OTHER FARM.
      expect(find.text('Carl Nkosi'), findsNothing);
      await _tap(tester, 'Ben Sithole');
      // Everything the office has is filled in.
      expect(find.widgetWithText(TextField, 'Ben Sithole'), findsOneWidget);
      await enter(tester, 'Benny Sithole');
      await _tap(tester, 'NEXT');
      expect(find.widgetWithText(TextField, '8505055009081'), findsOneWidget);
      await _tap(tester, 'NEXT');
      expect(find.widgetWithText(TextField, 'Benjamin'), findsOneWidget);
      await _tap(tester, 'NEXT');
      expect(find.widgetWithText(TextField, 'Sithole'), findsOneWidget);
      await _tap(tester, 'NEXT');
      await _tap(tester, 'NEXT'); // farm unchanged (already chosen)
      await _tap(tester, 'NEXT'); // paid in cash, as before
      await _tap(tester, 'SAVE');
      expect(store.queue.single.payload, {'action': 'change', 'employee_id': 'p2', 'employee_name': 'Ben Sithole', 'name': 'Benny Sithole'});
    });

    testWidgets('change: a worker with no ID on file can get one (then ID names are needed)', (tester) async {
      final store = await _pump(tester, const EmployeeFlow());
      await _tap(tester, 'Farm Limpopodraai - Stockpoort');
      await _tap(tester, 'CHANGE DETAILS');
      await _tap(tester, 'Anna Mokoena');
      await _tap(tester, 'NEXT');
      expect(find.text('ADD LATER'), findsOneWidget);
      await enter(tester, '9001015009087');
      await _tap(tester, 'NEXT');
      await _tap(tester, 'NEXT');
      expect(find.text('Full names (as on the ID)?'), findsOneWidget); // required now
      await enter(tester, 'Anna Maria');
      await _tap(tester, 'NEXT');
      await enter(tester, 'Mokoena');
      await _tap(tester, 'NEXT');
      await _tap(tester, 'NEXT');
      await _tap(tester, 'NEXT');
      await _tap(tester, 'SAVE');
      expect(store.queue.single.payload, {
        'action': 'change',
        'employee_id': 'p1',
        'employee_name': 'Anna Mokoena',
        'id_or_passport': '9001015009087',
        'full_names': 'Anna Maria',
        'surname': 'Mokoena',
      });
    });

    testWidgets('change: paid by ATM needs a phone number', (tester) async {
      final store = await _pump(tester, const EmployeeFlow());
      await _tap(tester, 'Farm Haaskraal - Swartwater');
      await _tap(tester, 'CHANGE DETAILS');
      await _tap(tester, 'Carl Nkosi');
      // Name, ID, names and farm unchanged: on to "How are they paid?".
      while (find.text('How are they paid?').evaluate().isEmpty) {
        await _tap(tester, find.text('ADD LATER').evaluate().isNotEmpty ? 'ADD LATER' : 'NEXT');
      }
      await _tap(tester, 'ATM');
      expect(find.text('Phone number?'), findsOneWidget);
      await enter(tester, '12345');
      await _tap(tester, 'NEXT');
      expect(find.text('Phone number?'), findsOneWidget); // not a phone number
      await enter(tester, '072 123 4567');
      await _tap(tester, 'NEXT');
      expect(find.text('ATM: phone 072 123 4567'), findsOneWidget);
      await _tap(tester, 'SAVE');
      expect(store.queue.single.payload, {
        'action': 'change',
        'employee_id': 'p3',
        'employee_name': 'Carl Nkosi',
        'payment_method': 'atm',
        'phone_number': '072 123 4567',
      });
    });

    testWidgets('worker left', (tester) async {
      final store = await _pump(tester, const EmployeeFlow());
      await _tap(tester, 'Farm Haaskraal - Swartwater');
      await _tap(tester, 'WORKER LEFT');
      await _tap(tester, 'Carl Nkosi');
      expect(find.text('Carl Nkosi has left the farm'), findsOneWidget);
      await _tap(tester, 'SAVE');
      expect(store.queue.single.payload, {'action': 'remove', 'employee_id': 'p3', 'employee_name': 'Carl Nkosi'});
      expect(store.queue.single.summary, 'Left: Carl Nkosi');
    });
  });
}
