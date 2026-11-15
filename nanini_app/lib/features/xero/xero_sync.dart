import '../suppliers/suppliers_models.dart';
import 'xero_api.dart';

/// The hub reading back from Xero: every contact's balance beside the hub's,
/// and the supplier payments made in Xero taken into the hub (instead of
/// the bank CSVs).

String _k(String name) => name.trim().toLowerCase();
double _r(double v) => (v * 100).roundToDouble() / 100;

/// A contact's balance in Xero and in the hub (null: not there).
class XeroBalanceRow {
  XeroBalanceRow({required this.name, required this.kind, this.xero, this.hub});
  final String name;

  /// 'Supplier', 'Customer' or 'Only in Xero'.
  final String kind;
  final double? xero;
  final double? hub;
  double get difference => _r((xero ?? 0) - (hub ?? 0));
  bool get differs => difference.abs() >= 0.01;
}

/// Suppliers (what we owe: Xero's accounts payable) and customers (what they
/// owe: accounts receivable), matched by name; a Xero contact that's neither,
/// with a balance, too. Differences first, then by name.
List<XeroBalanceRow> xeroBalanceRows({
  required List<XeroContactBalance> xero,
  required Map<String, double> suppliersDue,
  required Map<String, double> customersOwed,
}) {
  final byName = {for (final c in xero) _k(c.name): c};
  final used = <String>{};
  final rows = <XeroBalanceRow>[];
  for (final e in suppliersDue.entries) {
    final x = byName[_k(e.key)];
    if (x != null) used.add(_k(e.key));
    rows.add(XeroBalanceRow(name: e.key.trim(), kind: 'Supplier', xero: x == null ? null : _r(x.payable), hub: _r(e.value)));
  }
  for (final e in customersOwed.entries) {
    final x = byName[_k(e.key)];
    if (x != null) used.add(_k(e.key));
    rows.add(XeroBalanceRow(name: e.key.trim(), kind: 'Customer', xero: x == null ? null : _r(x.receivable), hub: _r(e.value)));
  }
  for (final c in xero) {
    if (used.contains(_k(c.name))) continue;
    final v = _r(c.payable - c.receivable);
    if (v.abs() >= 0.01) rows.add(XeroBalanceRow(name: c.name, kind: 'Only in Xero', xero: v));
  }
  rows.removeWhere((r) => (r.xero ?? 0).abs() < 0.01 && (r.hub ?? 0).abs() < 0.01);
  rows.sort((a, b) {
    if (a.differs != b.differs) return a.differs ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return rows;
}

/// A payment made in Xero, to add to a hub supplier.
class XeroPaymentToAdd {
  XeroPaymentToAdd(this.supplier, this.money);
  final Supplier supplier;
  final XeroMoneyOut money;
  String get notes => 'From Xero: ${money.what} (Xero ${money.id})';
}

int _days(String a, String b) => DateTime.parse(a).difference(DateTime.parse(b)).inDays.abs();

/// Which of Xero's payments to suppliers ([out]) the hub doesn't have yet.
/// One the hub has already: taken in from Xero before (its Xero id in the
/// notes), or the same payment from the bank -- the same supplier, within 3
/// days, the same amount; a bank payment Xero split over several bills
/// and/or spend money that day counts as one (their total, within R1 for
/// rounding). Payments to contacts that aren't hub suppliers: their totals
/// per contact, to say.
({List<XeroPaymentToAdd> add, int alreadyIn, Map<String, double> notSuppliers}) xeroSupplierPaymentsToAdd({
  required List<XeroMoneyOut> out,
  required List<Supplier> suppliers,
  required List<SupplierPayment> payments,
}) {
  final byName = {for (final s in suppliers) _k(s.name): s};
  final notSuppliers = <String, double>{};
  final taken = [for (final p in payments) p.notes ?? ''].join('\n');
  var alreadyIn = 0;
  // Per supplier and day.
  final groups = <(String, String), List<XeroMoneyOut>>{};
  for (final m in out) {
    final s = byName[_k(m.contact)];
    if (s == null) {
      notSuppliers[m.contact] = _r((notSuppliers[m.contact] ?? 0) + m.amount);
      continue;
    }
    if (taken.contains('(Xero ${m.id})')) {
      alreadyIn++;
      continue;
    }
    (groups[(s.id, m.date)] ??= []).add(m);
  }
  final used = <String>{};
  SupplierPayment? find(String supplierId, String date, double amount, double tolerance) {
    final fits = [
      for (final p in payments)
        if (p.supplierId == supplierId && !used.contains(p.id) && (p.amount - amount).abs() <= tolerance && _days(p.date, date) <= 3) p
    ]..sort((a, b) => _days(a.date, date).compareTo(_days(b.date, date)));
    return fits.isEmpty ? null : fits.first;
  }

  final add = <XeroPaymentToAdd>[];
  final keys = groups.keys.toList()..sort((a, b) => a.$2.compareTo(b.$2));
  for (final key in keys) {
    final ms = groups[key]!;
    final supplier = suppliers.firstWhere((s) => s.id == key.$1);
    if (ms.length > 1) {
      final whole = find(key.$1, key.$2, _r(ms.fold(0.0, (t, m) => t + m.amount)), 1.0);
      if (whole != null) {
        used.add(whole.id);
        alreadyIn += ms.length;
        continue;
      }
    }
    for (final m in ms) {
      final same = find(key.$1, m.date, m.amount, 0.01);
      if (same != null) {
        used.add(same.id);
        alreadyIn++;
      } else {
        add.add(XeroPaymentToAdd(supplier, m));
      }
    }
  }
  return (add: add, alreadyIn: alreadyIn, notSuppliers: notSuppliers);
}
