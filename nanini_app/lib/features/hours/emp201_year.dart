import '../../core/formatters.dart';
import '../employees/employees_models.dart';
import 'hours_models.dart';
import 'payroll_month.dart';

/// One employee's EMP201 figures for a month from before the app's payroll
/// (loaded from the old salary summary workbook, emp201_history.sql).
/// [uif] is the employee's and the employer's together.
class Emp201HistoryLine {
  const Emp201HistoryLine({required this.month, required this.name, this.employeeId, required this.salary, required this.uif, required this.sdl, required this.paye});
  final String month; // yyyy-MM-01
  final String name;
  final String? employeeId;
  final double salary;
  final double uif;
  final double sdl;
  final double paye;

  factory Emp201HistoryLine.fromJson(Map<String, dynamic> j) => Emp201HistoryLine(
        month: (j['month'] as String).substring(0, 10),
        name: j['employee_name'] as String,
        employeeId: j['employee_id'] as String?,
        salary: (j['salary'] as num).toDouble(),
        uif: (j['uif'] as num).toDouble(),
        sdl: (j['sdl'] as num?)?.toDouble() ?? 0,
        paye: (j['paye'] as num).toDouble(),
      );
}

/// What was actually submitted to SARS on eFiling for a month ("Ingedien").
class Emp201Submitted {
  const Emp201Submitted({required this.month, required this.uif, required this.sdl, required this.paye, this.submittedOn, this.reference});
  final String month; // yyyy-MM-01
  final double uif;
  final double sdl;
  final double paye;
  final String? submittedOn;
  final String? reference;
  double get total => uif + sdl + paye;

  factory Emp201Submitted.fromJson(Map<String, dynamic> j) => Emp201Submitted(
        month: (j['month'] as String).substring(0, 10),
        uif: (j['uif'] as num?)?.toDouble() ?? 0,
        sdl: (j['sdl'] as num?)?.toDouble() ?? 0,
        paye: (j['paye'] as num?)?.toDouble() ?? 0,
        submittedOn: j['submitted_on'] as String?,
        reference: j['reference'] as String?,
      );
}

/// One employee in one month: salary, UIF (employee + employer), SDL, PAYE.
class Emp201EmployeeMonth {
  Emp201EmployeeMonth(this.key, this.name, this.month);
  final String key; // employee id, else the name
  final String name;
  final String month;
  double salary = 0, uif = 0, sdl = 0, paye = 0;
}

/// A month of the tax year: the EMP201 worked out, and what was submitted.
class Emp201YearMonth {
  Emp201YearMonth(this.month, this.lines, {required this.fromHistory, this.submitted});
  final String month; // yyyy-MM-01
  final List<Emp201EmployeeMonth> lines;

  /// From the old workbook, not the app's payslips.
  final bool fromHistory;
  final Emp201Submitted? submitted;

  double _sum(double Function(Emp201EmployeeMonth) f) => lines.fold(0.0, (s, l) => s + f(l));
  double get salary => _sum((l) => l.salary);
  double get uif => _sum((l) => l.uif);
  double get sdl => _sum((l) => l.sdl);
  double get paye => _sum((l) => l.paye);
  double get total => uif + sdl + paye;
  int get employees => lines.where((l) => l.salary > 0).length;

  /// Submitted less worked out; null until the submission is entered.
  double? get difference => submitted == null ? null : _r(submitted!.total - total);
}

double _r(double v) => (v * 100).roundToDouble() / 100;

/// The tax year a month falls in, by the year it ends: March 2026 to
/// February 2027 is the 2027 tax year.
int taxYearOf(DateTime d) => d.month >= 3 ? d.year + 1 : d.year;

/// The 12 months (yyyy-MM-01) of the [taxYear], March to February.
List<String> taxYearMonths(int taxYear) => [for (var i = 0; i < 12; i++) toDateStr(DateTime(taxYear - 1, 3 + i))];

/// The EMP201s of a tax year: each month from the old workbook where it has
/// figures, else from the payslips in that month's EMP201 (see
/// [emp201Slips]) -- UIF is the employee's and the employer's, SDL 1% of
/// the pay when [includeSdl].
List<Emp201YearMonth> emp201Year({
  required int taxYear,
  required List<Payslip> payslips,
  required List<Emp201HistoryLine> history,
  required List<Employee> employees,
  required List<Emp201Submitted> submitted,
  required bool includeSdl,
}) {
  final names = {for (final e in employees) e.id: e.displayName};
  return [
    for (final m in taxYearMonths(taxYear))
      () {
        final hist = history.where((h) => h.month == m).toList();
        final byKey = <String, Emp201EmployeeMonth>{};
        Emp201EmployeeMonth line(String? id, String name) {
          final key = id ?? name;
          return byKey.putIfAbsent(key, () => Emp201EmployeeMonth(key, id == null ? name : names[id] ?? name, m));
        }

        if (hist.isNotEmpty) {
          for (final h in hist) {
            line(h.employeeId, h.name)
              ..salary += h.salary
              ..uif += h.uif
              ..sdl += h.sdl
              ..paye += h.paye;
          }
        } else {
          // Only those declared to SARS.
          for (final p in declaredSlips(emp201Slips(payslips, DateTime.parse(m)), employees)) {
            line(p.employeeId, 'Unknown')
              ..salary += p.gross
              ..uif += p.uif * 2
              ..sdl += includeSdl ? p.gross * 0.01 : 0
              ..paye += p.paye;
          }
        }
        final lines = byKey.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return Emp201YearMonth(m, lines, fromHistory: hist.isNotEmpty, submitted: submitted.where((s) => s.month == m).firstOrNull);
      }(),
  ];
}
