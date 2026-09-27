import '../../core/formatters.dart';
import 'hours_models.dart';

/// Totals of a set of payslips (a farm, a run, or a whole month).
class PayTotals {
  PayTotals(Iterable<Payslip> slips) {
    for (final p in slips) {
      count++;
      employees.add(p.employeeId);
      hours += p.hoursWorked;
      gross += p.gross;
      paye += p.paye;
      uif += p.uif;
      rent += p.rent;
      loan += p.loan;
      tuckshop += p.tuckshopDeduction;
      nett += p.nett;
    }
  }
  int count = 0;
  final employees = <String>{};
  double hours = 0, gross = 0, paye = 0, uif = 0, rent = 0, loan = 0, tuckshop = 0, nett = 0;
  double get deductions => paye + uif + rent + loan + tuckshop;
}

/// Payslips paid (by paid date) in the calendar month of [month].
List<Payslip> paidInMonth(List<Payslip> all, DateTime month) {
  final prefix = toDateStr(DateTime(month.year, month.month, 1)).substring(0, 7); // yyyy-MM
  return all.where((p) => p.paidDate.startsWith(prefix)).toList();
}

/// EMP201 (monthly employer declaration to SARS) for one calendar month, from
/// what was actually paid that month. ETI isn't worked out by the app (0).
class Emp201 {
  Emp201(this.month, List<Payslip> paidThisMonth, {required this.includeSdl}) {
    final t = PayTotals(paidThisMonth);
    employees = t.employees.length;
    remuneration = t.gross;
    paye = t.paye;
    uifEmployee = t.uif;
  }
  final DateTime month;

  /// Skills Development Levy (1% of remuneration) only applies to employers
  /// whose payroll is over R500 000 a year.
  final bool includeSdl;
  late final int employees;
  late final double remuneration;
  late final double paye;
  late final double uifEmployee;

  double get uifEmployer => uifEmployee;
  double get uif => uifEmployee + uifEmployer;
  double get sdl => includeSdl ? remuneration * 0.01 : 0;
  double get eti => 0;
  double get total => paye + uif + sdl - eti;

  /// SARS period code, e.g. 202609.
  String get period => '${month.year}${month.month.toString().padLeft(2, '0')}';

  /// Due by the 7th of the next month; a 7th on a weekend moves back to the
  /// Friday before. (Public holidays aren't checked.)
  DateTime get dueDate {
    var d = DateTime(month.year, month.month + 1, 7);
    while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }
}

/// One payroll run: the payslips a farm paid together (same paid date and
/// period end).
class PayRun {
  PayRun(this.paidDate, this.periodEnd, this.farmId, this.slips);
  final String paidDate;
  final String periodEnd;
  final String? farmId;
  final List<Payslip> slips;

  String get periodStart => slips.map((p) => p.periodStart).reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
  PayTotals get totals => PayTotals(slips);
}

/// Payslips grouped into runs, newest first.
List<PayRun> groupRuns(List<Payslip> payslips) {
  final runs = <(String, String, String?), List<Payslip>>{};
  for (final p in payslips) {
    runs.putIfAbsent((p.paidDate, p.periodEnd, p.farmId), () => []).add(p);
  }
  final out = [for (final e in runs.entries) PayRun(e.key.$1, e.key.$2, e.key.$3, e.value)];
  out.sort((a, b) => b.paidDate.compareTo(a.paidDate) != 0 ? b.paidDate.compareTo(a.paidDate) : b.periodEnd.compareTo(a.periodEnd));
  return out;
}
