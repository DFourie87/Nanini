import '../sales/sales_customers_models.dart';
import '../sales/sales_models.dart';
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
/// with a balance, too. Customers first, then suppliers, then the ones only
/// in Xero, each alphabetically.
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
  const order = {'Customer': 0, 'Supplier': 1, 'Only in Xero': 2};
  rows.sort((a, b) {
    final k = order[a.kind]!.compareTo(order[b.kind]!);
    return k != 0 ? k : a.name.toLowerCase().compareTo(b.name.toLowerCase());
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

/// Payments a customer made in Xero on one day, to add to the hub as one
/// payment: the account sales they paid, each with what was paid on it.
class XeroCustomerPaymentToAdd {
  XeroCustomerPaymentToAdd(this.customer, this.date, this.items);
  final Customer customer;
  final String date;

  /// Each Xero payment with the hub's account sale number it paid.
  final List<(XeroMoneyIn, String)> items;
  double get amount => _r(items.fold(0.0, (t, x) => t + x.$1.amount));

  /// Kept on the payment: its Xero ids, so it's never taken twice.
  String get fileName => 'Xero: ${[for (final (m, _) in items) m.id].join(',')}';
  List<({String reportNumber, double nett})> get lines => [for (final (m, n) in items) (reportNumber: n, nett: _r(m.amount))];
}

/// The hub's account sale an invoice number in Xero is: as sent ("103593",
/// "303984 (peppers)", or "15060-WEN" when two agents used the number).
String? _hubSale(String invoice, Set<String> numbers) {
  final n = baseReportNumber(invoice.trim());
  if (numbers.contains(n)) return n;
  final m = RegExp(r'^(.+)-[A-Z]{1,3}$').firstMatch(n);
  return m != null && numbers.contains(m.group(1)!) ? m.group(1) : null;
}

/// Which of Xero's customer payments ([incoming]) the hub doesn't have yet,
/// as one payment per customer and day. One the hub has already: taken in
/// from Xero before (its Xero id kept on the payment), or its account sale
/// already paid in the hub (a payment summary). Payments to contacts that
/// aren't hub customers, and of invoices that aren't account sales (e.g.
/// pallet invoices): their totals, to say.
({List<XeroCustomerPaymentToAdd> add, int alreadyIn, Map<String, double> notCustomers, Map<String, double> notSales}) xeroCustomerPaymentsToAdd({
  required List<XeroMoneyIn> incoming,
  required List<Customer> customers,
  required List<SalesReport> reports,
  required List<CustomerPayment> payments,
}) {
  final byName = {for (final c in customers) _k(c.name): c};
  final taken = [for (final p in payments) if ((p.fileName ?? '').startsWith('Xero:')) p.fileName!].join(',');
  final notCustomers = <String, double>{};
  final notSales = <String, double>{};
  var alreadyIn = 0;
  final groups = <(String, String), List<(XeroMoneyIn, String)>>{};
  for (final m in incoming) {
    final c = byName[_k(m.contact)];
    if (c == null) {
      notCustomers[m.contact] = _r((notCustomers[m.contact] ?? 0) + m.amount);
      continue;
    }
    if (taken.contains(m.id)) {
      alreadyIn++;
      continue;
    }
    final numbers = {for (final r in reports) if (r.agent == c.agent) baseReportNumber(r.reportNumber)};
    final sale = _hubSale(m.invoice, numbers);
    if (sale == null) {
      notSales[m.invoice] = _r((notSales[m.invoice] ?? 0) + m.amount);
      continue;
    }
    final paid = {for (final p in payments) if (p.customerId == c.id) for (final l in p.lines) l.reportNumber};
    if (paid.contains(sale)) {
      alreadyIn++;
      continue;
    }
    (groups[(c.id, m.date)] ??= []).add((m, sale));
  }
  final add = [
    for (final e in groups.entries) XeroCustomerPaymentToAdd(customers.firstWhere((c) => c.id == e.key.$1), e.key.$2, e.value),
  ]..sort((a, b) => a.date == b.date ? a.customer.name.compareTo(b.customer.name) : a.date.compareTo(b.date));
  return (add: add, alreadyIn: alreadyIn, notCustomers: notCustomers, notSales: notSales);
}
