import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/sales/sales_customers_models.dart';
import 'package:nanini_app/features/sales/sales_customers_screen.dart';
import 'package:nanini_app/features/sales/sales_models.dart';

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
}
