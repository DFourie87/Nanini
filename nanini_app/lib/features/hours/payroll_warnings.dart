import '../../core/formatters.dart';
import '../employees/employees_models.dart';
import 'pay_run.dart';

/// Something to look at before a payroll is approved, shown in the Run
/// payroll window. [blocking]: the payroll can't run with it (untick the
/// worker or fix it first); the rest only need "I've checked these".
class PayrollWarning {
  const PayrollWarning(this.line, this.text, {this.blocking = false});
  final PayLine line;
  final String text;
  final bool blocking;
}

/// More hours than this on one day: probably the same day captured twice.
const kMaxDayHours = 12.0;

/// This many working days (Monday to Saturday) in a row without hours,
/// between a worker's first and last day: missing days.
const kMissingDays = 3;

/// The warnings for [lines] (the workers ticked to be paid), in the order
/// of the lines; [farmNames]: farm id -> name, for "hours at two farms".
List<PayrollWarning> payrollWarnings(List<PayLine> lines, {Map<String, String> farmNames = const {}}) {
  final out = <PayrollWarning>[];
  for (final l in lines) {
    final e = l.employee;
    if (e.paymentMethod == PaymentMethod.atm && (e.phoneNumber ?? '').trim().isEmpty) {
      out.add(PayrollWarning(l, 'Paid by ATM, but no phone number', blocking: true));
    }
    if (l.hours > 0 && l.tariff <= 0) {
      out.add(PayrollWarning(l, 'No tariff: ${fmtHours(l.hours)} would be paid at R0', blocking: true));
    }
    if (l.nett < -0.005) {
      out.add(PayrollWarning(l, 'Nett pay below R0 (${fmtR(l.nett)}): the deductions are more than the pay'));
    }
    // Per day: the hours, and the farms they were captured at.
    final byDay = <String, double>{};
    final farmsByDay = <String, Set<String>>{};
    for (final h in l.entries) {
      byDay[h.date] = (byDay[h.date] ?? 0) + h.hours;
      if (h.farmId != null && h.hours > 0) (farmsByDay[h.date] ??= {}).add(h.farmId!);
    }
    final days = byDay.keys.toList()..sort();
    final long = [for (final d in days) if (byDay[d]! > kMaxDayHours + 0.001) d];
    if (long.isNotEmpty) {
      out.add(PayrollWarning(l, 'Over ${fmtHours(kMaxDayHours)} on ${long.map((d) => '${fmtDateDisplay(d)} (${fmtHours(byDay[d])})').join(', ')}'));
    }
    final twoFarms = [for (final d in days) if ((farmsByDay[d]?.length ?? 0) > 1) d];
    if (twoFarms.isNotEmpty) {
      String where(String d) => farmsByDay[d]!.map((f) => farmNames[f] ?? 'another farm').join(' and ');
      out.add(PayrollWarning(l, 'Hours at two farms on ${twoFarms.map((d) => '${fmtDateDisplay(d)} (${where(d)})').join(', ')}'));
    }
    final worked = [for (final d in days) if (byDay[d]! > 0.001) d];
    final gap = _longestGap(worked);
    if (gap != null) {
      out.add(PayrollWarning(l, 'No hours ${fmtDateDisplay(gap.$1)} to ${fmtDateDisplay(gap.$2)} (${gap.$3} working days)'));
    }
  }
  return out;
}

/// The longest run of working days (Monday to Saturday) without hours
/// between the first and last day worked: (first, last, days), or null when
/// shorter than [kMissingDays].
(String, String, int)? _longestGap(List<String> worked) {
  if (worked.length < 2) return null;
  final set = worked.toSet();
  (String, String, int)? best;
  DateTime? start;
  var run = 0;
  DateTime? lastMissing;
  for (var d = DateTime.parse(worked.first); !d.isAfter(DateTime.parse(worked.last)); d = DateTime(d.year, d.month, d.day + 1)) {
    if (d.weekday == DateTime.sunday) continue;
    if (set.contains(toDateStr(d))) {
      if (run >= kMissingDays && (best == null || run > best.$3)) best = (toDateStr(start!), toDateStr(lastMissing!), run);
      run = 0;
      start = null;
    } else {
      start ??= d;
      lastMissing = d;
      run++;
    }
  }
  return best;
}
