import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nanini_app/features/sales/sales_customers_models.dart';
import 'package:nanini_app/features/sales/sales_models.dart';
import 'package:nanini_app/features/xero/xero_api.dart';
import 'package:nanini_app/features/xero/xero_balances_page.dart';
import 'package:nanini_app/features/xero/xero_sync.dart';

final gn = Customer(id: 'gn', name: 'Grow Green Network', agent: 'Grow Green Network');
final wen = Customer(id: 'w', name: 'Wenpro Markagente', agent: 'Wenpro Markagente');

SalesReport sale(String agent, String number, double nett) => SalesReport(
  category: 'potatoes',
  agent: agent,
  reportNumber: number,
  reportDate: '2026-11-01',
  grossTotal: nett,
  commissionBeforeVat: 0,
  vat: 0,
  nettAmount: nett,
);

XeroMoneyIn pay(String id, String date, double amount, String contact, String invoice) =>
    XeroMoneyIn(id: id, date: date, amount: amount, contact: contact, invoice: invoice);

void main() {
  test('customer payments read from Xero: invoice payments only, not deleted', () {
    final p = xeroInvoicePayments([
      {
        'PaymentID': 'p1',
        'PaymentType': 'ACCRECPAYMENT',
        'Status': 'AUTHORISED',
        'DateString': '2026-11-17T00:00:00',
        'Amount': 157707.0,
        'Invoice': {
          'InvoiceNumber': '103593',
          'Contact': {'Name': 'Grow Green Network'},
        },
      },
      {'PaymentID': 'p2', 'PaymentType': 'ACCPAYPAYMENT', 'Status': 'AUTHORISED', 'DateString': '2026-11-17T00:00:00', 'Amount': 5},
      {'PaymentID': 'p3', 'PaymentType': 'ACCRECPAYMENT', 'Status': 'DELETED', 'DateString': '2026-11-17T00:00:00', 'Amount': 5},
    ]);
    expect([for (final x in p) (x.id, x.date, x.amount, x.contact, x.invoice)], [('p1', '2026-11-17', 157707.0, 'Grow Green Network', '103593')]);
  });

  test('one payment per customer and day; already paid (summary or Xero), pallets and other contacts left out', () {
    final r = xeroCustomerPaymentsToAdd(
      incoming: [
        pay('a', '2026-11-17', 157707.00, 'Grow Green Network', '103593'),
        pay('b', '2026-11-17', 195080.55, 'grow green network', 'IN161813'),
        pay('c', '2026-11-17', 2015.00, 'Grow Green Network', 'IN160836'), // pallets: not an account sale
        pay('d', '2026-11-13', 500.00, 'Wenpro Markagente', '15060-WEN'), // number sent with the agent's tag
        pay('e', '2026-11-13', 900.00, 'Wenpro Markagente', '15061'), // already on a payment summary
        pay('f', '2026-11-12', 100.00, 'Wenpro Markagente', '15062'), // taken in from Xero before
        pay('g', '2026-11-12', 40.00, 'Somebody', 'X1'),
      ],
      customers: [gn, wen],
      reports: [
        sale('Grow Green Network', '103593', 157707.00),
        sale('Grow Green Network', 'IN161813', 195080.55),
        sale('Wenpro Markagente', '15060', 500),
        sale('Wenpro Markagente', '15061', 900),
        sale('Wenpro Markagente', '15062', 100),
      ],
      payments: [
        CustomerPayment(
          id: '1',
          customerId: 'w',
          date: '2026-11-13',
          amount: 900,
          lines: [CustomerPaymentLine(reportNumber: '15061', nett: 900)],
        ),
        CustomerPayment(id: '2', customerId: 'w', date: '2026-11-12', amount: 100, fileName: 'Xero: f'),
      ],
    );
    expect(
      [
        for (final p in r.add) (p.customer.id, p.date, p.amount, [for (final l in p.lines) l.reportNumber].join(',')),
      ],
      [
        ('w', '2026-11-13', 500.0, '15060'),
        ('gn', '2026-11-17', 352787.55, '103593,IN161813'),
      ],
    );
    expect(r.add.last.fileName, 'Xero: a,b');
    expect(r.alreadyIn, 2);
    expect(r.notSales, {'IN160836': 2015.0});
    expect(r.notCustomers, {'Somebody': 40.0});
  });

  testWidgets('the page: Customer payments from Xero takes the new ones in', (tester) async {
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/Contacts')) return http.Response(jsonEncode({'Contacts': []}), 200);
      if (req.url.path.endsWith('/Payments')) {
        return http.Response(
          jsonEncode({
            'Payments': [
              {
                'PaymentID': 'p1',
                'PaymentType': 'ACCRECPAYMENT',
                'Status': 'AUTHORISED',
                'DateString': '2026-11-17T00:00:00',
                'Amount': 157707.0,
                'Invoice': {
                  'InvoiceNumber': '103593',
                  'Contact': {'Name': 'Grow Green Network'},
                },
              },
            ],
          }),
          200,
        );
      }
      return http.Response(jsonEncode({}), 200);
    });
    final api = XeroApi(
      client: client,
      store: MemoryXeroStore()
        ..connection = XeroConnection(clientId: 'c', accessToken: 'a', refreshToken: 'r', expiresAt: DateTime.utc(2030), tenantId: 't', tenantName: 'Nanini'),
      wait: (_) async {},
    );
    final added = <XeroCustomerPaymentToAdd>[];
    await tester.pumpWidget(
      MaterialApp(
        home: XeroBalancesPage(
          api: api,
          loadHub: () async => XeroHubSide(
            suppliersDue: const {},
            customersOwed: const {},
            suppliers: const [],
            payments: const [],
            customers: [gn],
            reports: [sale('Grow Green Network', '103593', 157707.00)],
          ),
          addCustomerPayment: (p) async => added.add(p),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('xero_take_customer_payments')));
    await tester.pumpAndSettle();
    expect(find.text('Take 1 customer payment(s) from Xero?'), findsOneWidget);
    await tester.tap(find.text('Take them in'));
    await tester.pumpAndSettle();
    expect([for (final p in added) (p.customer.id, p.date, p.amount, p.fileName)], [('gn', '2026-11-17', 157707.0, 'Xero: p1')]);
  });
}
