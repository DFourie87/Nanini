import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/emp201_year.dart';
import 'package:nanini_app/features/hours/emp201_year_screen.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/payroll_month.dart';

void main() {
  test('UIF: 1% up to the R17 712 ceiling (R177.12)', () {
    expect(calcUIF(5000), 50);
    expect(calcUIF(29600), closeTo(177.12, 0.001));
    expect(calcUIF(27000), closeTo(177.12, 0.001));
  });

  test('tax year: March to February, named by the year it ends', () {
    expect(taxYearOf(DateTime(2026, 3, 1)), 2027);
    expect(taxYearOf(DateTime(2027, 2, 28)), 2027);
    expect(taxYearOf(DateTime(2026, 2, 28)), 2026);
    final m = taxYearMonths(2027);
    expect(m.first, '2026-03-01');
    expect(m.last, '2027-02-01');
  });

  Payslip slip(String emp, String paid, double gross, double paye) => Payslip(
        id: emp + paid,
        employeeId: emp,
        farmId: 'fa',
        periodStart: paid,
        periodEnd: paid,
        paidDate: paid,
        gross: gross,
        hoursWorked: 0,
        paye: paye,
        uif: calcUIF(gross),
        rent: 0,
        loan: 0,
        tuckshopDeduction: 0,
        nett: gross - paye - calcUIF(gross),
        createdAt: DateTime(2026),
      );
  final employees = [
    Employee(id: 'f', firstName: 'Francois', lastName: 'Fourie', farmId: 'fa', isMember: true, monthlySalary: 29600),
    Employee(id: 'a', firstName: 'Anna', lastName: 'Mokoena', farmId: 'fa'),
  ];
  final history = [
    const Emp201HistoryLine(month: '2026-08-01', name: 'JF FOURIE', employeeId: 'f', salary: 29600, uif: 354.24, sdl: 0, paye: 4577),
    const Emp201HistoryLine(month: '2026-08-01', name: 'Brian', salary: 5600, uif: 112, sdl: 0, paye: 0),
  ];
  final payslips = [
    slip('f', '2026-09-30', 29600, 4577),
    slip('a', '2026-09-12', 2500, 0),
    slip('a', '2026-09-26', 2600, 0),
    slip('a', '2026-08-28', 9999, 0), // August is from the old workbook: not counted
  ];
  final submitted = [const Emp201Submitted(month: '2026-09-01', uif: 456.24, sdl: 0, paye: 4577, submittedOn: '2026-10-07')];

  test('a month from the old workbook, a month from the payslips, and what was submitted', () {
    final year = emp201Year(taxYear: 2027, payslips: payslips, history: history, employees: employees, submitted: submitted, includeSdl: false);
    expect(year.length, 12);
    final aug = year[5];
    expect(aug.month, '2026-08-01');
    expect(aug.fromHistory, isTrue);
    expect(aug.uif, closeTo(466.24, 0.001));
    expect(aug.paye, 4577);
    // Linked: the app's name. Anna isn't in the workbook: listed, not counted.
    expect(aug.lines.map((l) => l.name), ['Anna Mokoena', 'Brian', 'Francois Fourie']);
    expect(aug.counted.map((l) => l.name), ['Brian', 'Francois Fourie']);
    expect(aug.salary, 35200);
    final sep = year[6];
    expect(sep.fromHistory, isFalse);
    expect(sep.employees, 2);
    expect(sep.salary, 34700);
    // UIF: employee and employer -- 177.12 x 2 for Francois (ceiling), 2% of 5 100 for Anna.
    expect(sep.uif, closeTo(354.24 + 102, 0.001));
    expect(sep.paye, 4577);
    expect(sep.difference, 0);
    expect(year[7].difference, isNull); // October: nothing submitted yet
    final withSdl = emp201Year(taxYear: 2027, payslips: payslips, history: history, employees: employees, submitted: submitted, includeSdl: true);
    expect(withSdl[6].sdl, closeTo(347, 0.001));
    expect(withSdl[6].difference, closeTo(-347, 0.001));
  });

  test('Excel: the months, per month per employee, per employee', () {
    final year = emp201Year(taxYear: 2027, payslips: payslips, history: history, employees: employees, submitted: submitted, includeSdl: false);
    final x = Excel.decodeBytes(emp201YearXlsx(2027, year));
    expect(x.tables.keys, containsAll(['EMP201 2027', 'Salary', 'UIF', 'SDL', 'PAYE', 'Per month']));
    // Like the salary summary: the groups, everyone with a column per month.
    final salary = x.tables['Salary']!.rows.map((r) => [for (final c in r) c?.value?.toString()]).toList();
    expect(salary.map((r) => r.isEmpty ? null : r.first), containsAll(['On EMP201', 'Not on EMP201 -- no ID/passport', 'Francois Fourie', 'Anna Mokoena']));
    final francois = salary.firstWhere((r) => r.isNotEmpty && r.first == 'Francois Fourie');
    expect(francois.length, 3 + 12 + 1);
    expect(double.parse(francois[3 + 5]!), 29600); // August
    expect(double.parse(francois.last!), 59200); // the year
    final sum = x.tables['EMP201 2027']!;
    final firsts = sum.rows.map((r) => r.isEmpty ? null : r.first?.value.toString()).toList();
    expect(firsts.indexOf('Month') + 1, firsts.indexOf('March 2026'));
    expect(firsts, contains('Total'));
    expect(x.tables['Per month']!.rows.length, 1 + 3 + 2);
  });

  testWidgets('screen shows the months (no database here)', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Emp201YearScreen(payslips: payslips, employees: employees, includeSdl: false)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tax year'), findsOneWidget);
    expect(find.text('Sep 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('EMP201 summary: on EMP201, not on it with an ID, not on it without; only the declared count', () {
    final staff = [
      Employee(id: 'f', firstName: 'Francois', lastName: 'Fourie', farmId: 'fa', idOrPassport: '8001015009087', onEmp201: true),
      Employee(id: 'a', firstName: 'Anna', lastName: 'Mokoena', farmId: 'fa', idOrPassport: 'FN123456', onEmp201: false),
      Employee(id: 'b', firstName: 'Ben', lastName: 'Sithole', farmId: 'fb', onEmp201: false),
    ];
    final slips = [slip('f', '2026-09-30', 29600, 4577), slip('a', '2026-09-12', 2500, 0), slip('a', '2026-09-26', 2600, 0), slip('b', '2026-09-26', 3000, 0)];
    final months = emp201Year(taxYear: 2027, payslips: slips, history: const [], employees: staff, submitted: const [], includeSdl: false);
    final g = emp201YearByEmployee(months);
    expect(g[Emp201Group.declared]!.map((y) => y.key), ['f']);
    expect(g[Emp201Group.notDeclaredWithId]!.single.salary, 5100);
    expect(g[Emp201Group.notDeclaredWithId]!.single.uif, 51); // taken off their pay, not doubled
    expect(g[Emp201Group.notDeclaredNoId]!.single.name, 'Ben Sithole');
    expect(g[Emp201Group.declared]!.single.months['2026-09-01']!.uif, closeTo(354.24, 0.001));
    // The EMP201: Francois only.
    final e = Emp201(DateTime(2026, 9), declaredSlips(slips, staff), includeSdl: false);
    expect(e.employees, 1);
    expect(e.remuneration, 29600);
    final year = emp201Year(taxYear: 2027, payslips: slips, history: const [], employees: staff, submitted: const [], includeSdl: false);
    expect(year[6].employees, 1);
    // Before emp201_declared.sql (no column): everyone counts, as before.
    expect(Employee(id: 'x', firstName: 'X', lastName: '').declared, isTrue);
  });
}
