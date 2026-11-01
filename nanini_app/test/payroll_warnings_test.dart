import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/auth/app_user.dart';
import 'package:nanini_app/core/auth/session.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/hours_data.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/hours_repository.dart';
import 'package:nanini_app/features/hours/hours_summary_screen.dart';
import 'package:nanini_app/features/hours/pay_run.dart';
import 'package:nanini_app/features/hours/payroll_warnings.dart';
import 'package:provider/provider.dart';

HoursEntry h(String emp, String date, double hours, {String farm = 'fa'}) => HoursEntry(
      id: '$emp$date$farm',
      employeeId: emp,
      date: date,
      hours: hours,
      rate: 30,
      dailyThreshold: 9,
      otMultiplier: 1.5,
      normalHours: hours,
      otHours: 0,
      gross: hours * 30,
      farmId: farm,
    );

void main() {
  final farm = Farm(id: 'fa', name: 'Farm Limpopodraai - Stockpoort');
  final staff = [
    Employee(id: 'ok', firstName: 'Okay', lastName: '', farmId: 'fa', ratePerHour: 30),
    Employee(id: 'notariff', firstName: 'New', lastName: '', farmId: 'fa'),
    Employee(id: 'atm', firstName: 'Atm', lastName: '', farmId: 'fa', ratePerHour: 30, paymentMethod: PaymentMethod.atm),
    Employee(id: 'long', firstName: 'Long', lastName: '', farmId: 'fa', ratePerHour: 30),
    Employee(id: 'gap', firstName: 'Gap', lastName: '', farmId: 'fa', ratePerHour: 30),
    Employee(id: 'two', firstName: 'Two', lastName: '', farmId: 'fa', ratePerHour: 30),
    Employee(id: 'owe', firstName: 'Owe', lastName: '', farmId: 'fa', ratePerHour: 30, loanDeduction: 500),
  ];
  final work = [
    h('ok', '2026-09-21', 8), h('ok', '2026-09-22', 8),
    h('notariff', '2026-09-21', 8),
    h('atm', '2026-09-21', 8),
    h('long', '2026-09-21', 9), h('long', '2026-09-21', 8, farm: 'fa'), // the same day twice: 17 h
    // Mon 14, then nothing Tue 15 - Fri 18 (4 working days), Sat 19.
    h('gap', '2026-09-14', 8), h('gap', '2026-09-19', 8),
    h('two', '2026-09-22', 8), h('two', '2026-09-22', 4, farm: 'fb'),
    h('owe', '2026-09-21', 8),
  ];
  // The second 'long' entry needs its own id.
  work[5] = HoursEntry(
      id: 'long-2', employeeId: 'long', date: '2026-09-21', hours: 8, rate: 30, dailyThreshold: 9, otMultiplier: 1.5, normalHours: 8, otHours: 0, gross: 240, farmId: 'fa');
  List<PayLine> lines() => buildPayRun(payUpTo: '2026-09-27', employees: staff, entries: work, kgEntries: const [], purchases: const [], payslips: const []);

  test('The warnings before paying: what each one says, and which block', () {
    final w = payrollWarnings(lines(), farmNames: {'fa': 'Limpopodraai', 'fb': 'Haaskraal'});
    String of(String id) => w.where((x) => x.line.employee.id == id).map((x) => '${x.blocking ? '!' : ''}${x.text}').join(' | ');
    expect(of('ok'), '');
    expect(of('notariff'), '!No tariff: 8h would be paid at R0');
    expect(of('atm'), '!Paid by ATM, but no phone number');
    expect(of('long'), contains('Over 12h on'));
    expect(of('long'), contains('(17h)'));
    expect(of('gap'), contains('(4 working days)'));
    expect(of('two'), contains('Hours at two farms on'));
    expect(of('two'), contains('Limpopodraai and Haaskraal'));
    expect(of('owe'), contains('Nett pay below R0'));
  });

  testWidgets('Run payroll: warnings at the top; paying needs "I\'ve checked these"', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    // Only the non-blocking ones: long day and missing days.
    final some = lines().where((l) => ['ok', 'long', 'gap'].contains(l.employee.id)).toList();
    final data = HoursData.forTest(HoursRepository(), employees: staff, entries: work, farms: [farm]);
    final session = Session()..currentUser = AppUser(id: 'u', username: 'admin', displayName: 'Admin', role: 'admin');
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
        home: Scaffold(body: HoursSummaryScreen(data: data, lines: some, scopeBar: const SizedBox(), payUpTo: DateTime(2026, 9, 27), farmName: 'Limpopodraai')),
      ),
    ));
    await tester.tap(find.text('Run payroll -- Limpopodraai'));
    await tester.pumpAndSettle();
    expect(find.text('Check before paying (2)'), findsOneWidget);
    expect(find.textContaining('Over 12h on'), findsOneWidget);
    await tester.tap(find.text('Pay 3'));
    await tester.pumpAndSettle();
    expect(find.textContaining("tick \"I've checked these\""), findsOneWidget);
    // Unticking the workers concerned: no warnings left.
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Long'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Gap'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check before paying'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
