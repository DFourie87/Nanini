import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/capture_store.dart';
import 'package:nanini_app/capture_app/flows/payslips_flow.dart';
import 'package:nanini_app/capture_app/ref_data.dart';
import 'package:nanini_app/features/capture/capture_models.dart';
import 'package:provider/provider.dart';

String _day(int ago) => DateTime.now().subtract(Duration(days: ago)).toIso8601String().substring(0, 10);

/// Capture phone lists with the Payslips task's pay data, in the shape
/// capture_reference sends it.
RefData _ref() => RefData(
      farms: const [RefItem('fa', 'Farm Limpopodraai - Stockpoort'), RefItem('fb', 'Farm Haaskraal - Swartwater')],
      people: const [],
      groups: const [],
      tanks: const [],
      vehicles: const [],
      activities: const [],
      shopItems: const [],
      payJson: {
        'employees': [
          {'id': 'anna', 'first_name': 'Anna', 'last_name': '', 'farm_id': 'fa', 'rate_per_hour': 30, 'loan_deduction': 100},
          {'id': 'cara', 'first_name': 'Cara', 'last_name': '', 'farm_id': 'fb', 'rate_per_hour': null},
          // Haaskraal worker with nothing logged since the last pay: still listed.
          {'id': 'fay', 'first_name': 'Fay', 'last_name': '', 'farm_id': 'fb', 'rate_per_hour': 25},
          {'id': 'gus', 'first_name': 'Gus', 'last_name': ''}, // no farm
        ],
        'hours': [
          {'id': 'h1', 'employee_id': 'anna', 'entry_date': _day(20), 'hours': 8}, // before the last pay
          {'id': 'h2', 'employee_id': 'anna', 'entry_date': _day(3), 'hours': 9},
          {'id': 'h3', 'employee_id': 'cara', 'entry_date': _day(2), 'hours': 6},
        ],
        'kg': [],
        'tuck': [
          {'id': 't1', 'employee_id': 'anna', 'sale_date': _day(4), 'revenue': 40, 'farm_id': 'fa'},
        ],
        'paid': [
          {'id': 'anna', 'employee_id': 'anna', 'farm_id': 'fa', 'period_start': _day(40), 'period_end': _day(10), 'paid_date': _day(10)},
        ],
        'extras': [],
      },
    );

Future<CaptureStore> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final store = CaptureStore.forTest(_ref());
  await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: PayslipsFlow())));
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
  testWidgets('every worker on the farm is listed, even with no hours (Haaskraal)', (tester) async {
    await _pump(tester);
    expect(find.text('Which farm?'), findsOneWidget);
    expect(find.text('2 workers · 6 h since the last pay'), findsOneWidget); // Haaskraal: Cara + Fay
    expect(find.textContaining('no farm in Employees > List: Gus'), findsOneWidget);
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    expect(find.text('Hours since the last pay'), findsOneWidget);
    expect(find.text('Cara'), findsOneWidget);
    expect(find.text('Fay'), findsOneWidget);
    expect(find.text('0 h'), findsOneWidget);
  });

  testWidgets('tariff, extra pay and loan are sent to the office to approve', (tester) async {
    final store = await _pump(tester);
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    expect(find.text('9 h'), findsOneWidget); // only since the last pay
    await _tap(tester, 'NEXT');
    // Tariffs: change Anna's.
    await _tap(tester, 'Anna');
    await _type(tester, '32');
    await _tap(tester, 'OK');
    expect(find.text('R32 per hour (changed)'), findsOneWidget);
    await _tap(tester, 'NEXT');
    // Extra pay: a bonus.
    await _tap(tester, 'ADD');
    await _tap(tester, 'AN AMOUNT');
    await _tap(tester, 'Bonus');
    await _type(tester, '500');
    await _tap(tester, 'OK');
    expect(find.text('R500'), findsOneWidget);
    await _tap(tester, 'NEXT');
    // Deductions: tuck shop debt shown, loan changed.
    expect(find.text('R40'), findsOneWidget);
    await _tap(tester, 'Loan');
    await _type(tester, '150'); // replaces the R100 shown
    await _tap(tester, 'OK');
    await _tap(tester, 'NEXT');
    // PAYE and UIF: nothing to change.
    expect(find.text('PAYE and UIF'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('Anna: tariff R32/h'), findsOneWidget);
    await _tap(tester, 'SEND');
    final e = store.queue.single;
    expect(e.module, CaptureModule.payCheck);
    expect(e.payload['farm_id'], 'fa');
    expect(e.payload['changes'], [
      {'employee_id': 'anna', 'employee_name': 'Anna', 'rate_per_hour': 32.0, 'loan_deduction': 150.0},
    ]);
    final extra = (e.payload['extras'] as List).single as Map;
    expect(extra['description'], 'Bonus');
    expect(extra['amount'], 500.0);
  });

  testWidgets('nothing changed: DONE, nothing sent', (tester) async {
    final store = await _pump(tester);
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    for (var n = 0; n < 5; n++) {
      await _tap(tester, 'NEXT');
    }
    expect(find.textContaining('Nothing changed'), findsOneWidget);
    await _tap(tester, 'DONE');
    expect(store.queue, isEmpty);
  });

  testWidgets('tuck shop debt at the pay farm only: one line, as before', (tester) async {
    await _pump(tester);
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    for (var n = 0; n < 3; n++) {
      await _tap(tester, 'NEXT');
    }
    // Bought only at the pay farm's shop: just "Tuck shop", no farm name.
    expect(find.text('Tuck shop'), findsOneWidget);
    expect(find.text('Tuck shop Limpopodraai'), findsNothing);
    expect(find.text('Tuck shop Haaskraal'), findsNothing);
    // Limpopodraai's debt comes from its till: not typed in.
    await _tap(tester, 'Tuck shop');
    expect(find.textContaining('tuck shop debt of'), findsNothing);
  });

  testWidgets('Limpopodraai worker who bought only at Haaskraal: own shop line plus Haaskraal, from its sales', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final ref = _ref();
    final tuck = ref.payJson!['tuck'] as List;
    tuck
      ..clear()
      ..add({'id': 't2', 'employee_id': 'anna', 'sale_date': _day(2), 'revenue': 60, 'farm_id': 'fb'});
    final store = CaptureStore.forTest(RefData(
      farms: ref.farms,
      people: const [],
      groups: const [],
      tanks: const [],
      vehicles: const [],
      activities: const [],
      shopItems: const [],
      payJson: ref.payJson,
    ));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: PayslipsFlow())));
    await tester.pumpAndSettle();
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    for (var n = 0; n < 3; n++) {
      await _tap(tester, 'NEXT');
    }
    expect(find.text('Tuck shop Limpopodraai'), findsOneWidget);
    expect(find.text('Tuck shop Haaskraal'), findsOneWidget);
    // Haaskraal sells per item too: its debt comes from its sales.
    await _tap(tester, 'Tuck shop Haaskraal');
    expect(find.textContaining('tuck shop debt of'), findsNothing);
  });

  testWidgets('tuck shop debt at Haaskraal too: separate lines, from each shop\'s sales', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final ref = _ref();
    (ref.payJson!['tuck'] as List).add({'id': 't2', 'employee_id': 'anna', 'sale_date': _day(2), 'revenue': 60, 'farm_id': 'fb'});
    final store = CaptureStore.forTest(RefData(
      farms: ref.farms,
      people: const [],
      groups: const [],
      tanks: const [],
      vehicles: const [],
      activities: const [],
      shopItems: const [],
      payJson: ref.payJson,
    ));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: PayslipsFlow())));
    await tester.pumpAndSettle();
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    for (var n = 0; n < 3; n++) {
      await _tap(tester, 'NEXT');
    }
    expect(find.text('Tuck shop Limpopodraai'), findsOneWidget);
    expect(find.text('Tuck shop Haaskraal'), findsOneWidget);
    expect(find.text('R40'), findsOneWidget);
    expect(find.text('R60'), findsOneWidget);
    await _tap(tester, 'Tuck shop Haaskraal');
    expect(find.textContaining('tuck shop debt of'), findsNothing);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    expect(find.textContaining('Haaskraal tuck shop'), findsNothing);
    expect(store.queue, isEmpty);
  });

  testWidgets('hours since the last pay can be changed', (tester) async {
    final store = await _pump(tester);
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Anna');
    expect(find.text('Hours of Anna since the last pay?'), findsOneWidget);
    await _type(tester, '45'); // replaces the 9 shown
    await _tap(tester, 'OK');
    expect(find.text('45 h'), findsWidgets);
    for (var n = 0; n < 5; n++) {
      await _tap(tester, 'NEXT');
    }
    expect(find.text('Anna: 45 h since the last pay (was 9 h)'), findsOneWidget);
    await _tap(tester, 'SEND');
    final c = (store.queue.single.payload['changes'] as List).single as Map;
    expect(c['hours_since_last_pay'], 45.0);
    expect(c['hours_was'], 9.0);
  });

  testWidgets('tariff and rent typed once are remembered next time', (tester) async {
    final store = await _pump(tester);
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'Anna');
    await _type(tester, '35');
    await _tap(tester, 'OK');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'Rent');
    await _type(tester, '200');
    await _tap(tester, 'OK');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SEND');
    expect(store.queue, hasLength(1));

    // Next check (office hasn't approved yet): starts from R35 and R200.
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(key: ValueKey(2), home: PayslipsFlow())));
    await tester.pumpAndSettle();
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'NEXT');
    expect(find.text('R35 per hour (sent before)'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    expect(find.text('R200'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    expect(find.textContaining('Nothing changed'), findsOneWidget);
  });

  testWidgets('PAYE and UIF: PAYE only over the threshold, UIF chosen and remembered', (tester) async {
    final store = await _pump(tester);
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    expect(find.text('PAYE and UIF'), findsOneWidget);
    // R270 pay: no PAYE line. No ID on file and not chosen: no UIF.
    expect(find.text('PAYE'), findsNothing);
    expect(find.text('Not deducted'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('UIF (changed)'), findsOneWidget);
    expect(find.text('Deducted: R2,7'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('Anna: UIF deducted'), findsOneWidget);
    await _tap(tester, 'SEND');
    expect(store.queue.single.payload['changes'], [
      {'employee_id': 'anna', 'employee_name': 'Anna', 'uif_deduct': true},
    ]);

    // Next time (not approved yet) UIF stays on; a big bonus brings PAYE.
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(key: ValueKey(3), home: PayslipsFlow())));
    await tester.pumpAndSettle();
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'ADD');
    await _tap(tester, 'AN AMOUNT');
    await _tap(tester, 'Bonus');
    await _type(tester, '40000');
    await _tap(tester, 'OK');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    expect(find.text('PAYE'), findsOneWidget);
    expect(find.text('UIF'), findsOneWidget);
    expect(find.textContaining('Deducted: R'), findsOneWidget);
  });

  testWidgets('Haaskraal worker, bought at Haaskraal only: plain "Tuck shop", from its sales', (tester) async {
    await _pump(tester);
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NO TARIFF -- tap to set'); // Cara
    await _type(tester, '30');
    await _tap(tester, 'OK');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    expect(find.text('Tuck shop Haaskraal'), findsNothing);
    await _tap(tester, 'Tuck shop'); // Cara (first)
    expect(find.textContaining('tuck shop debt of'), findsNothing);
  });

  testWidgets('Haaskraal worker who bought per item at Limpopodraai: two lines, neither typed in', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final ref = _ref();
    (ref.payJson!['tuck'] as List)
      // Sold per item, saved before the shop was recorded: Limpopodraai's.
      ..add({'id': 't3', 'employee_id': 'cara', 'sale_date': _day(3), 'revenue': 30, 'item_id': 'bread'})
      ..add({'id': 't4', 'employee_id': 'cara', 'sale_date': _day(2), 'revenue': 50, 'farm_id': 'fb'});
    final store = CaptureStore.forTest(RefData(
      farms: ref.farms,
      people: const [],
      groups: const [],
      tanks: const [],
      vehicles: const [],
      activities: const [],
      shopItems: const [],
      payJson: ref.payJson,
    ));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: PayslipsFlow())));
    await tester.pumpAndSettle();
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NO TARIFF -- tap to set'); // Cara
    await _type(tester, '30');
    await _tap(tester, 'OK');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    expect(find.text('Tuck shop Haaskraal'), findsOneWidget);
    expect(find.text('Tuck shop Limpopodraai'), findsOneWidget);
    expect(find.text('R50'), findsOneWidget);
    expect(find.text('R30'), findsOneWidget);
    await _tap(tester, 'Tuck shop Limpopodraai');
    expect(find.textContaining('tuck shop debt of'), findsNothing);
    await _tap(tester, 'Tuck shop Haaskraal');
    expect(find.textContaining('tuck shop debt of'), findsNothing);
  });

  testWidgets('Haaskraal worker who bought only at Limpopodraai (Frank): own Haaskraal line still shown', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final ref = _ref();
    (ref.payJson!['tuck'] as List).add({'id': 't5', 'employee_id': 'cara', 'sale_date': _day(3), 'revenue': 30, 'farm_id': 'fa'});
    final store = CaptureStore.forTest(RefData(
      farms: ref.farms,
      people: const [],
      groups: const [],
      tanks: const [],
      vehicles: const [],
      activities: const [],
      shopItems: const [],
      payJson: ref.payJson,
    ));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: PayslipsFlow())));
    await tester.pumpAndSettle();
    await _tap(tester, 'Farm Haaskraal - Swartwater');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NO TARIFF -- tap to set'); // Cara
    await _type(tester, '30');
    await _tap(tester, 'OK');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    expect(find.text('Tuck shop Haaskraal'), findsOneWidget);
    expect(find.text('Tuck shop Limpopodraai'), findsOneWidget);
    await _tap(tester, 'Tuck shop Haaskraal');
    expect(find.textContaining('tuck shop debt of'), findsNothing);
    expect(find.text('R30'), findsOneWidget);
  });

  testWidgets('hours not yet approved count too: another phone\'s and this phone\'s own', (tester) async {
    final ref = _ref();
    final store = CaptureStore.forTest(RefData(
      farms: ref.farms,
      people: ref.people,
      groups: ref.groups,
      tanks: ref.tanks,
      vehicles: ref.vehicles,
      activities: ref.activities,
      shopItems: ref.shopItems,
      payJson: {
        ...ref.payJson!,
        // Sent from another phone, waiting in the hub's inbox.
        'pending': [
          {
            'id': 'c1',
            'module': 'hours',
            'captured_at': '${_day(1)}T08:00:00Z',
            'payload': {
              'date': _day(1),
              'farm_id': 'fa',
              'entries': [
                {'employee_id': 'anna', 'hours': 7},
              ],
            },
          },
        ],
      },
    ));
    // Captured on this phone, not sent yet.
    await store.add(CaptureModule.hours, {
      'mode': 'individual',
      'date': _day(0),
      'farm_id': 'fa',
      'entries': [
        {'employee_id': 'anna', 'hours': 4},
      ],
    }, 'Hours');
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: PayslipsFlow())));
    await tester.pumpAndSettle();
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    // 9 approved + 7 + 4 waiting.
    expect(find.text('20 h'), findsOneWidget);
    expect(find.textContaining('incl. 11 h still to approve'), findsOneWidget);
  });

  testWidgets('payslip hours already put in the hours are not counted twice', (tester) async {
    final ref = _ref();
    final store = CaptureStore.forTest(RefData(
      farms: ref.farms,
      people: ref.people,
      groups: ref.groups,
      tanks: ref.tanks,
      vehicles: ref.vehicles,
      activities: ref.activities,
      shopItems: ref.shopItems,
      payJson: {
        ...ref.payJson!,
        // Its hours went in when it was sent (the 9 h); a tariff still waits.
        'pending': [
          {
            'id': 'c2',
            'module': 'pay_check',
            'captured_at': '${_day(0)}T08:00:00Z',
            'payload': {
              'farm_id': 'fa',
              'hours_applied': true,
              'changes': [
                {'employee_id': 'anna', 'rate_per_hour': 30, 'hours_since_last_pay': 9, 'hours_was': 5, 'hours_up_to': _day(0)},
              ],
              'extras': [],
            },
          },
        ],
      },
    ));
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: PayslipsFlow())));
    await tester.pumpAndSettle();
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    expect(find.text('9 h'), findsOneWidget);
    expect(find.text('13 h'), findsNothing);
  });

  testWidgets('a payslip check sent earlier still shows until approved', (tester) async {
    final store = await _pump(tester);
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Anna'); // hours
    await _type(tester, '12');
    await _tap(tester, 'OK');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'ADD');
    await _tap(tester, 'AN AMOUNT');
    await _tap(tester, 'Bonus');
    await _type(tester, '300');
    await _tap(tester, 'OK');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'SEND');
    expect(store.queue, hasLength(1));
    // The hours typed on the first page go to the office.
    final change = (store.queue.single.payload['changes'] as List).single as Map;
    expect(change['hours_since_last_pay'], 12.0);
    expect(change['hours_was'], 9.0);

    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(key: ValueKey(4), home: PayslipsFlow())));
    await tester.pumpAndSettle();
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    expect(find.text('12 h'), findsOneWidget);
    expect(find.textContaining('incl. 3 h still to approve'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    expect(find.text('R300'), findsOneWidget); // the bonus sent before
  });
}
