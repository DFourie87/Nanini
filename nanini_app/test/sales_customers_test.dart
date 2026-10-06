import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/sales/sales_customers_models.dart';
import 'package:nanini_app/features/customers/customers_home_screen.dart';
import 'package:nanini_app/features/customers/customers_screen.dart';
import 'package:nanini_app/features/sales/sales_models.dart';
import 'package:nanini_app/features/sales/sales_data.dart';
import 'package:nanini_app/features/sales/sales_repository.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_repository.dart';

class _Repo extends SalesRepository {
  _Repo(this.reports, this.customers, this.payments);
  final List<SalesReport> reports;
  final List<Customer> customers;
  final List<CustomerPayment> payments;
  @override
  Future<List<SalesReport>> fetchReports() async => reports;
  @override
  Future<List<Customer>> fetchCustomers() async => customers;
  @override
  Future<List<CustomerPayment>> fetchCustomerPayments() async => payments;
}

class _Delivery extends DeliveryRepository {
  @override
  Future<List<DeliveryNote>> fetchNotes() async => [];
}

SalesReport report(String n, String date, double nett, {String agent = 'Wenpro Markagente', String category = 'peppers'}) => SalesReport(
    id: n, category: category, agent: agent, reportNumber: n, reportDate: date, grossTotal: nett * 1.2, commissionBeforeVat: 0, vat: 0, nettAmount: nett);

void main() {
  final wenpro = Customer(id: 'w', name: 'Wenpro Markagente', agent: 'Wenpro Markagente', accountNo: '0278929');
  final reports = [
    report('100', '2026-08-01', 500), // before the first one paid: paid before payments were read
    report('56797326', '2026-09-02', 2073.52),
    report('56843576', '2026-09-09', 1007.34),
    report('56885275', '2026-09-16', 2969.17),
    report('300', '2026-10-01', 4000),
    report('400', '2026-10-02', 1000, category: 'butternut'),
    report('999', '2026-10-01', 7777, agent: 'Dapper Agencies'),
  ];
  final payment = CustomerPayment(id: 'p', customerId: 'w', date: '2026-09-30', amount: 6050.03, method: 'transfer', lines: [
    CustomerPaymentLine(reportNumber: '56797326', nett: 2073.52),
    CustomerPaymentLine(reportNumber: '56843576', nett: 1000.00),
    CustomerPaymentLine(reportNumber: '56885275', nett: 2969.17),
    CustomerPaymentLine(reportNumber: '777', nett: 7.34),
  ]);

  test('owed: account sales from the first one paid, not yet on a payment summary', () {
    final a = CustomerAccount(wenpro, reports, [payment], today: DateTime(2026, 10, 5));
    expect(a.countsFrom, '2026-09-02');
    expect(a.open.map((s) => (s.report.reportNumber, s.daysOutstanding)), [('300', 4), ('400', 3)]);
    expect(a.owed, 5000);
    expect(a.queries.map((q) => q.message), [
      'Account sale 56843576: paid R1 000.00, Sales has R1 007.34',
      'Account sale 777 is not in Sales',
    ]);
  });

  test('a few cents off (rounding) is not queried; a sale worth nothing is not unpaid', () {
    final ulsa = Customer(id: 'u', name: 'Universal Leaf South Africa', agent: 'Universal Leaf South Africa');
    final sales = [
      report('ULSA006606', '2026-07-29', 433537.85, agent: 'Universal Leaf South Africa', category: 'tobacco'),
      report('ULSA006607', '2026-07-30', 0, agent: 'Universal Leaf South Africa', category: 'tobacco'),
    ];
    final paid = CustomerPayment(id: 'q', customerId: 'u', date: '2026-07-29', amount: 433537.86,
        lines: [CustomerPaymentLine(reportNumber: 'ULSA006606', nett: 433537.86)]);
    final a = CustomerAccount(ulsa, sales, [paid]);
    expect(a.queries, isEmpty);
    expect(a.open, isEmpty);
    expect(a.owed, 0);
  });

  test('payments from before the account sales in Sales (old years): their lines not queried', () {
    final old = CustomerPayment(id: 'o', customerId: 'w', date: '2021-02-12', amount: 100, lines: [CustomerPaymentLine(reportNumber: '34344', nett: 100)]);
    final a = CustomerAccount(wenpro, reports, [payment, old]);
    expect(a.queries.map((q) => q.line.reportNumber), ['56843576', '777']);
  });

  test('Peppadew: deliveries to the 15th paid at the end of that month, from the 16th the next', () {
    final pep = Customer(id: 'p', name: 'Peppadew', agent: 'Peppadew', terms: 'month_end_15');
    expect([pep.paidBy('2026-04-15'), pep.paidBy('2026-04-16'), pep.paidBy('2026-05-15'), pep.paidBy('2026-12-20')],
        ['2026-04-30', '2026-05-31', '2026-05-31', '2027-01-31']);
    final loads = [
      report('GRV-1', '2026-09-10', 1000, agent: 'Peppadew'), // paid
      report('GRV-2', '2026-09-14', 200, agent: 'Peppadew'),
      report('GRV-3', '2026-09-20', 300, agent: 'Peppadew'),
      report('GRV-4', '2026-10-15', 400, agent: 'Peppadew'),
      report('GRV-5', '2026-10-16', 500, agent: 'Peppadew'),
    ];
    final paid = CustomerPayment(id: 'x', customerId: 'p', date: '2026-09-29', amount: 1000, lines: [CustomerPaymentLine(reportNumber: 'GRV-1', nett: 1000)]);
    final a = CustomerAccount(pep, loads, [paid]);
    expect(a.nextPayments.map((n) => (n.date, n.amount, n.sales.length)),
        [('2026-09-30', 200.0, 1), ('2026-10-31', 700.0, 2), ('2026-11-30', 500.0, 1)]);
    expect(CustomerAccount(wenpro, reports, [payment]).nextPayments, isEmpty); // no terms
  });

  test('no payment summaries yet: nothing owed; an opening balance counts from its date', () {
    expect(CustomerAccount(wenpro, reports, const []).owed, 0);
    final opened = Customer(id: 'w', name: 'Wenpro', agent: 'Wenpro Markagente', openingBalance: 250, openingDate: '2026-10-01');
    expect(CustomerAccount(opened, reports, const []).owed, 5250);
  });

  test('a two-crop account sale saved as a report per crop is paid as one', () {
    final split = [report('303984 (peppers)', '2025-06-09', 100, agent: 'RSA'), report('303984 (butternut)', '2025-06-09', 50, agent: 'RSA')];
    final rsa = Customer(id: 'r', name: 'RSA', agent: 'RSA');
    final paid = CustomerPayment(id: 'q', customerId: 'r', date: '2025-06-20', amount: 150, lines: [CustomerPaymentLine(reportNumber: '303984', nett: 150)]);
    final a = CustomerAccount(rsa, split, [paid]);
    expect(a.owed, 0);
    expect(a.queries, isEmpty);
  });

  testWidgets('the account page lists what to check, unpaid sales and payments', (tester) async {
    final a = CustomerAccount(wenpro, reports, [payment], today: DateTime(2026, 10, 5));
    await tester.pumpWidget(MaterialApp(home: CustomerAccountScreen(account: a)));
    expect(find.text('Account sale 777 is not in Sales'), findsOneWidget);
    expect(find.text('#300 · peppers'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('30 Sep 2026 · transfer'), 200);
    await tester.tap(find.text('30 Sep 2026 · transfer'));
    await tester.pumpAndSettle();
    expect(find.text('R2 073.52'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Customers tab: per agent, the tax year\'s account sales and payments, and owed now', (tester) async {
    final dapper = Customer(id: 'd', name: 'Dapper Agencies', agent: 'Dapper Agencies');
    final data = SalesData(_Repo(reports, [wenpro, dapper], [payment]), delivery: _Delivery());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CustomersScreen(data: data, today: DateTime(2026, 10, 5)))));
    await tester.pumpAndSettle();
    expect(find.text('2026/27 (Mar 2026 - Feb 2027)'), findsOneWidget);
    // Wenpro in 2026/27: R500 + 2 073.52 + 1 007.34 + 2 969.17 + 4 000 + 1 000 = R11 550.03; paid R6 050.03; owed R5 000.
    expect(find.text('Account sales (6)'), findsOneWidget);
    expect(find.text('R11 550.03'), findsOneWidget);
    expect(find.text('R6 050.03'), findsNWidgets(2)); // all agents, Wenpro
    expect(find.text('R5 000.00'), findsNWidgets(2));
    // Dapper: one account sale (R7 777), nothing owed yet (no payment summaries).
    expect(find.text('Account sales (1)'), findsOneWidget);
    expect(find.text('R7 777.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Customers is its own app under Financials; Sales keeps Summary and Reports', (tester) async {
    final data = SalesData(_Repo(reports, [wenpro], [payment]), delivery: _Delivery());
    await tester.pumpWidget(MaterialApp(home: CustomersHomeScreen(data: data)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Customers', findRichText: true), findsWidgets); // the title
    expect(find.text('ALL MARKET AGENTS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
