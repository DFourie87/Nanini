import 'dart:math';

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
    this.farmId,
  });
  final String id;
  final String employeeId;
  final String date;

  /// The farm this day was worked on (may differ from the worker's own
  /// farm, where they're paid). Null on older entries: their own farm.
  final String? farmId;
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
        farmId: j['farm_id'] as String?,
      );
}

class KgEntry {
  KgEntry({required this.id, required this.employeeId, required this.date, required this.kg, required this.ratePerKg, required this.gross, this.farmId});
  final String id;

  /// The farm picked on (null on older entries: the worker's own farm).
  final String? farmId;
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
        farmId: j['farm_id'] as String?,
      );
}

/// Extra pay on top of a worker's hours (Payslips on the phone, or Summary): a set
/// amount, or [hours] at a different [rate]. Open until a payroll run pays
/// it ([payslipId]).
class PayExtra {
  PayExtra({
    required this.id,
    required this.employeeId,
    this.farmId,
    required this.date,
    required this.description,
    this.hours,
    this.rate,
    required this.amount,
    this.payslipId,
  });
  final String id;
  final String employeeId;
  final String? farmId;
  final String date;
  final String description;
  final double? hours;
  final double? rate;
  final double amount;
  final String? payslipId;

  bool get isHours => (hours ?? 0) > 0;

  factory PayExtra.fromJson(Map<String, dynamic> j) => PayExtra(
        id: j['id'] as String,
        employeeId: j['employee_id'] as String,
        farmId: j['farm_id'] as String?,
        date: j['entry_date'] as String,
        description: j['description'] as String? ?? '',
        hours: (j['hours'] as num?)?.toDouble(),
        rate: (j['rate'] as num?)?.toDouble(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        payslipId: j['payslip_id'] as String?,
      );

  /// For the payslip: what it was for.
  Map<String, dynamic> toLine() => {'description': description, 'hours': ?hours, 'rate': ?rate, 'amount': amount};
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

/// The most UIF is worked out on: R17 712 a month (so at most R177.12 a
/// month from the employee, and the same from the employer).
const kUifCeiling = 17712.0;

/// The employee's UIF: 1% of the pay, up to the ceiling.
double calcUIF(double monthlyGross) => (monthlyGross < kUifCeiling ? monthlyGross : kUifCeiling) * 0.01;

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
    this.hoursWorked = 0,
    this.hourlyRate = 0,
    this.kgWorked = 0,
    this.kgRate = 0,
    this.extraPay = 0,
    this.extras = const [],
    required this.paye,
    required this.uif,
    required this.rent,
    required this.loan,
    required this.tuckshopDeduction,
    required this.nett,
    required this.createdAt,
    this.atmAccessCode,
  });
  final String id;
  final String employeeId;
  final String? farmId;
  final String periodStart;
  final String periodEnd;
  final String paidDate;
  final double gross;

  /// The hours-worked and picking (kg) components behind [gross], shown on
  /// the payslip as "X hrs × R Y/hr" etc. Either can be 0 if the employee
  /// wasn't paid that way this period.
  final double hoursWorked;
  final double hourlyRate;
  final double kgWorked;
  final double kgRate;

  /// Extra pay included in [gross], and its lines ({description, hours?,
  /// rate?, amount}) for printing.
  final double extraPay;
  final List<Map<String, dynamic>> extras;
  final double paye;
  final double uif;
  final double rent;
  final double loan;
  final double tuckshopDeduction;
  final double nett;
  final DateTime createdAt;

  /// ATM card payslips only: that payday's 6-digit access code (the same for
  /// everyone paid by ATM that day, new every payday).
  final String? atmAccessCode;

  double get totalDeductions => paye + uif + rent + loan + tuckshopDeduction;

  factory Payslip.fromJson(Map<String, dynamic> j) => Payslip(
        id: j['id'] as String,
        employeeId: j['employee_id'] as String,
        farmId: j['farm_id'] as String?,
        periodStart: j['period_start'] as String,
        periodEnd: j['period_end'] as String,
        paidDate: j['paid_date'] as String,
        gross: (j['gross'] as num?)?.toDouble() ?? 0,
        hoursWorked: (j['hours_worked'] as num?)?.toDouble() ?? 0,
        hourlyRate: (j['hourly_rate'] as num?)?.toDouble() ?? 0,
        kgWorked: (j['kg_worked'] as num?)?.toDouble() ?? 0,
        kgRate: (j['kg_rate'] as num?)?.toDouble() ?? 0,
        extraPay: (j['extra_pay'] as num?)?.toDouble() ?? 0,
        extras: ((j['extras'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList(),
        paye: (j['paye'] as num?)?.toDouble() ?? 0,
        uif: (j['uif'] as num?)?.toDouble() ?? 0,
        rent: (j['rent'] as num?)?.toDouble() ?? 0,
        loan: (j['loan'] as num?)?.toDouble() ?? 0,
        tuckshopDeduction: (j['tuckshop_deduction'] as num?)?.toDouble() ?? 0,
        nett: (j['nett'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.parse(j['created_at'] as String? ?? DateTime.now().toIso8601String()),
        atmAccessCode: j['atm_access_code'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        'employee_id': employeeId,
        'farm_id': farmId,
        'period_start': periodStart,
        'period_end': periodEnd,
        'paid_date': paidDate,
        'gross': gross,
        'hours_worked': hoursWorked,
        'hourly_rate': hourlyRate,
        'kg_worked': kgWorked,
        'kg_rate': kgRate,
        // Only sent when there is extra pay, so runs without any still work
        // on a database without these columns yet.
        if (extraPay != 0) ...{'extra_pay': extraPay, 'extras': extras},
        'paye': paye,
        'uif': uif,
        'rent': rent,
        'loan': loan,
        'tuckshop_deduction': tuckshopDeduction,
        'nett': nett,
        'atm_access_code': ?atmAccessCode,
      };
}

/// The ATM access code for payday [paidDate]: the one already on that day's
/// payslips, else a new 6-digit number never used on another payday.
String atmCodeFor(String paidDate, List<Payslip> payslips, {Random? random}) {
  for (final p in payslips) {
    if (p.paidDate == paidDate && (p.atmAccessCode ?? '').isNotEmpty) return p.atmAccessCode!;
  }
  final used = {for (final p in payslips) ?p.atmAccessCode};
  final r = random ?? Random.secure();
  while (true) {
    final code = (100000 + r.nextInt(900000)).toString();
    if (!used.contains(code)) return code;
  }
}

bool isAtmCode(String s) => RegExp(r'^\d{6}$').hasMatch(s);
