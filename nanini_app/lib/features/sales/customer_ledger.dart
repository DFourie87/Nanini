import '../../core/formatters.dart';
import '../hours/emp201_year_sheet.dart';
import 'sales_customers_models.dart';
import 'sales_models.dart';

/// Sales > Customer ledger: for a period ([from] to [to], yyyy-MM-dd), each
/// market agent's account as a ledger -- a row per account sale (date,
/// number, gross per subcategory, VAT, deductions, nett receivable) and per
/// payment, with the balance brought forward and a running balance -- after
/// a summary of all of them. One section (Excel sheet) per customer.
///
/// The balance counts as the Customers tab does: from the customer's
/// opening balance (on its opening date), else from its first account sale
/// on a payment summary. A payment settles what it paid plus the loans the
/// agent took off.
List<SheetSection> customerLedgerSheet({
  required List<Customer> customers,
  required List<SalesReport> reports,
  required Map<String, List<SalesLineItem>> items,
  required List<CustomerPayment> payments,
  required String from,
  required String to,
}) {
  final ledgers = <_Ledger>[];
  for (final c in customers) {
    final account = CustomerAccount(c, reports, payments);
    ledgers.add(_Ledger(
      name: c.name,
      opening: c.openingDate == null ? null : (c.openingDate!, c.openingBalance),
      sales: [for (final r in account.reports) if (account.countsFrom == null || r.reportDate.compareTo(account.countsFrom!) >= 0) r],
      payments: account.payments,
      items: items,
    ));
  }
  // Account sales of an agent that isn't a customer (yet): a ledger of their own.
  final known = {for (final c in customers) c.agent};
  final others = <String, List<SalesReport>>{};
  for (final r in reports) {
    final agent = (r.agent ?? '').trim();
    if (agent.isNotEmpty && !known.contains(r.agent)) (others[agent] ??= []).add(r);
  }
  for (final e in others.entries) {
    ledgers.add(_Ledger(name: '${e.key} (not a customer)', sales: e.value..sort((a, b) => a.reportDate.compareTo(b.reportDate)), payments: const [], items: items));
  }

  final shown = [for (final l in ledgers) if (l.inPeriod(from, to)) l]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final period = 'From ${fmtDateDisplay(from)} to ${fmtDateDisplay(to)} · amounts in rand';

  final summaryRows = <SheetRow>[
    SheetRow([
      for (final h in ['Customer', 'Brought forward', 'Gross incl. VAT', 'Deductions incl. VAT', 'Nett receivable', 'Payments', 'Loans', 'Balance'])
        SheetCell.text(h, bold: true, right: h != 'Customer'),
    ], shade: SheetShade.heading),
  ];
  final totals = List<double>.filled(7, 0);
  for (final l in shown) {
    final t = l.totals(from, to);
    final v = [l.balanceBefore(from), t.grossIncl, t.deductionsIncl, t.nett, t.paid, t.loans, l.balanceBefore(from) + t.nett - t.paid - t.loans];
    for (var i = 0; i < v.length; i++) {
      totals[i] += v[i];
    }
    summaryRows.add(SheetRow([SheetCell.text(l.name), for (final x in v) _n(x)]));
  }
  summaryRows.add(SheetRow([const SheetCell.text('Total', bold: true), for (final x in totals) _n(x, bold: true)], shade: SheetShade.total));

  return [
    SheetSection('Customer ledger -- summary', period, [SheetTable(summaryRows, fixed: const [150])]),
    for (final l in shown) SheetSection(l.name, period, [SheetTable(l.rows(from, to), fixed: const [44, 54])]),
  ];
}

SheetCell _n(double v, {bool bold = false}) => SheetCell.number(_r(v), bold: bold);
SheetCell _blank(double v, {bool bold = false}) => v.abs() < 0.005 ? const SheetCell.empty() : _n(v, bold: bold);
double _r(double v) => (v * 100).roundToDouble() / 100;

/// A subcategory as a column heading: "Potatoes Medium C1", "Peppers Red 5kg".
String _subcatLabel(SalesLineItem li, {required bool withProduce}) {
  final produce = kSalesCategories.where((c) => c.key == li.category).firstOrNull?.label ?? li.category;
  final klass = switch (li.effectiveClass) { 'Class 1' => 'C1', 'Class 2' => 'C2', 'Lowest class' => 'Lowest', final k => k };
  return [if (withProduce) produce, li.subcategory ?? 'Other', ?klass].join(' ');
}

class _Totals {
  double grossIncl = 0, deductionsIncl = 0, nett = 0, paid = 0, loans = 0;
}

class _Ledger {
  _Ledger({required this.name, this.opening, required this.sales, required this.payments, required this.items});
  final String name;

  /// (date, balance) the account starts from, when set.
  final (String, double)? opening;
  final List<SalesReport> sales;
  final List<CustomerPayment> payments;

  /// Line items by report id.
  final Map<String, List<SalesLineItem>> items;

  bool _in(String d, String from, String to) => d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
  double _loans(CustomerPayment p) => p.lines.fold<double>(0, (s, l) => s + l.loans);

  bool inPeriod(String from, String to) =>
      sales.any((r) => _in(r.reportDate, from, to)) ||
      payments.any((p) => _in(p.date, from, to)) ||
      (opening != null && _in(opening!.$1, from, to)) ||
      balanceBefore(from).abs() >= 0.01;

  double balanceBefore(String from) {
    var b = 0.0;
    if (opening != null && opening!.$1.compareTo(from) < 0) b += opening!.$2;
    for (final r in sales) {
      if (r.reportDate.compareTo(from) < 0) b += r.nettAmount;
    }
    for (final p in payments) {
      if (p.date.compareTo(from) < 0) b -= p.amount + _loans(p);
    }
    return b;
  }

  _Totals totals(String from, String to) {
    final t = _Totals();
    if (opening != null && _in(opening!.$1, from, to)) t.nett += opening!.$2;
    for (final r in sales.where((r) => _in(r.reportDate, from, to))) {
      t.grossIncl += r.grossTotal + (r.vatOnSales ?? 0);
      t.deductionsIncl += r.commissionBeforeVat + r.vat;
      t.nett += r.nettAmount;
    }
    for (final p in payments.where((p) => _in(p.date, from, to))) {
      t.paid += p.amount;
      t.loans += _loans(p);
    }
    return t;
  }

  List<SheetRow> rows(String from, String to) {
    final periodSales = sales.where((r) => _in(r.reportDate, from, to)).toList();
    final periodPayments = payments.where((p) => _in(p.date, from, to)).toList();
    final withProduce = periodSales.map((r) => r.category).toSet().length > 1;

    // Gross (excl. VAT) per subcategory, per account sale; what the lines
    // don't explain (no lines, rounding) goes in "Other".
    final cols = <String>[];
    final bySale = <String, Map<String, double>>{};
    for (final r in periodSales) {
      final m = <String, double>{};
      for (final li in items[r.id] ?? const <SalesLineItem>[]) {
        final k = _subcatLabel(li, withProduce: withProduce);
        m[k] = (m[k] ?? 0) + li.grossAmount;
      }
      final rest = r.grossTotal - m.values.fold<double>(0, (a, b) => a + b);
      if (rest.abs() >= 0.5) m['Other'] = (m['Other'] ?? 0) + rest;
      bySale[r.reportNumber + (r.id ?? '')] = m;
      for (final k in m.keys) {
        if (!cols.contains(k)) cols.add(k);
      }
    }
    cols.sort((a, b) => a == 'Other' ? 1 : (b == 'Other' ? -1 : _subcatOrder(a).compareTo(_subcatOrder(b))));
    final anyLoans = periodPayments.any((p) => _loans(p).abs() >= 0.005);

    final head = [
      'Date', 'Invoice / ref', ...cols, 'Gross excl. VAT', 'VAT', 'Gross incl. VAT', //
      'Deductions excl. VAT', 'VAT on deductions', 'Deductions incl. VAT', 'Nett receivable', 'Payments', if (anyLoans) 'Loans', 'Balance',
    ];
    final width = head.length;
    final rows = <SheetRow>[
      SheetRow([for (final h in head) SheetCell.text(h, bold: true, right: h != 'Date' && h != 'Invoice / ref')], shade: SheetShade.heading),
    ];
    var balance = balanceBefore(from);
    SheetRow line(String date, String ref, {Map<String, double> subcats = const {}, List<double?> money = const [], double paid = 0, double loans = 0}) {
      return SheetRow([
        SheetCell.text(date),
        SheetCell.text(ref),
        for (final c in cols) _blank(subcats[c] ?? 0),
        for (final v in money) v == null ? const SheetCell.empty() : _n(v),
        if (money.isEmpty) for (var i = 0; i < 7; i++) const SheetCell.empty(),
        _blank(paid),
        if (anyLoans) _blank(loans),
        _n(balance),
      ]);
    }

    rows.add(SheetRow([
      SheetCell.text(fmtDateDisplay(from), bold: true),
      const SheetCell.text('Brought forward', bold: true),
      for (var i = 2; i < width - 1; i++) const SheetCell.empty(),
      _n(balance, bold: true),
    ]));

    // (date, order on the day, row): the opening balance, then account sales, then payments.
    final events = <(String, int, SheetRow Function())>[
      if (opening != null && _in(opening!.$1, from, to))
        (
          opening!.$1,
          0,
          () {
            balance += opening!.$2;
            return line(fmtDateDisplay(opening!.$1), 'Opening balance', money: [null, null, null, null, null, null, opening!.$2]);
          }
        ),
      for (final r in periodSales)
        (
          r.reportDate,
          1,
          () {
            balance += r.nettAmount;
            final vatOnSales = r.vatOnSales ?? 0;
            return line(fmtDateDisplay(r.reportDate), r.reportNumber, subcats: bySale[r.reportNumber + (r.id ?? '')]!, money: [
              r.grossTotal,
              vatOnSales,
              r.grossTotal + vatOnSales,
              r.commissionBeforeVat,
              r.vat,
              r.commissionBeforeVat + r.vat,
              r.nettAmount,
            ]);
          }
        ),
      for (final p in periodPayments)
        (
          p.date,
          2,
          () {
            final loans = _loans(p);
            balance -= p.amount + loans;
            return line(fmtDateDisplay(p.date), 'Payment${(p.method ?? '').isEmpty ? '' : ' (${p.method})'}', paid: p.amount, loans: loans);
          }
        ),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    for (final e in events) {
      rows.add(e.$3());
    }

    final t = totals(from, to);
    double sum(String c) => bySale.values.fold<double>(0, (s, m) => s + (m[c] ?? 0));
    final grossExcl = periodSales.fold<double>(0, (s, r) => s + r.grossTotal);
    final vat = periodSales.fold<double>(0, (s, r) => s + (r.vatOnSales ?? 0));
    final dedExcl = periodSales.fold<double>(0, (s, r) => s + r.commissionBeforeVat);
    final dedVat = periodSales.fold<double>(0, (s, r) => s + r.vat);
    rows.add(SheetRow([
      SheetCell.text(fmtDateDisplay(to), bold: true),
      const SheetCell.text('Total / balance', bold: true),
      for (final c in cols) _n(sum(c), bold: true),
      _n(grossExcl, bold: true),
      _n(vat, bold: true),
      _n(grossExcl + vat, bold: true),
      _n(dedExcl, bold: true),
      _n(dedVat, bold: true),
      _n(dedExcl + dedVat, bold: true),
      _n(t.nett, bold: true),
      _n(t.paid, bold: true),
      if (anyLoans) _n(t.loans, bold: true),
      _n(balance, bold: true),
    ], shade: SheetShade.total));
    return rows;
  }
}

/// Subcategory columns in the produce's own order (sizes small to large,
/// then class), else by name.
int _subcatOrder(String label) {
  for (final c in kSalesCategories) {
    for (final (i, s) in c.subcats.indexed) {
      if (label == s || label.startsWith('$s ') || label.contains(' $s ') || label.endsWith(' $s')) {
        return kSalesCategories.indexOf(c) * 1000 + i * 10 + (label.endsWith('C2') ? 1 : (label.endsWith('Lowest') ? 2 : 0));
      }
    }
  }
  return 1 << 30;
}
