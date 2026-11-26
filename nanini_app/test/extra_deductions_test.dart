import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/hours_data.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/hours_repository.dart';
import 'package:nanini_app/features/hours/pay_edit.dart';
import 'package:nanini_app/features/hours/pay_run.dart';

final anna = Employee(id: 'a', firstName: 'Anna', lastName: '', farmId: 'f', ratePerHour: 30);

HoursEntry day(String emp, double h) => HoursEntry(
  id: 'h$emp',
  employeeId: emp,
  date: '2026-11-10',
  hours: h,
  rate: 30,
  dailyThreshold: 9,
  otMultiplier: 1.5,
  normalHours: h,
  otHours: 0,
  gross: h * 30,
);

PayExtra extra(String id, String what, double amount, {bool deduction = false}) =>
    PayExtra(id: id, employeeId: 'a', date: '2026-11-12', description: what, amount: amount, isDeduction: deduction);

void main() {
  test('an extra deduction comes off the nett, not the gross (PAYE and UIF stay on the gross)', () {
    final l = PayLine(
      employee: anna,
      since: null,
      entries: [day('a', 10)],
      kgEntries: const [],
      purchases: const [],
      extras: [extra('x1', 'Bonus', 100), extra('x2', 'Broken spade', 80, deduction: true)],
    );
    expect(l.extraPay, 100);
    expect(l.gross, 300 + 100);
    expect(l.extraDeductions, 80);
    expect(l.deductions, 80);
    expect(l.nett, 400 - 80);
    expect(l.payExtras.map((x) => x.description), ['Bonus']);

    final slip = draftPayslip(l, upTo: '2026-11-15', paidDate: '2026-11-15');
    expect(slip.extraPay, 100);
    expect(slip.extras.map((x) => x['description']), ['Bonus']); // pay lines only
    expect(slip.extraDeductions, 80);
    expect(slip.deductionLines, [
      {'description': 'Broken spade', 'amount': 80.0},
    ]);
    expect(slip.totalDeductions, 80);
    expect(slip.toInsert()['extra_deductions'], 80);
    final read = Payslip.fromJson({...slip.toInsert(), 'id': 'p', 'created_at': '2026-11-15T10:00:00'});
    expect(read.extraDeductions, 80);
    expect(read.deductionLines.single['description'], 'Broken spade');
    // Without one, the payslip doesn't send the columns.
    final plain = draftPayslip(
      PayLine(employee: anna, since: null, entries: [day('a', 10)], kgEntries: const [], purchases: const []),
      upTo: '2026-11-15',
      paidDate: '2026-11-15',
    );
    expect(plain.toInsert().containsKey('extra_deductions'), isFalse);
    // Saved in one go with one that has: 0 and no lines, never empty.
    final both = sameFields([slip.toInsert(), plain.toInsert()]);
    expect(both[1]['extra_deductions'], 0);
    expect(both[1]['deduction_lines'], isEmpty);
    expect(both[1]['extra_pay'], 0);
    expect(both[0]['extra_deductions'], 80);
    expect(both[1].keys.toSet(), both[0].keys.toSet());
    expect(PayExtra.fromJson({'id': 'x', 'employee_id': 'a', 'entry_date': '2026-11-12', 'amount': 5, 'is_deduction': true}).isDeduction, isTrue);
  });

  testWidgets('Summary: under Extra pay, an Extra deductions line with Add', (tester) async {
    final data = HoursData.forTest(
      HoursRepository(),
      employees: [anna],
      entries: [day('a', 10)],
      extras: [extra('x1', 'Bonus', 100), extra('x2', 'Broken spade', 80, deduction: true)],
    );
    final line = PayLine(employee: anna, since: null, entries: [day('a', 10)], kgEntries: const [], purchases: const []);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(onPressed: () => showPayLineEditor(c, data, line, DateTime(2026, 11, 15)), child: const Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    double top(Finder f) => tester.getTopLeft(f).dy;
    await tester.scrollUntilVisible(find.text('Extra deductions'), 200, scrollable: find.byType(Scrollable).last);
    expect(top(find.text('Extra pay')), lessThan(top(find.text('Extra deductions'))));
    expect(top(find.text('Bonus')), lessThan(top(find.text('Extra deductions'))));
    expect(top(find.text('Broken spade')), greaterThan(top(find.text('Extra deductions'))));
    expect(find.text('-R80'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pay_edit_add_deduction')));
    await tester.pumpAndSettle();
    expect(find.text('Extra deduction -- Anna'), findsOneWidget);
    expect(find.text('Hours at a rate'), findsNothing); // an amount only
    expect(find.text('Amount to take off'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
