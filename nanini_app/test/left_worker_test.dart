import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/pay_run.dart';
import 'package:nanini_app/features/hours/timesheet_pdf.dart';

// Made-up workers and figures.
final haas = Farm(id: 'fh', name: 'Farm Haaskraal - Swartwater');
Employee w(String id, {String? left}) => Employee(id: id, firstName: id, lastName: '', farmId: haas.id, ratePerHour: 20, leftOn: left);
Payslip slip(String emp, String end) => Payslip(
    id: 's$emp', employeeId: emp, farmId: haas.id, periodStart: '2026-11-01', periodEnd: end, paidDate: end,
    gross: 100, paye: 0, uif: 0, rent: 0, loan: 0, tuckshopDeduction: 0, nett: 100, createdAt: DateTime(2026));

void main() {
  test('A worker who left during the month: not on a sheet printed after, nor listed once paid out', () {
    final staff = [w('anna'), w('peter', left: '2026-11-09')];
    // Printed on 1 Nov: still on it (worked to the 9th); printed on the 24th: not.
    expect(timesheetsFor(haas, staff, const [], DateTime(2026, 11), today: DateTime(2026, 11, 1)).single.workers.map((e) => e.id), ['anna', 'peter']);
    expect(timesheetsFor(haas, staff, const [], DateTime(2026, 11), today: DateTime(2026, 11, 24)).single.workers.map((e) => e.id), ['anna']);
    // The payslip check lists every worker -- not Peter, paid up to the day he left.
    List<PayLine> run(List<Payslip> slips) => buildPayRun(
        payUpTo: '2026-11-27', employees: staff, entries: const [], kgEntries: const [], purchases: const [], payslips: slips, includeAll: true);
    expect(run([slip('peter', '2026-11-09')]).map((l) => l.employee.id), ['anna']);
    // Not paid out yet: still listed (his last pay to come).
    expect(run(const []).map((l) => l.employee.id), ['anna', 'peter']);
  });
}
