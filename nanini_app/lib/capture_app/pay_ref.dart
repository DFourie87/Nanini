import '../features/employees/employees_models.dart';
import '../features/hours/hours_models.dart';
import '../features/hours/pay_run.dart';
import '../features/tuckshop/tuckshop_models.dart';

/// The Payslips task's pay data (capture_reference 'pay'), as the hub's own
/// models so the phone works out "since the last pay" exactly like the hub.
class PayRef {
  PayRef({
    required this.employees,
    required this.entries,
    required this.kgEntries,
    required this.purchases,
    required this.payslips,
    required this.extras,
    this.pending = const [],
  });

  factory PayRef.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) {
      final out = <T>[];
      for (final e in (j[key] as List?) ?? const []) {
        try {
          out.add(f((e as Map).cast<String, dynamic>()));
        } catch (_) {} // one odd row never hides the rest
      }
      return out;
    }

    return PayRef(
      employees: list('employees', Employee.fromJson),
      entries: list('hours', HoursEntry.fromJson),
      kgEntries: list('kg', KgEntry.fromJson),
      purchases: list('tuck', TuckshopPurchase.fromJson),
      payslips: list('paid', Payslip.fromJson),
      extras: list('extras', PayExtra.fromJson),
      pending: list('pending', PendingCapture.fromJson),
    );
  }

  /// Sent from the phones, not yet approved in the hub (any phone's).
  final List<PendingCapture> pending;

  /// This pay data with everything still waiting for approval worked in
  /// (from [pending] and [local], this phone's own -- the same capture is
  /// counted once): hours and picking captured, tuck shop sales, and
  /// earlier payslip checks (tariff, rent, loan, UIF, hours, Haaskraal tuck
  /// shop debt, extra pay). So Payslips matches what the office will see
  /// once they're approved. Their rows' ids start with "pending-".
  PayRef withPending(Iterable<PendingCapture> local) {
    final all = <String, PendingCapture>{for (final c in pending) c.id: c, for (final c in local) c.id: c}.values.toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (all.isEmpty) return this;
    final emps = {for (final e in employees) e.id: e};
    final entries = [...this.entries];
    final kg = [...kgEntries];
    final purchases = [...this.purchases];
    final extras = [...this.extras];
    double num0(Object? v) => (v as num?)?.toDouble() ?? 0;
    for (final c in all) {
      final p = c.payload;
      final date = p['date'] as String? ?? c.at.toIso8601String().substring(0, 10);
      switch (c.module) {
        case 'hours':
          // Changed hours for a day: what was there for those workers goes.
          final replace = ((p['replace'] as List?) ?? const []).toSet();
          if (replace.isNotEmpty) entries.removeWhere((e) => e.date == date && replace.contains(e.employeeId));
          for (final l in ((p['entries'] as List?) ?? const []).cast<Map>()) {
            final h = num0(l['hours']);
            entries.add(HoursEntry(
              id: 'pending-${c.id}-${l['employee_id']}',
              employeeId: l['employee_id'] as String,
              date: date,
              hours: h,
              rate: 0,
              dailyThreshold: 9,
              otMultiplier: 1.5,
              normalHours: h,
              otHours: 0,
              gross: 0,
              farmId: p['farm_id'] as String?,
            ));
          }
        case 'kg':
          // The rate per kg is set when the office approves: kg only.
          for (final l in ((p['entries'] as List?) ?? const []).cast<Map>()) {
            kg.add(KgEntry(
              id: 'pending-${c.id}-${l['employee_id']}',
              employeeId: l['employee_id'] as String,
              date: date,
              kg: num0(l['kg']),
              ratePerKg: 0,
              gross: 0,
              farmId: p['farm_id'] as String?,
            ));
          }
        case 'tuckshop':
          final total = p['manual_total'] != null
              ? num0(p['manual_total'])
              : ((p['lines'] as List?) ?? const []).cast<Map>().fold<double>(0, (a, l) => a + num0(l['qty']) * num0(l['price']));
          purchases.add(TuckshopPurchase(
            id: 'pending-${c.id}',
            employeeId: p['employee_id'] as String,
            revenue: total,
            cogs: 0,
            date: date,
            farmId: p['farm_id'] as String?,
          ));
        case 'pay_check':
          for (final ch in ((p['changes'] as List?) ?? const []).cast<Map>()) {
            final id = ch['employee_id'] as String;
            final e = emps[id];
            if (e == null) continue;
            emps[id] = e.copyWithPay(
              ratePerHour: (ch['rate_per_hour'] as num?)?.toDouble(),
              rentDeduction: (ch['rent_deduction'] as num?)?.toDouble(),
              loanDeduction: (ch['loan_deduction'] as num?)?.toDouble(),
              uifDeduct: ch['uif_deduct'] as bool?,
            );
            // Already in the hours (put in when it was sent): not twice.
            if (ch['hours_since_last_pay'] != null && p['hours_applied'] != true) {
              final diff = num0(ch['hours_since_last_pay']) - num0(ch['hours_was']);
              if (diff.abs() > 0.001) {
                entries.add(HoursEntry(
                  id: 'pending-${c.id}-$id-hours',
                  employeeId: id,
                  date: ch['hours_up_to'] as String? ?? date,
                  hours: diff,
                  rate: 0,
                  dailyThreshold: 9,
                  otMultiplier: 1.5,
                  normalHours: diff,
                  otHours: 0,
                  gross: 0,
                  farmId: p['farm_id'] as String?,
                ));
              }
            }
            final shop = ch['tuckshop_farm_id'] as String?;
            if (ch['tuckshop_debt'] != null && shop != null) {
              // The debt at that shop becomes the amount typed.
              final owed = purchases
                  .where((x) => x.employeeId == id && x.payslipId == null && x.farmId == shop)
                  .fold<double>(0, (a, x) => a + x.revenue);
              purchases.add(TuckshopPurchase(
                id: 'pending-${c.id}-$id-tuck',
                employeeId: id,
                revenue: num0(ch['tuckshop_debt']) - owed,
                cogs: 0,
                date: date,
                farmId: shop,
              ));
            }
          }
          for (final (i, x) in ((p['extras'] as List?) ?? const []).cast<Map>().indexed) {
            final id = x['employee_id'] as String;
            extras.add(PayExtra(
              id: 'pending-${c.id}-x$i',
              employeeId: id,
              farmId: p['farm_id'] as String?,
              date: x['date'] as String? ?? date,
              description: x['description'] as String? ?? 'Extra pay',
              hours: (x['hours'] as num?)?.toDouble(),
              rate: (x['rate'] as num?)?.toDouble(),
              amount: num0(x['amount']),
            ));
          }
      }
    }
    return PayRef(
      employees: [for (final e in employees) emps[e.id]!],
      entries: entries,
      kgEntries: kg,
      purchases: purchases,
      payslips: payslips,
      extras: extras,
    );
  }

  final List<Employee> employees;
  final List<HoursEntry> entries;
  final List<KgEntry> kgEntries;
  final List<TuckshopPurchase> purchases;
  final List<Payslip> payslips;
  final List<PayExtra> extras;

  /// Every worker on [farmId], with what they're owed and owe since their
  /// last pay (up to today). [employees], [extras] and [purchases] may be the
  /// phone's edited copies.
  List<PayLine> linesFor(String farmId, {List<Employee>? employees, List<PayExtra>? extras, List<TuckshopPurchase>? purchases, List<HoursEntry>? entries}) => buildPayRun(
        payUpTo: DateTime.now().toIso8601String().substring(0, 10),
        employees: (employees ?? this.employees).where((e) => e.farmId == farmId).toList(),
        entries: entries ?? this.entries,
        kgEntries: kgEntries,
        purchases: purchases ?? this.purchases,
        payslips: payslips,
        extras: extras ?? this.extras,
        includeAll: true,
      );
}

/// A capture sent from a phone and not yet approved in the hub.
class PendingCapture {
  const PendingCapture({required this.id, required this.module, required this.payload, required this.at});
  final String id;
  final String module;
  final Map<String, dynamic> payload;
  final DateTime at;

  factory PendingCapture.fromJson(Map<String, dynamic> j) => PendingCapture(
        id: j['id'] as String,
        module: j['module'] as String,
        payload: (j['payload'] as Map).cast<String, dynamic>(),
        at: DateTime.tryParse(j['captured_at'] as String? ?? '') ?? DateTime.now(),
      );
}
