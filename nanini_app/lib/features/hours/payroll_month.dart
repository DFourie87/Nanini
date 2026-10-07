import '../../core/formatters.dart';
import '../employees/employees_models.dart';
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

/// Days into the next month a payroll run still counts for the month before
/// in its EMP201 (a run paid on 2 October is September's).
const emp201GraceDays = 3;

/// The EMP201 a payslip goes in: the month of its paid date, less
/// [emp201GraceDays] -- so each payslip is in exactly one EMP201.
DateTime emp201MonthOf(String paidDate) {
  final d = DateTime.parse(paidDate).subtract(const Duration(days: emp201GraceDays));
  return DateTime(d.year, d.month);
}

/// The payslips in [month]'s EMP201: paid from the 4th of that month up to
/// the 3rd of the next.
List<Payslip> emp201Slips(List<Payslip> all, DateTime month) =>
    all.where((p) => p.paidDate.isNotEmpty && emp201MonthOf(p.paidDate) == DateTime(month.year, month.month)).toList();

/// EMP201 (monthly employer declaration to SARS) for one month, from the
/// payslips paid in it -- including runs paid up to 3 days after it ends
/// (see [emp201Slips]). ETI isn't worked out by the app (0).
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

  /// Paid from (the 4th of the month) to (the 3rd of the next), yyyy-MM-dd.
  String get paidFrom => toDateStr(DateTime(month.year, month.month, emp201GraceDays + 1));
  String get paidTo => toDateStr(DateTime(month.year, month.month + 1, emp201GraceDays));

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

/// Payslips grouped into runs, newest first. [groupOf] (default: the
/// payslip's farm) says which run a payslip belongs to -- e.g. the members'
/// own run.
List<PayRun> groupRuns(List<Payslip> payslips, {String? Function(Payslip)? groupOf}) {
  final runs = <(String, String, String?), List<Payslip>>{};
  for (final p in payslips) {
    runs.putIfAbsent((p.paidDate, p.periodEnd, groupOf == null ? p.farmId : groupOf(p)), () => []).add(p);
  }
  final out = [for (final e in runs.entries) PayRun(e.key.$1, e.key.$2, e.key.$3, e.value)];
  out.sort((a, b) => b.paidDate.compareTo(a.paidDate) != 0 ? b.paidDate.compareTo(a.paidDate) : b.periodEnd.compareTo(a.periodEnd));
  return out;
}

/// One farm's hours in a month, by the farm the work was done on.
class FarmHours {
  double hours = 0;
  double cost = 0;
  final workers = <String>{};

  /// Hours by workers who are paid at another farm.
  double visitors = 0;
}

/// Hours worked per farm in the month of [month] (by date worked). Each
/// entry counts at the farm it was worked on, or -- entries from before
/// that was recorded -- at the worker's own farm.
Map<String?, FarmHours> hoursByFarm(List<HoursEntry> entries, List<Employee> employees, DateTime month) {
  final prefix = toDateStr(DateTime(month.year, month.month, 1)).substring(0, 7);
  final payFarm = {for (final e in employees) e.id: e.farmId};
  final out = <String?, FarmHours>{};
  for (final e in entries.where((e) => e.date.startsWith(prefix))) {
    final own = payFarm[e.employeeId];
    final worked = e.farmId ?? own;
    final f = out.putIfAbsent(worked, FarmHours.new)
      ..hours += e.hours
      ..cost += e.gross
      ..workers.add(e.employeeId);
    if (own != worked) f.visitors += e.hours;
  }
  return out;
}

/// The three groups of the EMP201 summary: who is declared to SARS, and who
/// isn't -- with an ID/passport on file, or without.
enum Emp201Group {
  declared('On EMP201'),
  notDeclaredWithId('Not on EMP201 -- ID/passport on file'),
  notDeclaredNoId('Not on EMP201 -- no ID/passport');

  const Emp201Group(this.label);
  final String label;
}

Emp201Group emp201GroupOf(Employee? e) => e == null || e.declared
    ? Emp201Group.declared
    : e.hasId
        ? Emp201Group.notDeclaredWithId
        : Emp201Group.notDeclaredNoId;

/// One employee's pay in a month's EMP201 summary (all their payslips).
class Emp201SummaryLine {
  Emp201SummaryLine(this.employeeId, this.employee);
  final String employeeId;
  final Employee? employee;
  double gross = 0, uif = 0, paye = 0;
  int payslips = 0;
  String get name => employee?.displayName ?? 'Unknown';
}

/// [slips] (a month's EMP201 payslips, all farms) per employee, in the
/// three groups -- every group listed, even when empty.
Map<Emp201Group, List<Emp201SummaryLine>> emp201Summary(List<Payslip> slips, List<Employee> employees) {
  final byId = {for (final e in employees) e.id: e};
  final lines = <String, Emp201SummaryLine>{};
  for (final p in slips) {
    final l = lines.putIfAbsent(p.employeeId, () => Emp201SummaryLine(p.employeeId, byId[p.employeeId]));
    l
      ..gross += p.gross
      ..uif += p.uif
      ..paye += p.paye
      ..payslips += 1;
  }
  final out = {for (final g in Emp201Group.values) g: <Emp201SummaryLine>[]};
  for (final l in lines.values) {
    out[emp201GroupOf(l.employee)]!.add(l);
  }
  for (final g in out.values) {
    g.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
  return out;
}

/// Only the payslips of employees declared on the EMP201.
List<Payslip> declaredSlips(List<Payslip> slips, List<Employee> employees) {
  final notDeclared = {for (final e in employees) if (!e.declared) e.id};
  return slips.where((p) => !notDeclared.contains(p.employeeId)).toList();
}
