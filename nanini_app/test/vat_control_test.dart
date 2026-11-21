import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/vat/vat_models.dart';
import 'package:nanini_app/features/vat/vat_repository.dart';
import 'package:nanini_app/features/vat/vat_screen.dart';
import 'package:nanini_app/features/vat/vat_xlsx.dart';

// Made-up figures.
final List<VatSale> sales = [
  (date: '2026-03-10', crop: 'Potatoes', gross: 100000, vatOnSales: 0, deductionsVat: 1500, pallets: 0),
  (date: '2026-04-20', crop: 'Peppers', gross: 50000, vatOnSales: 0, deductionsVat: 750, pallets: 1150),
  (date: '2026-05-02', crop: 'Tobacco', gross: 200000, vatOnSales: 30000, deductionsVat: 0, pallets: 0),
  (date: '2027-02-27', crop: 'Potatoes', gross: 10000, vatOnSales: 0, deductionsVat: 0, pallets: 0),
  (date: '2027-03-01', crop: 'Potatoes', gross: 99999, vatOnSales: 0, deductionsVat: 0, pallets: 0), // next year
];
final List<VatPurchase> purchases = [(date: '2026-03-15', vat: 3000, capital: false), (date: '2026-04-01', vat: 15000, capital: true)];

void main() {
  test('periods of two months from March; Jan - Feb ends the year', () {
    expect(vatPeriodStarts('2026-03-01'), ['2026-03-01', '2026-05-01', '2026-07-01', '2026-09-01', '2026-11-01', '2027-01-01']);
    expect(vatPeriodOf('2026-04-30'), '2026-03-01');
    expect(vatPeriodOf('2027-02-28'), '2027-01-01');
    expect(vatYearStart('2027-02-28'), '2026-03-01');
  });

  test('the hub\'s figures and those entered: output VAT, input VAT, diesel, net, against the VAT201', () {
    final hub = vatHubFigures('2026-03-01', sales, purchases);
    final y = vatYear('2026-03-01', hub, [
      VatManual(periodStart: '2026-03-01', otherStandard: 23000, dieselRefund: 2000, vat201Output: 3150, vat201Input: 20250, vat201Diesel: 2000),
    ], fsSales: 400000);
    final p = y.periods.first;
    expect(p.label, 'Mar - Apr 2026');
    expect((p.standard, p.zeroRated), (1150.0 + 23000, 150000.0)); // pallets and hunting; potatoes and peppers
    expect(p.outputVat, 3150); // 24 150 x 15/115
    expect((p.inputStandard, p.inputCapital, p.inputVat), (5250.0, 15000.0, 20250.0)); // commission VAT and supplier
    expect(p.net, 3150 - 20250 - 2000);
    expect((p.vat201Net, p.difference), (-19100.0, 0.0));
    final may = y.periods[1];
    expect((may.standard, may.outputVat, may.difference), (230000.0, 30000.0, null)); // tobacco with its VAT
    expect(y.periods.last.zeroRated, 10000);
    expect(y.salesExcl, 21000 + 200000 + 160000); // standard less VAT, and zero-rated
    expect(y.salesDifference, 381000 - 400000);
    expect(y.zeroByCrop, {'Potatoes': 110000.0, 'Peppers': 50000.0});
    expect(y.standardBySource, {'Pallets sold': 1150.0, 'Tobacco (account sales)': 230000.0, 'Other (entered)': 23000.0});
    final x = Excel.decodeBytes(vatControlXlsx(y, preparedOn: '2026-11-21'));
    final rows = x['VAT control'].rows.map((r) => r.map((c) => c?.value?.toString() ?? '').join('|')).toList();
    expect(rows.any((r) => r.startsWith('Mar - Apr 2026|24150|0|150000|3150|15000|5250|20250|2000|-19100|-19100|0')), isTrue);
    expect(rows.any((r) => r.startsWith('Difference|||-19000')), isTrue);
  });

  testWidgets('the screen: a period\'s figures entered, the VAT201 difference, the Excel', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    final saved = <String, Uint8List>{};
    await tester.pumpWidget(
      MaterialApp(
        home: VatScreen(
          repo: repo,
          today: DateTime(2026, 11, 21),
          save: (n, b) async {
            saved[n] = b;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mar - Apr 2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('vat_edit_2026-03-01')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vat_field_VAT201: output VAT')), '0');
    await tester.enterText(find.byKey(const Key('vat_field_VAT201: input VAT')), '20000');
    await tester.tap(find.byKey(const Key('vat_save')));
    await tester.pumpAndSettle();
    expect(repo.manual.single.vat201Input, 20000);
    expect(find.text('-R20 000.00'), findsOneWidget); // per VAT201
    expect(find.text('-R100.00'), findsOneWidget); // the difference: 150 output less 20 250 input (-20 100) against -20 000
    await tester.tap(find.byKey(const Key('vat_excel')));
    await tester.pumpAndSettle();
    expect(saved.keys, ['VAT control year 2027.xlsx']);
    expect(tester.takeException(), isNull);
  });
}

class _Repo extends VatRepository {
  final manual = <VatManual>[];
  @override
  Future<List<VatSale>> fetchSales(String from, String to) async => sales;
  @override
  Future<List<VatPurchase>> fetchPurchases(String from, String to) async => purchases;
  @override
  Future<List<VatManual>> fetchManual() async => manual;
  @override
  Future<void> saveManual(VatManual m) async => manual
    ..removeWhere((x) => x.periodStart == m.periodStart)
    ..add(m);
  @override
  Future<Map<String, double>> fetchFsSales() async => const {};
}
