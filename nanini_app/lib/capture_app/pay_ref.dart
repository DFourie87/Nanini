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
    );
  }

  final List<Employee> employees;
  final List<HoursEntry> entries;
  final List<KgEntry> kgEntries;
  final List<TuckshopPurchase> purchases;
  final List<Payslip> payslips;
  final List<PayExtra> extras;

  /// Every worker on [farmId], with what they're owed and owe since their
  /// last pay (up to today). [employees] and [extras] may be the phone's
  /// edited copies.
  List<PayLine> linesFor(String farmId, {List<Employee>? employees, List<PayExtra>? extras}) => buildPayRun(
        payUpTo: DateTime.now().toIso8601String().substring(0, 10),
        employees: (employees ?? this.employees).where((e) => e.farmId == farmId).toList(),
        entries: entries,
        kgEntries: kgEntries,
        purchases: purchases,
        payslips: payslips,
        extras: extras ?? this.extras,
        includeAll: true,
      );
}
