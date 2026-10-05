import '../../core/formatters.dart';
import 'sales_models.dart';

/// A market agent the farm sells through (Sales > Customers).
class Customer {
  Customer({required this.id, required this.name, required this.agent, this.accountNo, this.emails, this.openingBalance = 0, this.openingDate});
  final String id;
  final String name;

  /// The agent as on its account sales (SalesReport.agent).
  final String agent;
  final String? accountNo;
  final String? emails;
  final double openingBalance;
  final String? openingDate;

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as String,
        name: j['name'] as String,
        agent: j['agent'] as String,
        accountNo: j['account_no'] as String?,
        emails: j['emails'] as String?,
        openingBalance: (j['opening_balance'] as num?)?.toDouble() ?? 0,
        openingDate: j['opening_date'] as String?,
      );
}

/// An account sale on a payment summary (afrekeningstaat).
class CustomerPaymentLine {
  CustomerPaymentLine({required this.reportNumber, this.deliveryNote, this.received, this.sales, this.deductions, this.loans = 0, required this.nett, this.qty});
  final String reportNumber;
  final String? deliveryNote;
  final String? received;
  final double? sales;
  final double? deductions;

  /// Loans the agent took off (part of what settles the account sale).
  final double loans;
  final double nett;
  final double? qty;

  factory CustomerPaymentLine.fromJson(Map<String, dynamic> j) => CustomerPaymentLine(
        reportNumber: j['report_number'] as String,
        deliveryNote: j['delivery_note'] as String?,
        received: j['received'] as String?,
        sales: (j['sales'] as num?)?.toDouble(),
        deductions: (j['deductions'] as num?)?.toDouble(),
        loans: (j['loans'] as num?)?.toDouble() ?? 0,
        nett: (j['nett'] as num).toDouble(),
        qty: (j['qty'] as num?)?.toDouble(),
      );
}

/// A payment summary: what an agent paid on a day, and for which account sales.
class CustomerPayment {
  CustomerPayment({required this.id, required this.customerId, required this.date, required this.amount, this.method, this.fileName, this.bankDate, this.lines = const []});
  final String id;
  final String customerId;
  final String date;
  final double amount;
  final String? method;
  final String? fileName;

  /// The receipt found in the bank, if it has been.
  final String? bankDate;
  final List<CustomerPaymentLine> lines;

  factory CustomerPayment.fromJson(Map<String, dynamic> j) => CustomerPayment(
        id: j['id'] as String,
        customerId: j['customer_id'] as String,
        date: j['pay_date'] as String,
        amount: (j['amount'] as num).toDouble(),
        method: j['method'] as String?,
        fileName: j['file_name'] as String?,
        bankDate: j['bank_date'] as String?,
        lines: [for (final l in (j['customer_payment_lines'] as List?) ?? const []) CustomerPaymentLine.fromJson((l as Map).cast<String, dynamic>())]
          ..sort((a, b) => a.reportNumber.compareTo(b.reportNumber)),
      );
}

/// An account sale not yet paid.
class OpenSale {
  OpenSale(this.report, this.daysOutstanding);
  final SalesReport report;
  final int daysOutstanding;
}

/// Something on a payment summary that doesn't agree with Sales.
class PaymentQuery {
  PaymentQuery(this.payment, this.line, this.message);
  final CustomerPayment payment;
  final CustomerPaymentLine line;
  final String message;
}

/// The account sale's number as the agent prints it: an account sale with
/// two crops is saved as a report per crop ("303984 (peppers)").
String baseReportNumber(String reportNumber) => reportNumber.replaceFirst(RegExp(r'\s*\(.*\)$'), '');

/// What an agent owes: the nett it pays (after commission and the VAT on
/// it) of each account sale not yet on one of its payment summaries.
///
/// Account sales count from the opening date (its opening balance is what
/// was owed then), else from the earliest account sale on a payment
/// summary -- the ones before were paid before payments were read here.
class CustomerAccount {
  CustomerAccount(this.customer, Iterable<SalesReport> reports, Iterable<CustomerPayment> payments, {DateTime? today})
      : reports = reports.where((r) => r.agent == customer.agent).toList()..sort((a, b) => a.reportDate.compareTo(b.reportDate)),
        payments = payments.where((p) => p.customerId == customer.id).toList()..sort((a, b) => b.date.compareTo(a.date)),
        _today = today ?? DateTime.now();

  final Customer customer;
  final List<SalesReport> reports;

  /// Newest first.
  final List<CustomerPayment> payments;
  final DateTime _today;

  late final Map<String, List<SalesReport>> _byNumber = () {
    final m = <String, List<SalesReport>>{};
    for (final r in reports) {
      (m[baseReportNumber(r.reportNumber)] ??= []).add(r);
    }
    return m;
  }();

  late final Set<String> _paidNumbers = {for (final p in payments) for (final l in p.lines) l.reportNumber};

  /// From when account sales count (yyyy-MM-dd), or null: no payment summaries yet.
  late final String? countsFrom = () {
    if (customer.openingDate != null) return customer.openingDate;
    String? first;
    for (final n in _paidNumbers) {
      for (final r in _byNumber[n] ?? const <SalesReport>[]) {
        if (first == null || r.reportDate.compareTo(first) < 0) first = r.reportDate;
      }
    }
    return first;
  }();

  /// Account sales not yet paid, oldest first.
  late final List<OpenSale> open = [
    if (countsFrom != null)
      for (final r in reports)
        if (r.reportDate.compareTo(countsFrom!) >= 0 && !_paidNumbers.contains(baseReportNumber(r.reportNumber)))
          OpenSale(r, _today.difference(DateTime.parse(r.reportDate)).inDays),
  ];

  /// Owed now.
  double get owed => _r((countsFrom == null ? 0 : customer.openingBalance) + open.fold<double>(0, (t, s) => t + s.report.nettAmount));

  /// Lines of payment summaries that don't agree with Sales: an account sale
  /// not in Sales, or paid at a different nett.
  late final List<PaymentQuery> queries = [
    for (final p in payments)
      for (final l in p.lines)
        if (_byNumber[l.reportNumber] == null)
          PaymentQuery(p, l, 'Account sale ${l.reportNumber} is not in Sales')
        else if (((l.nett + l.loans) - _byNumber[l.reportNumber]!.fold<double>(0, (t, r) => t + r.nettAmount)).abs() >= 0.01)
          PaymentQuery(p, l,
              'Account sale ${l.reportNumber}: paid ${fmtRCents(l.nett + l.loans)}, Sales has ${fmtRCents(_byNumber[l.reportNumber]!.fold<double>(0, (t, r) => t + r.nettAmount))}'),
  ];
}

double _r(double v) => (v * 100).roundToDouble() / 100;
