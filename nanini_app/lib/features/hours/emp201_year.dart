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

/// One employee in one month: salary, UIF, SDL, PAYE -- all of it, and the
/// part on the EMP201 (declared; UIF then the employee's and the employer's
/// together). Pay not declared (not on EMP201, or before the day they were
/// registered) shows the UIF taken off their pay.
class Emp201EmployeeMonth {
  Emp201EmployeeMonth(this.key, this.name, this.month, {this.employee});
  final String key; // employee id, else the name
  final String name;
  final String month;
  final Employee? employee;
  double salary = 0, uif = 0, sdl = 0, paye = 0;
  double dSalary = 0, dUif = 0, dSdl = 0, dPaye = 0;
  bool counted = false;

  void add({required double salary, required double uif, required double sdl, required double paye, required bool declared}) {
    this.salary += salary;
    this.uif += uif;
    this.sdl += sdl;
    this.paye += paye;
    if (!declared) return;
    counted = true;
    dSalary += salary;
    dUif += uif;
    dSdl += sdl;
    dPaye += paye;
  }

  /// UIF or PAYE taken off pay that isn't declared.
  bool get withheldNotDeclared => uif - dUif > 0.004 || paye - dPaye > 0.004;
}

/// A month of the tax year: the EMP201 worked out (only the lines on it),
/// and what was submitted.
class Emp201YearMonth {
  Emp201YearMonth(this.month, this.lines, {required this.fromHistory, this.submitted});
  final String month; // yyyy-MM-01

  /// Everyone paid that month, on the EMP201 or not.
  final List<Emp201EmployeeMonth> lines;

  /// From the old workbook, not the app's payslips.
  final bool fromHistory;
  final Emp201Submitted? submitted;

  Iterable<Emp201EmployeeMonth> get counted => lines.where((l) => l.counted);
  double _sum(double Function(Emp201EmployeeMonth) f) => lines.fold(0.0, (s, l) => s + f(l));
  double get salary => _sum((l) => l.dSalary);
  double get uif => _sum((l) => l.dUif);
  double get sdl => _sum((l) => l.dSdl);
  double get paye => _sum((l) => l.dPaye);
  double get total => uif + sdl + paye;
  int get employees => counted.where((l) => l.dSalary > 0).length;

  /// Submitted less worked out; null until the submission is entered.
  double? get difference => submitted == null ? null : _r(submitted!.total - total);
}

double _r(double v) => (v * 100).roundToDouble() / 100;

/// The tax year a month falls in, by the year it ends: March 2026 to
/// February 2027 is the 2027 tax year.
int taxYearOf(DateTime d) => d.month >= 3 ? d.year + 1 : d.year;

/// The 12 months (yyyy-MM-01) of the [taxYear], March to February.
List<String> taxYearMonths(int taxYear) => [for (var i = 0; i < 12; i++) toDateStr(DateTime(taxYear - 1, 3 + i))];

/// The EMP201s of a tax year, and everyone paid in it. A month with figures
/// from the old workbook takes them as they were declared; the rest of that
/// month's payslips (people not in the workbook) are listed but not
/// counted. Other months come from the payslips in that month's EMP201 (see
/// [emp201Slips]): those on EMP201 counted -- UIF the employee's and the
/// employer's, SDL 1% of the pay when [includeSdl].
List<Emp201YearMonth> emp201Year({
  required int taxYear,
  required List<Payslip> payslips,
  required List<Emp201HistoryLine> history,
  required List<Employee> employees,
  required List<Emp201Submitted> submitted,
  required bool includeSdl,
}) {
  final byId = {for (final e in employees) e.id: e};
  return [
    for (final m in taxYearMonths(taxYear))
      () {
        final hist = history.where((h) => h.month == m).toList();
        final byKey = <String, Emp201EmployeeMonth>{};
        Emp201EmployeeMonth line(String? id, String name) {
          final key = id ?? name;
          final e = id == null ? null : byId[id];
          return byKey.putIfAbsent(key, () => Emp201EmployeeMonth(key, e?.displayName ?? name, m, employee: e));
        }

        for (final h in hist) {
          line(h.employeeId, h.name).add(salary: h.salary, uif: h.uif, sdl: h.sdl, paye: h.paye, declared: true);
        }
        final inHistory = {for (final h in hist) ?h.employeeId};
        for (final p in emp201Slips(payslips, DateTime.parse(m))) {
          // Already in the workbook's figures for the month.
          if (inHistory.contains(p.employeeId)) continue;
          // On the EMP201 from the day they were registered (e.g. for UIF).
          final declared = hist.isEmpty && (byId[p.employeeId]?.declaredOn(p.paidDate) ?? true);
          line(p.employeeId, 'Unknown').add(
            salary: p.gross,
            uif: declared ? p.uif * 2 : p.uif,
            sdl: declared && includeSdl ? p.gross * 0.01 : 0,
            paye: p.paye,
            declared: declared,
          );
        }
        final lines = byKey.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return Emp201YearMonth(m, lines, fromHistory: hist.isNotEmpty, submitted: submitted.where((s) => s.month == m).firstOrNull);
      }(),
  ];
}

/// One employee's tax year: each month's figures, and their group (on
/// EMP201, or not with/without an ID/passport -- as they are now).
class Emp201EmployeeYear {
  Emp201EmployeeYear(this.key, this.name, this.employee, this.group);
  final String key;
  final String name;
  final Employee? employee;
  final Emp201Group group;
  final months = <String, Emp201EmployeeMonth>{};

  double _sum(double Function(Emp201EmployeeMonth) f) => months.values.fold(0.0, (s, l) => s + f(l));
  double get salary => _sum((l) => l.salary);
  double get uif => _sum((l) => l.uif);
  double get sdl => _sum((l) => l.sdl);
  double get paye => _sum((l) => l.paye);
}

/// Everyone paid in the tax year [months], per group, A to Z -- every group
/// listed, even when empty. Someone only in the old workbook is on EMP201.
Map<Emp201Group, List<Emp201EmployeeYear>> emp201YearByEmployee(List<Emp201YearMonth> months) {
  final byKey = <String, Emp201EmployeeYear>{};
  for (final m in months) {
    for (final l in m.lines) {
      byKey.putIfAbsent(l.key, () => Emp201EmployeeYear(l.key, l.name, l.employee, emp201GroupOf(l.employee))).months[m.month] = l;
    }
  }
  final out = {for (final g in Emp201Group.values) g: <Emp201EmployeeYear>[]};
  for (final y in byKey.values) {
    out[y.group]!.add(y);
  }
  for (final g in out.values) {
    g.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
  return out;
}
