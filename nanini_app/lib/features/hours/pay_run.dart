import '../../core/formatters.dart';
import '../employees/employees_models.dart';
import '../tuckshop/tuckshop_models.dart';
import 'hours_models.dart';

/// One employee's pay since their last payslip, up to the "pay up to" date --
/// what Payslips (capture phones) checks and the Summary tab totals and pays.
class PayLine {
  PayLine({
    required this.employee,
    required this.since,
    required this.entries,
    required this.kgEntries,
    required this.purchases,
    this.extras = const [],
  });
  final Employee employee;

  /// Hours and kg dated after this day count (the last pay's end date);
  /// null when this employee (and their farm) has never been paid here.
  final String? since;
  final List<HoursEntry> entries;
  final List<KgEntry> kgEntries;

  /// Tuck shop purchases not yet taken off a payslip.
  final List<TuckshopPurchase> purchases;

  /// Extra pay not yet paid (bonus, hours at another rate...).
  final List<PayExtra> extras;
  double get extraPay => extras.fold<double>(0, (s, x) => s + x.amount);

  double get hours => entries.fold<double>(0, (s, e) => s + e.hours);

  /// The employee's tariff (rate per hour on their record) -- checked in the
  /// Tariff step and used for the whole period.
  double get tariff => employee.ratePerHour ?? 0;
  double get hoursPay => hours * tariff;

  double get kg => kgEntries.fold<double>(0, (s, k) => s + k.kg);
  double get kgPay => kgEntries.fold<double>(0, (s, k) => s + k.gross);
  double get kgRate => kg > 0 ? kgPay / kg : 0;

  /// A member's fixed salary for this pay run.
  double get salary => employee.monthlySalary ?? 0;

  double get gross => hoursPay + kgPay + extraPay + salary;

  /// PAYE when the pay is over the tax threshold (the SARS tables).
  double get paye => calcMonthlyPAYE(gross);

  /// UIF as chosen in Payslips; until chosen, when an ID/passport is on file.
  bool get deductsUif => employee.uifDeduct ?? (employee.idOrPassport ?? '').trim().isNotEmpty;
  double get uif => deductsUif ? calcUIF(gross) : 0;
  double get rent => employee.rentDeduction ?? 0;
  double get loan => employee.loanDeduction ?? 0;
  double get tuckshop => purchases.fold<double>(0, (s, p) => s + p.revenue);
  double get deductions => paye + uif + rent + loan + tuckshop;
  double get nett => gross - deductions;

  /// Logged at a rate other than today's tariff (e.g. before a raise).
  bool get tariffDiffers => entries.any((e) => e.rate > 0 && (e.rate - tariff).abs() > 0.005);

  /// First day this payslip covers: the day after the last pay, else the
  /// earliest day with hours, kg or a tuck shop purchase.
  String periodStart(String payUpTo) {
    final s = parseDateStr(since);
    if (s != null) return toDateStr(s.add(const Duration(days: 1)));
    final dates = [...entries.map((e) => e.date), ...kgEntries.map((k) => k.date), ...purchases.map((p) => p.date), ...extras.map((x) => x.date)]..sort();
    return dates.isEmpty ? payUpTo : dates.first;
  }
}

/// Pay for every employee since their last pay, up to and including
/// [payUpTo] (yyyy-MM-dd). "Last pay" is the employee's latest payslip end
/// date; someone never paid here falls back to their farm's latest pay, so
/// old history isn't pulled in. Employees with nothing to pay or deduct are
/// left out, unless [includeAll] (the Payslips check lists every worker, so
/// someone with no hours logged yet still shows).
List<PayLine> buildPayRun({
  required String payUpTo,
  required List<Employee> employees,
  required List<HoursEntry> entries,
  required List<KgEntry> kgEntries,
  required List<TuckshopPurchase> purchases,
  required List<Payslip> payslips,
  List<PayExtra> extras = const [],
  bool includeAll = false,
}) {
  String? latest(Iterable<String> dates) => dates.isEmpty ? null : dates.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);

  final paidByEmployee = <String, String>{};
  final paidByFarm = <String, String>{};
  for (final p in payslips) {
    paidByEmployee[p.employeeId] = latest([p.periodEnd, ?paidByEmployee[p.employeeId]])!;
    if (p.farmId != null) paidByFarm[p.farmId!] = latest([p.periodEnd, ?paidByFarm[p.farmId!]])!;
  }

  final lines = <PayLine>[];
  for (final emp in employees.where((e) => e.onPayroll)) {
    final since = paidByEmployee[emp.id] ?? paidByFarm[emp.farmId];
    bool inPeriod(String date) => date.compareTo(payUpTo) <= 0 && (since == null || date.compareTo(since) > 0);
    final line = PayLine(
      employee: emp,
      since: since,
      entries: entries.where((e) => e.employeeId == emp.id && inPeriod(e.date)).toList()..sort((a, b) => a.date.compareTo(b.date)),
      kgEntries: kgEntries.where((k) => k.employeeId == emp.id && inPeriod(k.date)).toList()..sort((a, b) => a.date.compareTo(b.date)),
      // Unpaid tuck shop debt, however old -- it stays owing until deducted.
      purchases: purchases.where((p) => p.employeeId == emp.id && p.payslipId == null && p.date.compareTo(payUpTo) <= 0).toList()
        ..sort((a, b) => a.date.compareTo(b.date)),
      // Extra pay not yet paid, however old -- like tuck shop debt.
      extras: extras.where((x) => x.employeeId == emp.id && x.payslipId == null && x.date.compareTo(payUpTo) <= 0).toList()
        ..sort((a, b) => a.date.compareTo(b.date)),
    );
    if (includeAll || line.hours > 0 || line.kg > 0 || line.tuckshop > 0 || line.extras.isNotEmpty || line.salary > 0) lines.add(line);
  }
  lines.sort((a, b) => a.employee.displayName.toLowerCase().compareTo(b.employee.displayName.toLowerCase()));
  return lines;
}

/// Lines grouped by farm, in the farms' usual order ("No farm" last).
/// Members of Nanini 121 CC are left out -- see [membersOf].
List<(Farm?, List<PayLine>)> byFarm(List<PayLine> lines, List<Farm> farms) {
  final workers = lines.where((x) => !x.employee.isMember).toList();
  final out = <(Farm?, List<PayLine>)>[];
  for (final f in farms) {
    final l = workers.where((x) => x.employee.farmId == f.id).toList();
    if (l.isNotEmpty) out.add((f, l));
  }
  final none = workers.where((x) => !farms.any((f) => f.id == x.employee.farmId)).toList();
  if (none.isNotEmpty) out.add((null, none));
  return out;
}

/// The members' lines (only admins ever get them), paid in their own run.
List<PayLine> membersOf(List<PayLine> lines) => lines.where((x) => x.employee.isMember).toList();
