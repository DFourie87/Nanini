import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/supabase_client.dart';
import '../employees/employees_models.dart';
import '../tuckshop/tuckshop_models.dart';
import 'hours_models.dart';
import 'hours_repository.dart';
import 'pay_run.dart';

/// The members' payroll runs by itself: their fixed monthly salaries, paid
/// on the last Friday of each month -- the first one on 30 Sep 2026.
const kMembersFirstPayday = '2026-09-30';

DateTime lastFridayOf(int year, int month) {
  var d = DateTime(year, month + 1, 0); // the month's last day
  while (d.weekday != DateTime.friday) {
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return d;
}

/// The members' payday due by [today]: this month's last Friday once it's
/// here, else last month's; none before [kMembersFirstPayday].
String? membersPayday(DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  final thisMonth = lastFridayOf(t.year, t.month);
  final day = toDateStr(t.isBefore(thisMonth) ? lastFridayOf(t.year, t.month - 1) : thisMonth);
  if (day.compareTo(kMembersFirstPayday) >= 0) return day;
  return toDateStr(t).compareTo(kMembersFirstPayday) >= 0 ? kMembersFirstPayday : null;
}

/// The members' payslips due by [today], not yet paid: each member on
/// payroll with a salary, once a month. A member already paid for that
/// month (a payslip up to a day in it, e.g. run by hand) is left out.
List<Payslip> membersDue({
  required DateTime today,
  required List<Employee> employees,
  required List<Payslip> payslips,
  List<HoursEntry> entries = const [],
  List<KgEntry> kgEntries = const [],
  List<TuckshopPurchase> purchases = const [],
  List<PayExtra> extras = const [],
}) =>
    membersDueLines(today: today, employees: employees, payslips: payslips, entries: entries, kgEntries: kgEntries, purchases: purchases, extras: extras)
        .map((x) => x.$1)
        .toList();

/// [membersDue], with each payslip's line (its tuck shop and extra pay).
List<(Payslip, PayLine)> membersDueLines({
  required DateTime today,
  required List<Employee> employees,
  required List<Payslip> payslips,
  List<HoursEntry> entries = const [],
  List<KgEntry> kgEntries = const [],
  List<TuckshopPurchase> purchases = const [],
  List<PayExtra> extras = const [],
}) {
  final day = membersPayday(today);
  if (day == null) return const [];
  final monthStart = '${day.substring(0, 7)}-01';
  final members = employees.where((e) => e.isMember && e.onPayroll && (e.monthlySalary ?? 0) > 0).toList();
  final unpaid = [
    for (final m in members)
      if (!payslips.any((p) => p.employeeId == m.id && p.periodEnd.compareTo(monthStart) >= 0)) m,
  ];
  if (unpaid.isEmpty) return const [];
  final ids = {for (final m in unpaid) m.id};
  final lines = buildPayRun(
    payUpTo: day,
    employees: unpaid,
    entries: entries,
    kgEntries: kgEntries,
    purchases: purchases,
    // Only their own payslips: never a farm's workers' last pay.
    payslips: payslips.where((p) => ids.contains(p.employeeId)).toList(),
    extras: extras,
  );
  return [
    for (final l in lines)
      // The month's salary: from the day after their last pay, else the 1st.
      (draftPayslip(l, upTo: day, paidDate: day, periodStart: l.since == null ? monthStart : null), l),
  ];
}

/// Runs the members' payroll when it's due -- checked when an admin opens
/// the hub, at most once a day (and again a few minutes after a failure).
class MembersAutoPay {
  static String? _doneDay;
  static DateTime? _failedAt;
  static bool _running = false;

  static void check(BuildContext context) {
    final today = toDateStr(DateTime.now());
    if (_running || _doneDay == today) return;
    if (_failedAt != null && DateTime.now().difference(_failedAt!) < const Duration(minutes: 10)) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    _running = true;
    _run().then((n) {
      _doneDay = today;
      if (n > 0) messenger?.showSnackBar(SnackBar(content: Text('Members payroll run: $n paid (Employees > Reports).')));
    }, onError: (Object e) {
      _failedAt = DateTime.now();
      debugPrint('Members payroll: $e');
    }).whenComplete(() => _running = false);
  }

  static Future<int> _run() async {
    final now = DateTime.now();
    final day = membersPayday(now);
    if (day == null) return 0;
    List<Map<String, dynamic>> rows(Object r) => (r as List).cast<Map<String, dynamic>>();
    final employees = rows(await sb.from('employees').select().eq('is_member', true)).map(Employee.fromJson).toList();
    final ids = [for (final e in employees) if (e.onPayroll && (e.monthlySalary ?? 0) > 0) e.id];
    if (ids.isEmpty) return 0;
    final payslips = rows(await sb.from('payslips').select().inFilter('employee_id', ids)).map(Payslip.fromJson).toList();
    // Quick way out: everyone already paid this month.
    if (membersDue(today: now, employees: employees, payslips: payslips).isEmpty) return 0;
    final entries = rows(await sb.from('hours_entries').select().inFilter('employee_id', ids).lte('entry_date', day)).map(HoursEntry.fromJson).toList();
    final kg = rows(await sb.from('kg_entries').select().inFilter('employee_id', ids).lte('entry_date', day)).map(KgEntry.fromJson).toList();
    final purchases = rows(await sb.from('tuckshop_purchases').select().inFilter('employee_id', ids).isFilter('payslip_id', null)).map(TuckshopPurchase.fromJson).toList();
    final extras = rows(await sb.from('pay_extras').select().inFilter('employee_id', ids).isFilter('payslip_id', null)).map(PayExtra.fromJson).toList();
    final due = membersDueLines(today: now, employees: employees, payslips: payslips, entries: entries, kgEntries: kg, purchases: purchases, extras: extras);
    if (due.isEmpty) return 0;
    await HoursRepository().runPayroll([
      for (final (slip, l) in due) (slip, [for (final p in l.purchases) p.id], [for (final x in l.extras) x.id]),
    ]);
    return due.length;
  }
}
