class HoursSettings {
  HoursSettings({this.dailyThreshold = 9, this.otMultiplier = 1.5});
  final double dailyThreshold;
  final double otMultiplier;

  factory HoursSettings.fromJson(Map<String, dynamic> j) => HoursSettings(
        dailyThreshold: (j['daily_threshold'] as num?)?.toDouble() ?? 9,
        otMultiplier: (j['ot_multiplier'] as num?)?.toDouble() ?? 1.5,
      );
}

class HoursEntry {
  HoursEntry({
    required this.id,
    required this.employeeId,
    required this.date,
    required this.hours,
    required this.rate,
    required this.dailyThreshold,
    required this.otMultiplier,
    required this.normalHours,
    required this.otHours,
    required this.gross,
    this.via,
    this.groupName,
  });
  final String id;
  final String employeeId;
  final String date;
  final double hours;
  final double rate;
  final double dailyThreshold;
  final double otMultiplier;
  final double normalHours;
  final double otHours;
  final double gross;
  final String? via;
  final String? groupName;

  factory HoursEntry.fromJson(Map<String, dynamic> j) => HoursEntry(
        id: j['id'] as String,
        employeeId: j['employee_id'] as String,
        date: j['entry_date'] as String,
        hours: (j['hours'] as num).toDouble(),
        rate: (j['rate'] as num?)?.toDouble() ?? 0,
        dailyThreshold: (j['daily_threshold'] as num?)?.toDouble() ?? 9,
        otMultiplier: (j['ot_multiplier'] as num?)?.toDouble() ?? 1.5,
        normalHours: (j['normal_hours'] as num?)?.toDouble() ?? 0,
        otHours: (j['ot_hours'] as num?)?.toDouble() ?? 0,
        gross: (j['gross'] as num?)?.toDouble() ?? 0,
        via: j['via'] as String?,
        groupName: j['group_name'] as String?,
      );
}

class KgEntry {
  KgEntry({required this.id, required this.employeeId, required this.date, required this.kg, required this.ratePerKg, required this.gross});
  final String id;
  final String employeeId;
  final String date;
  final double kg;
  final double ratePerKg;
  final double gross;

  factory KgEntry.fromJson(Map<String, dynamic> j) => KgEntry(
        id: j['id'] as String,
        employeeId: j['employee_id'] as String,
        date: j['entry_date'] as String,
        kg: (j['kg'] as num).toDouble(),
        ratePerKg: (j['rate_per_kg'] as num).toDouble(),
        gross: (j['gross'] as num).toDouble(),
      );
}

/// (hours, normalHours, otHours, gross). Gross = hours × rate — no OT
/// premium is actually applied; the normal/OT split is informational only,
/// matching the web app's `calcPay()`.
class PayCalc {
  static ({double normal, double ot, double gross}) calc(double hours, double rate, double threshold) {
    final normal = hours < threshold ? hours : threshold;
    final ot = hours > threshold ? hours - threshold : 0.0;
    return (normal: normal, ot: ot, gross: hours * rate);
  }
}

/// SARS 2026/27 monthly PAYE, matching the web app's `calcMonthlyPAYE()`.
double calcMonthlyPAYE(double monthlyGross) {
  final annual = monthlyGross * 12;
  const brackets = [
    (245100.0, 0.18, 0.0),
    (383100.0, 0.26, 44118.0),
    (530200.0, 0.31, 80730.0),
    (695800.0, 0.36, 126522.0),
    (887000.0, 0.39, 186322.0),
    (1878600.0, 0.41, 260638.0),
    (double.infinity, 0.45, 636498.0),
  ];
  var prevCeiling = 0.0;
  var annualTax = 0.0;
  for (final (ceiling, rate, base) in brackets) {
    if (annual <= ceiling) {
      annualTax = base + (annual - prevCeiling) * rate;
      break;
    }
    prevCeiling = ceiling;
  }
  const primaryRebate = 17820.0;
  final afterRebate = (annualTax - primaryRebate).clamp(0, double.infinity);
  return afterRebate / 12;
}

double calcUIF(double monthlyGross) => monthlyGross * 0.01;

/// One employee's slice of a payroll run -- a permanent record of what was
/// paid for a given period, once "Run payroll" is used. Pay periods are
/// never a fixed length or start day, so both dates are stored explicitly
/// rather than assumed (e.g. calendar month).
class Payslip {
  Payslip({
    required this.id,
    required this.employeeId,
    this.farmId,
    required this.periodStart,
    required this.periodEnd,
    required this.paidDate,
    required this.gross,
    required this.paye,
    required this.uif,
    required this.rent,
    required this.loan,
    required this.tuckshopDeduction,
    required this.nett,
    required this.createdAt,
  });
  final String id;
  final String employeeId;
  final String? farmId;
  final String periodStart;
  final String periodEnd;
  final String paidDate;
  final double gross;
  final double paye;
  final double uif;
  final double rent;
  final double loan;
  final double tuckshopDeduction;
  final double nett;
  final DateTime createdAt;

  factory Payslip.fromJson(Map<String, dynamic> j) => Payslip(
        id: j['id'] as String,
        employeeId: j['employee_id'] as String,
        farmId: j['farm_id'] as String?,
        periodStart: j['period_start'] as String,
        periodEnd: j['period_end'] as String,
        paidDate: j['paid_date'] as String,
        gross: (j['gross'] as num?)?.toDouble() ?? 0,
        paye: (j['paye'] as num?)?.toDouble() ?? 0,
        uif: (j['uif'] as num?)?.toDouble() ?? 0,
        rent: (j['rent'] as num?)?.toDouble() ?? 0,
        loan: (j['loan'] as num?)?.toDouble() ?? 0,
        tuckshopDeduction: (j['tuckshop_deduction'] as num?)?.toDouble() ?? 0,
        nett: (j['nett'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.parse(j['created_at'] as String? ?? DateTime.now().toIso8601String()),
      );

  Map<String, dynamic> toInsert() => {
        'employee_id': employeeId,
        'farm_id': farmId,
        'period_start': periodStart,
        'period_end': periodEnd,
        'paid_date': paidDate,
        'gross': gross,
        'paye': paye,
        'uif': uif,
        'rent': rent,
        'loan': loan,
        'tuckshop_deduction': tuckshopDeduction,
        'nett': nett,
      };
}
