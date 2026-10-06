import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/auth/app_user.dart';
import 'package:nanini_app/core/auth/session.dart';
import 'package:provider/provider.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/hours_data.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/hours_repository.dart';
import 'package:nanini_app/features/hours/hours_summary_screen.dart';
import 'package:nanini_app/features/hours/hours_payslip_preview.dart';
import 'package:nanini_app/features/hours/pay_run.dart';
import 'package:nanini_app/features/hours/payroll_month.dart';
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
    emp('eve', 'Eve', 'fa'), // nothing to pay yet
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

  final extras = [
    PayExtra(id: 'x1', employeeId: 'ben', farmId: 'fa', date: '2026-09-20', description: 'Bonus', amount: 500),
    PayExtra(id: 'x2', employeeId: 'ben', farmId: 'fa', date: '2026-09-21', description: 'Sunday work', hours: 8, rate: 40, amount: 320),
    PayExtra(id: 'x3', employeeId: 'ben', farmId: 'fa', date: '2026-09-01', description: 'Paid before', amount: 999, payslipId: 'old'),
    PayExtra(id: 'x4', employeeId: 'ben', farmId: 'fa', date: '2026-09-30', description: 'Next pay', amount: 50),
  ];

  List<PayLine> run() => buildPayRun(
        payUpTo: '2026-09-27',
        employees: employees,
        entries: entries,
        kgEntries: const [],
        purchases: purchases,
        payslips: payslips,
        extras: extras,
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
    expect(ben.hoursPay, 250); // today's tariff R25, not the R20 it was logged at
    // Extra pay: open ones up to the pay date, not already paid or later.
    expect(ben.extras.map((x) => x.id), ['x1', 'x2']);
    expect(ben.extraPay, 820);
    expect(ben.gross, 250 + 820);
    expect(ben.tariffDiffers, isTrue);

    expect(lines['cara']!.since, isNull); // farm B never paid here
    expect(lines['cara']!.tariff, 0);
    expect(lines['dan']!.hours, 0);
    expect(lines['dan']!.nett, -55);
    expect(lines.containsKey('eve'), isFalse);
  });

  test('grouped per farm in the farms\' order', () {
    final groups = byFarm(run(), [farmA, farmB]);
    expect(groups.map((g) => g.$1?.id), ['fa', 'fb']);
    expect(groups.first.$2.map((l) => l.employee.id), ['anna', 'ben']);
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
    expect(find.text('R370'), findsOneWidget); // Anna: 510 - 40 - 100
    // How the pay is worked out shows only after tapping the name.
    expect(find.text('= '), findsNothing);
    expect(find.text('Tuck shop'), findsNothing);
    await tester.tap(find.text('Anna'));
    await tester.pumpAndSettle();
    expect(find.text('R370'), findsNWidgets(2)); // top right and "= Nett"
    // The sum laid out with signs, one step per line.
    expect(find.text('Gross'), findsWidgets);
    expect(find.text('Tuck shop'), findsWidgets);
    expect(find.text('Loan'), findsWidgets);
    expect(find.text('Nett'), findsWidgets);
    expect(find.text('−'), findsWidgets);
    expect(find.text('='), findsWidgets);
    expect(find.text('-R55'), findsWidgets); // Dan owes more than he earned
    // Each farm is paid on its own.
    expect(find.text('Run payroll -- Limpopodraai'), findsOneWidget);
    expect(find.text('Run payroll -- Haaskraal'), findsOneWidget);
    // A Summary preview above each farm's Run payroll.
    expect(find.widgetWithText(OutlinedButton, 'Summary'), findsNWidgets(2));
    // Calendar just above Summary.
    expect(find.widgetWithText(OutlinedButton, 'Calendar'), findsNWidgets(2));
    expect(tester.getTopLeft(find.widgetWithText(OutlinedButton, 'Calendar').first).dy,
        lessThan(tester.getTopLeft(find.widgetWithText(OutlinedButton, 'Summary').first).dy));
    expect(tester.getTopLeft(find.widgetWithText(OutlinedButton, 'Summary').first).dy,
        lessThan(tester.getTopLeft(find.text('Run payroll -- Limpopodraai')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run payroll: paid by ATM without a phone number -- not run, names shown', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final staff = [
      Employee(id: 'anna', firstName: 'Anna', lastName: '', farmId: 'fa', ratePerHour: 30, paymentMethod: PaymentMethod.atm),
      Employee(id: 'ben', firstName: 'Ben', lastName: '', farmId: 'fa', ratePerHour: 30, paymentMethod: PaymentMethod.atm, phoneNumber: '0721234567'),
      Employee(id: 'gus', firstName: 'Gus', lastName: '', farmId: 'fa', ratePerHour: 30, paymentMethod: PaymentMethod.atm, phoneNumber: '  '),
    ];
    final work = [hrs('anna', '2026-09-20', 8), hrs('ben', '2026-09-20', 8), hrs('gus', '2026-09-20', 8)];
    final data = HoursData.forTest(HoursRepository(), employees: staff, entries: work, farms: [farmA]);
    final lines = buildPayRun(payUpTo: '2026-09-27', employees: staff, entries: work, kgEntries: const [], purchases: const [], payslips: const []);
    final session = Session()..currentUser = AppUser(id: 'u', username: 'admin', displayName: 'Admin', role: 'admin');
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
        home: Scaffold(
          body: HoursSummaryScreen(data: data, lines: lines, scopeBar: const SizedBox(), payUpTo: DateTime(2026, 9, 27), farmName: null),
        ),
      ),
    ));
    await tester.tap(find.text('Run payroll -- Limpopodraai'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay 3'));
    await tester.pumpAndSettle();
    expect(find.text('Payroll NOT run'), findsOneWidget);
    expect(find.textContaining('Paid by ATM, but no phone number'), findsWidgets);
    expect(find.text('• Anna'), findsOneWidget);
    expect(find.text('• Gus'), findsOneWidget); // only spaces: no number
    expect(find.text('• Ben'), findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // Still in Run payroll, nothing paid; Pay can be pressed again.
    expect(find.text('Pay 3'), findsOneWidget);
  });

  testWidgets('Members tab: each member\'s salary info', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final members = [
      Employee(id: 'm1', firstName: 'Dereck', lastName: 'Fourie', farmId: 'fa', isMember: true, monthlySalary: 30000, paymentMethod: PaymentMethod.bank, bankName: 'FNB', bankAccountNo: '62000000000', uifDeduct: false),
      Employee(id: 'm2', firstName: 'Thys', lastName: 'Fourie', farmId: 'fb', isMember: true, onPayroll: false),
    ];
    final data = HoursData.forTest(HoursRepository(), employees: [...employees, ...members], entries: entries, purchases: purchases, payslips: payslips, farms: [farmA, farmB]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HoursSummaryScreen(data: data, lines: const [], scopeBar: const SizedBox(), payUpTo: DateTime(2026, 9, 27), farmName: 'Members', memberInfo: members),
      ),
    ));
    expect(find.text('Dereck Fourie'), findsOneWidget);
    expect(find.text('Monthly salary'), findsOneWidget);
    expect(find.text('R30 000'), findsOneWidget);
    expect(find.text('PAYE'), findsOneWidget);
    expect(find.text('UIF'), findsNothing); // chosen: no UIF
    expect(find.text('Limpopodraai · Paid by bank transfer (FNB 62000000000)'), findsOneWidget);
    // Members are all paid by bank transfer: the account can be added.
    expect(find.text('Haaskraal · not on payroll · Paid by bank transfer'), findsOneWidget);
    expect(find.text('Bank account'), findsOneWidget);
    expect(find.text('Add bank account'), findsOneWidget);
    expect(find.text('No hours, picking or tuck shop debt since the last pay.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('pay-out split: bank, cash and ATM add up to the nett, in whole rands', () {
    PayLine line(String id, PaymentMethod m, double hours) => PayLine(
          employee: Employee(id: id, firstName: id, lastName: '', farmId: 'fa', ratePerHour: 30.15, paymentMethod: m),
          since: null,
          entries: [hrs(id, '2026-09-20', hours, rate: 30.15)],
          kgEntries: const [],
          purchases: const [],
        );
    final lines = [line('a', PaymentMethod.bank, 10), line('b', PaymentMethod.cash, 10), line('c', PaymentMethod.atm, 10), line('d', PaymentMethod.cash, 3)];
    final split = payoutSplit(lines);
    final nett = lines.fold<double>(0, (s, l) => s + l.nett);
    expect(split.values.fold<double>(0, (a, b) => a + b), nett.roundToDouble());
    expect(split.keys, containsAll(PaymentMethod.values));
  });

  group('Month and EMP201', () {
    Payslip slip(String emp, String farm, String paid, {double gross = 1000, double paye = 0, double uif = 10, double tuck = 50}) => Payslip(
          id: '$emp$paid',
          employeeId: emp,
          farmId: farm,
          periodStart: '2026-09-01',
          periodEnd: paid,
          paidDate: paid,
          gross: gross,
          hoursWorked: 40,
          paye: paye,
          uif: uif,
          rent: 0,
          loan: 0,
          tuckshopDeduction: tuck,
          nett: gross - paye - uif - tuck,
          createdAt: DateTime(2026),
        );
    final slips = [
      slip('anna', 'fa', '2026-09-12'),
      slip('ben', 'fa', '2026-09-12'),
      slip('cara', 'fb', '2026-09-26', gross: 2000, paye: 100, uif: 20),
      slip('anna', 'fa', '2026-09-26'),
      slip('anna', 'fa', '2026-10-03'), // next month
    ];

    test('month totals for all farms, by paid date', () {
      final sept = paidInMonth(slips, DateTime(2026, 9));
      expect(sept.length, 4);
      final t = PayTotals(sept);
      expect(t.employees.length, 3);
      expect(t.gross, 5000);
      expect(t.nett, 5000 - 100 - 50 - 200);
    });

    test('members (paid in their own run) are in the month totals and EMP201', () {
      // Hidden everywhere else, but legally part of the payroll: SARS gets them.
      final withMember = [...slips, slip('dereck', 'fa', '2026-09-26', gross: 30000, paye: 4000, uif: 0, tuck: 0)];
      final t = PayTotals(paidInMonth(withMember, DateTime(2026, 9)));
      expect(t.employees, contains('dereck'));
      expect(t.gross, 35000);
      final e = Emp201(DateTime(2026, 9), emp201Slips(withMember, DateTime(2026, 9)), includeSdl: false);
      expect(e.employees, 4);
      expect(e.remuneration, 36000); // with the run paid on 3 Oct (September's EMP201)
      expect(e.paye, 4100);
    });

    test('EMP201: PAYE, UIF both sides, SDL only when on, due by the 7th', () {
      final e = Emp201(DateTime(2026, 9), paidInMonth(slips, DateTime(2026, 9)), includeSdl: false);
      expect(e.period, '202609');
      expect(e.paye, 100);
      expect(e.uif, 100); // 50 employees + 50 employer
      expect(e.sdl, 0);
      expect(e.total, 200);
      expect(e.dueDate, DateTime(2026, 10, 7)); // a Wednesday
      expect(Emp201(DateTime(2026, 9), paidInMonth(slips, DateTime(2026, 9)), includeSdl: true).sdl, 50);
      // 7 Nov 2026 is a Saturday: due the Friday before.
      expect(Emp201(DateTime(2026, 10), const [], includeSdl: false).dueDate, DateTime(2026, 11, 6));
      // December rolls into January.
      expect(Emp201(DateTime(2026, 12), const [], includeSdl: false).period, '202612');
      expect(Emp201(DateTime(2026, 12), const [], includeSdl: false).dueDate.month, 1);
    });

    test('EMP201: runs paid up to 3 days after the month are in it, and not in the next one', () {
      // 3 Oct is September's; 4 Oct would be October's.
      expect(emp201Slips(slips, DateTime(2026, 9)).length, 5);
      expect(emp201Slips(slips, DateTime(2026, 10)), isEmpty);
      final late = [...slips, slip('ben', 'fa', '2026-10-04')];
      expect(emp201Slips(late, DateTime(2026, 10)).single.paidDate, '2026-10-04');
      // Each payslip in exactly one EMP201.
      for (final p in late) {
        expect([for (var m = 8; m <= 11; m++) emp201Slips([p], DateTime(2026, m)).length].fold<int>(0, (a, b) => a + b), 1);
      }
      // Year end: paid 2 Jan is December's.
      expect(emp201MonthOf('2027-01-02'), DateTime(2026, 12));
      final e = Emp201(DateTime(2026, 9), emp201Slips(slips, DateTime(2026, 9)), includeSdl: false);
      expect((e.paidFrom, e.paidTo), ('2026-09-04', '2026-10-03'));
      expect(e.remuneration, PayTotals(slips).gross); // the 3 Oct run's pay too
      expect(e.remuneration, greaterThan(PayTotals(paidInMonth(slips, DateTime(2026, 9))).gross));
    });

    test('runs are per farm', () {
      final runs = groupRuns(slips);
      expect(runs.first.paidDate, '2026-10-03');
      final sept12 = runs.where((r) => r.paidDate == '2026-09-12').toList();
      expect(sept12.length, 1);
      expect(sept12.single.slips.length, 2);
      final sept26 = runs.where((r) => r.paidDate == '2026-09-26').map((r) => r.farmId).toSet();
      expect(sept26, {'fa', 'fb'}); // two farms paid the same day: two runs
    });

    testWidgets('run and month PDFs build', (tester) async {
      await tester.runAsync(() async {
        final withExtra = Payslip(
          id: 'e',
          employeeId: 'ben',
          periodStart: '2026-09-01',
          periodEnd: '2026-09-12',
          paidDate: '2026-09-12',
          gross: 1320,
          extraPay: 320,
          extras: [
            {'description': 'Sunday work', 'hours': 8, 'rate': 40, 'amount': 320},
          ],
          paye: 0,
          uif: 13,
          rent: 0,
          loan: 0,
          tuckshopDeduction: 0,
          nett: 1307,
          createdAt: DateTime(2026),
        );
        expect(withExtra.toInsert()['extra_pay'], 320);
        expect(slips[0].toInsert().containsKey('extra_pay'), isFalse); // none: column not needed
        final run = await buildRunPdf(farmName: 'Limpopodraai', slips: [(slips[0], employees[0]), (withExtra, employees[1])]);
        expect((await run.save()).length, greaterThan(1000));
        final month = await buildMonthPdf(
          monthLabel: 'September 2026',
          farmRows: [('Limpopodraai', List.filled(9, '1'))],
          totalRow: List.filled(9, '1'),
          emp201: [('PAYE', 'R100')],
          dueLine: 'Submit and pay by Wednesday 7 October 2026',
        );
        expect((await month.save()).length, greaterThan(1000));
      });
    });
  });

  test('hours per farm: by the farm worked on, not the pay farm', () {
    HoursEntry e(String emp, String date, double h, {String? farm}) => HoursEntry(
          id: '$emp$date',
          employeeId: emp,
          date: date,
          hours: h,
          rate: 20,
          dailyThreshold: 9,
          otMultiplier: 1.5,
          normalHours: h,
          otHours: 0,
          gross: h * 20,
          farmId: farm,
        );
    final byFarm = hoursByFarm([
      e('anna', '2026-09-10', 8), // old entry, no farm: Anna's own (fa)
      e('anna', '2026-09-11', 8, farm: 'fb'), // Anna helped at Haaskraal
      e('cara', '2026-09-11', 6, farm: 'fb'),
      e('cara', '2026-10-01', 9, farm: 'fb'), // next month
    ], employees, DateTime(2026, 9));
    expect(byFarm['fa']!.hours, 8);
    expect(byFarm['fb']!.hours, 14);
    expect(byFarm['fb']!.visitors, 8); // Anna is paid at Limpopodraai
    expect(byFarm['fb']!.workers, {'anna', 'cara'});
    expect(byFarm['fb']!.cost, 280);
  });
}
