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
    expect(find.text('R 32 per hour (changed)'), findsOneWidget);
    await _tap(tester, 'NEXT');
    // Extra pay: a bonus.
    await _tap(tester, 'ADD');
    await _tap(tester, 'AN AMOUNT');
    await _tap(tester, 'Bonus');
    await _type(tester, '500');
    await _tap(tester, 'OK');
    expect(find.text('R 500'), findsOneWidget);
    await _tap(tester, 'NEXT');
    // Deductions: tuck shop debt shown, loan changed.
    expect(find.text('R 40'), findsOneWidget);
    await _tap(tester, 'Loan');
    await _type(tester, '150'); // replaces the R 100 shown
    await _tap(tester, 'OK');
    await _tap(tester, 'NEXT');
    expect(find.text('Anna: tariff R 32/h'), findsOneWidget);
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
    for (var n = 0; n < 4; n++) {
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

  testWidgets('bought only at Haaskraal: one line, Haaskraal, typed in', (tester) async {
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
    expect(find.text('Tuck shop Limpopodraai'), findsNothing);
    expect(find.text('Tuck shop Haaskraal'), findsOneWidget);
    await _tap(tester, 'Tuck shop Haaskraal');
    expect(find.text('Haaskraal tuck shop debt of Anna?'), findsOneWidget);
  });

  testWidgets('tuck shop debt at Haaskraal too: separate lines, Haaskraal typed in', (tester) async {
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
    expect(find.text('R 40'), findsOneWidget);
    expect(find.text('R 60'), findsOneWidget);
    await _tap(tester, 'Tuck shop Haaskraal');
    expect(find.text('Haaskraal tuck shop debt of Anna?'), findsOneWidget);
    await _type(tester, '80');
    await _tap(tester, 'OK');
    expect(find.text('R 80'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.text('Anna: Haaskraal tuck shop R 80'), findsOneWidget);
    await _tap(tester, 'SEND');
    final c = (store.queue.single.payload['changes'] as List).single as Map;
    expect(c['tuckshop_debt'], 80.0);
    expect(c['tuckshop_farm_id'], 'fb');
  });

  testWidgets('hours since the last pay can be changed', (tester) async {
    final store = await _pump(tester);
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'Anna');
    expect(find.text('Hours of Anna since the last pay?'), findsOneWidget);
    await _type(tester, '45'); // replaces the 9 shown
    await _tap(tester, 'OK');
    expect(find.text('45 h'), findsWidgets);
    for (var n = 0; n < 4; n++) {
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
    await _tap(tester, 'SEND');
    expect(store.queue, hasLength(1));

    // Next check (office hasn't approved yet): starts from R 35 and R 200.
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(key: ValueKey(2), home: PayslipsFlow())));
    await tester.pumpAndSettle();
    await _tap(tester, 'Farm Limpopodraai - Stockpoort');
    await _tap(tester, 'NEXT');
    expect(find.text('R 35 per hour (sent before)'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _tap(tester, 'NEXT');
    expect(find.text('R 200'), findsOneWidget);
    await _tap(tester, 'NEXT');
    expect(find.textContaining('Nothing changed'), findsOneWidget);
  });

  testWidgets('Haaskraal worker, bought at Haaskraal only: plain "Tuck shop", typed in', (tester) async {
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
    expect(find.text('Haaskraal tuck shop debt of Cara?'), findsOneWidget);
  });
}
