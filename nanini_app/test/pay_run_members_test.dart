import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/pay_run.dart';

void main() {
  HoursEntry h(String emp, String date, double hours) => HoursEntry(
      id: '$emp$date', employeeId: emp, date: date, hours: hours, rate: 30, dailyThreshold: 9, otMultiplier: 1.5, normalHours: hours, otHours: 0, gross: hours * 30);
  Payslip slip(String emp, String farm, String end) => Payslip(
      id: 's$emp$end', employeeId: emp, farmId: farm, periodStart: '2026-10-01', periodEnd: end, paidDate: end,
      gross: 1000, paye: 0, uif: 0, rent: 0, loan: 0, tuckshopDeduction: 0, nett: 1000, createdAt: DateTime(2026, 10, 30));

  final worker = Employee(id: 'w', firstName: 'Never', lastName: 'Paid', farmId: 'limpo', ratePerHour: 30);
  final paidWorker = Employee(id: 'p', firstName: 'Paid', lastName: 'Before', farmId: 'limpo', ratePerHour: 30);
  final member = Employee(id: 'm', firstName: 'Member', lastName: 'Salary', farmId: 'limpo', isMember: true, monthlySalary: 27000);

  test("The members' salary run (paid at the farm, up to 30 Oct) is not the farm's last pay run", () {
    final lines = buildPayRun(
      payUpTo: '2026-10-30',
      employees: [worker, paidWorker, member],
      entries: [h('w', '2026-10-10', 9), h('w', '2026-10-20', 9), h('p', '2026-10-01', 9), h('p', '2026-10-20', 9)],
      kgEntries: const [],
      purchases: const [],
      payslips: [slip('p', 'limpo', '2026-10-02'), slip('m', 'limpo', '2026-10-30')],
    );
    final never = lines.firstWhere((l) => l.employee.id == 'w');
    // Never paid: from the day after the farm's workers' last run (2 Oct), not 30 Oct.
    expect(never.hours, 18);
    expect(lines.firstWhere((l) => l.employee.id == 'p').hours, 9);
    // Timesheets and fridge sheets: from the day after the workers' run too.
    expect(farmPayEnds([slip('p', 'limpo', '2026-10-02'), slip('m', 'limpo', '2026-10-30')], 'limpo', [worker, paidWorker, member]), ['2026-10-02']);
  });
}
