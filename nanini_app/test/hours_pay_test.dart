import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/hours_data.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/hours_repository.dart';
import 'package:nanini_app/features/hours/hours_summary_screen.dart';
import 'package:nanini_app/features/hours/hours_work_screen.dart';
import 'package:nanini_app/features/hours/pay_run.dart';
import 'package:nanini_app/features/tuckshop/tuckshop_models.dart';

final farmA = Farm(id: 'fa', name: 'Farm Limpopodraai - Stockpoort');
final farmB = Farm(id: 'fb', name: 'Farm Haaskraal - Swartwater');

Employee emp(String id, String name, String farm, {double? rate = 30, double? loan, String? idNo}) =>
    Employee(id: id, firstName: name, lastName: '', farmId: farm, ratePerHour: rate, loanDeduction: loan, idOrPassport: idNo);

HoursEntry hrs(String emp, String date, double h, {double rate = 30, String? group}) => HoursEntry(
      id: '$emp$date',
      employeeId: emp,
      date: date,
      hours: h,
      rate: rate,
      dailyThreshold: 9,
      otMultiplier: 1.5,
      normalHours: h,
      otHours: 0,
      gross: h * rate,
      groupName: group,
    );

Payslip paid(String emp, String farm, String end) => Payslip(
      id: 'p$emp$end',
      employeeId: emp,
      farmId: farm,
      periodStart: '2026-08-01',
      periodEnd: end,
      paidDate: end,
      gross: 0,
      paye: 0,
      uif: 0,
      rent: 0,
      loan: 0,
      tuckshopDeduction: 0,
      nett: 0,
      createdAt: DateTime(2026),
    );

TuckshopPurchase buy(String emp, String date, double r, {String? payslip}) =>
    TuckshopPurchase(id: '$emp$date$r', employeeId: emp, revenue: r, cogs: 0, date: date, payslipId: payslip);

void main() {
  final employees = [
    emp('anna', 'Anna', 'fa', loan: 100),
    emp('ben', 'Ben', 'fa', rate: 25),
    emp('cara', 'Cara', 'fb', rate: null),
    emp('dan', 'Dan', 'fb'),
  ];
  final entries = [
    hrs('anna', '2026-09-10', 8), // paid already (Anna paid to 09-15)
    hrs('anna', '2026-09-16', 9),
    hrs('anna', '2026-09-17', 8, group: 'Pickers'),
    hrs('anna', '2026-09-30', 8), // after the pay-up-to date
    hrs('ben', '2026-09-14', 5), // Ben never paid: falls back to farm A's last pay (09-15)
    hrs('ben', '2026-09-20', 10, rate: 20), // logged at an old rate
    hrs('cara', '2026-09-20', 6),
  ];
  final payslips = [paid('anna', 'fa', '2026-09-15')];
  final purchases = [
    buy('anna', '2026-09-01', 40), // old but never deducted: still owed
    buy('anna', '2026-09-02', 99, payslip: 'x'), // already deducted
    buy('dan', '2026-09-18', 55), // debt, no hours
  ];

  List<PayLine> run() => buildPayRun(
        payUpTo: '2026-09-27',
        employees: employees,
        entries: entries,
        kgEntries: const [],
        purchases: purchases,
        payslips: payslips,
      );

  test('since last pay per worker, farm fallback, unpaid tuck shop debt', () {
    final lines = {for (final l in run()) l.employee.id: l};
    expect(lines.keys, containsAll(['anna', 'ben', 'cara', 'dan']));

    final anna = lines['anna']!;
    expect(anna.since, '2026-09-15');
    expect(anna.hours, 17); // 16th + 17th; not the 10th (paid) or the 30th (after)
    expect(anna.gross, 17 * 30);
    expect(anna.tuckshop, 40);
    expect(anna.loan, 100);
    expect(anna.nett, 17 * 30 - 40 - 100);
    expect(anna.periodStart('2026-09-27'), '2026-09-16');

    final ben = lines['ben']!;
    expect(ben.since, '2026-09-15'); // farm A's last pay
    expect(ben.hours, 10);
    expect(ben.gross, 250); // today's tariff R25, not the R20 it was logged at
    expect(ben.tariffDiffers, isTrue);

    expect(lines['cara']!.since, isNull); // farm B never paid here
    expect(lines['cara']!.tariff, 0);
    expect(lines['dan']!.hours, 0);
    expect(lines['dan']!.nett, -55);
  });

  test('grouped per farm in the farms\' order', () {
    final groups = byFarm(run(), [farmA, farmB]);
    expect(groups.map((g) => g.$1?.id), ['fa', 'fb']);
    expect(groups.first.$2.map((l) => l.employee.id), ['anna', 'ben']);
  });

  Future<HoursData> pumpWork(WidgetTester tester, WorkStep step) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final data = HoursData.forTest(HoursRepository(), employees: employees, entries: entries, purchases: purchases, payslips: payslips, farms: [farmA, farmB]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HoursWorkScreen(data: data, lines: run(), scopeBar: const SizedBox(), step: step, onStep: (_) {}, onDone: () {}),
      ),
    ));
    return data;
  }

  testWidgets('Work 1: hours per worker and per farm, no groups', (tester) async {
    await pumpWork(tester, WorkStep.hours);
    expect(find.text('Limpopodraai'), findsOneWidget);
    expect(find.text('Haaskraal'), findsOneWidget);
    expect(find.text('2 workers · 27h'), findsOneWidget); // Anna 17 + Ben 10
    expect(find.text('17h'), findsOneWidget);
    expect(find.textContaining('Pickers'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Work 2: tariffs, missing one flagged', (tester) async {
    await pumpWork(tester, WorkStep.tariff);
    expect(find.text('1 without tariff'), findsOneWidget);
    expect(find.text('6h -- no tariff set'), findsOneWidget);
    expect(find.textContaining('another rate'), findsOneWidget);
  });

  testWidgets('Work 3: tuck shop debt and loan', (tester) async {
    await pumpWork(tester, WorkStep.deductions);
    expect(find.text('Tuck shop debt: R 40'), findsOneWidget);
    expect(find.text('Loan repayment: R 100'), findsOneWidget);
    expect(find.text('Tuck shop debt: R 55'), findsOneWidget);
  });

  testWidgets('Summary: nett per worker and farm, run payroll button', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final data = HoursData.forTest(HoursRepository(), employees: employees, entries: entries, purchases: purchases, payslips: payslips, farms: [farmA, farmB]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HoursSummaryScreen(data: data, lines: run(), scopeBar: const SizedBox(), payUpTo: DateTime(2026, 9, 27), farmName: null),
      ),
    ));
    expect(find.text('R 370'), findsOneWidget); // Anna: 510 - 40 - 100
    expect(find.text('-R 55'), findsWidgets); // Dan owes more than he earned
    expect(find.text('Run payroll'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
