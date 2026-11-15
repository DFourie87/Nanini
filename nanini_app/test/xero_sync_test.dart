import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nanini_app/features/xero/xero_balances_page.dart';
import 'package:nanini_app/features/suppliers/suppliers_models.dart';
import 'package:nanini_app/features/xero/xero_api.dart';
import 'package:nanini_app/features/xero/xero_sync.dart';

XeroMoneyOut out(String id, String date, double amount, String contact, [String what = 'Bill']) =>
    XeroMoneyOut(id: id, date: date, amount: amount, contact: contact, what: what);

SupplierPayment pay(String id, String supplier, String date, double amount, [String? notes]) =>
    SupplierPayment(id: id, supplierId: supplier, date: date, amount: amount, notes: notes);

void main() {
  test('Xero dates: DateString, or the /Date(ms)/ form', () {
    expect(xeroDate({'DateString': '2026-10-06T00:00:00'}), '2026-10-06');
    expect(xeroDate({'Date': '/Date(1791244800000+0000)/'}), '2026-10-06');
    expect(xeroDate({'Date': 'nonsense'}), isNull);
  });

  test('bill payments and spend money read from Xero; deleted ones and other payments left out', () {
    final bills = xeroBillPayments([
      {'PaymentID': 'p1', 'PaymentType': 'ACCPAYPAYMENT', 'Status': 'AUTHORISED', 'DateString': '2026-10-06T00:00:00', 'Amount': 108415.10,
        'Invoice': {'InvoiceNumber': 'IN002886', 'Contact': {'Name': 'Drip Irrigation'}}},
      {'PaymentID': 'p2', 'PaymentType': 'ACCRECPAYMENT', 'Status': 'AUTHORISED', 'DateString': '2026-10-06T00:00:00', 'Amount': 5},
      {'PaymentID': 'p3', 'PaymentType': 'ACCPAYPAYMENT', 'Status': 'DELETED', 'DateString': '2026-10-06T00:00:00', 'Amount': 5},
    ]);
    expect([for (final b in bills) (b.id, b.date, b.amount, b.contact, b.what)], [('p1', '2026-10-06', 108415.10, 'Drip Irrigation', 'Bill IN002886')]);
    final spend = xeroSpendMoney([
      {'BankTransactionID': 't1', 'Type': 'SPEND-OVERPAYMENT', 'Status': 'AUTHORISED', 'DateString': '2026-11-08T00:00:00', 'Total': 11172.76, 'Contact': {'Name': 'SRT Fuel'}},
      {'BankTransactionID': 't2', 'Type': 'RECEIVE', 'Status': 'AUTHORISED', 'DateString': '2026-11-08T00:00:00', 'Total': 9, 'Contact': {'Name': 'X'}},
      {'BankTransactionID': 't3', 'Type': 'SPEND', 'Status': 'AUTHORISED', 'DateString': '2026-11-08T00:00:00', 'Total': 50, 'Contact': {'Name': ''}},
    ]);
    expect([for (final s in spend) (s.id, s.what, s.amount)], [('t1', 'Overpayment', 11172.76)]);
  });

  test('balances side by side: differences first; a Xero contact with a balance that isn\'t in the hub too', () {
    final rows = xeroBalanceRows(
      xero: [
        XeroContactBalance('Laeveld Agrochem', 110228, 0),
        XeroContactBalance('Omnia', 81637.50, 0),
        XeroContactBalance('Botha Roodt Johannesburg', 0, 553016.07),
        XeroContactBalance('PXD Plastics (Pty) Ltd', 12753.95, 0),
        XeroContactBalance('Empty', 0, 0),
      ],
      suppliersDue: {'Laeveld Agrochem': 58793, 'Omnia ': 81637.50, 'Polokwane Municipality - 0000000885': -21829.85},
      customersOwed: {'Botha Roodt Johannesburg': 553016.07},
    );
    expect([for (final r in rows) (r.name, r.kind, r.xero, r.hub, r.differs)], [
      ('Laeveld Agrochem', 'Supplier', 110228.0, 58793.0, true),
      ('Polokwane Municipality - 0000000885', 'Supplier', null, -21829.85, true),
      ('PXD Plastics (Pty) Ltd', 'Only in Xero', 12753.95, null, true),
      ('Botha Roodt Johannesburg', 'Customer', 553016.07, 553016.07, false),
      ('Omnia', 'Supplier', 81637.50, 81637.50, false),
    ]);
    expect(rows.first.difference, 51435.0);
  });

  test('supplier payments from Xero: the ones the bank already brought are left out, also when Xero split them', () {
    final eskom = Supplier(id: 'e', name: 'Eskom - 5851646746');
    final vkb = Supplier(id: 'v', name: 'VKB');
    final srt = Supplier(id: 's', name: 'SRT Fuel');
    final novon = Supplier(id: 'n', name: 'Novon');
    final r = xeroSupplierPaymentsToAdd(
      out: [
        // Eskom 28 Sep: one bank payment, in Xero part bill, part spend money.
        out('a', '2026-09-28', 5373.34, 'Eskom - 5851646746'),
        out('b', '2026-09-28', 4840.01, 'Eskom - 5851646746', 'Spend money'),
        // VKB 7 Sep: many bills, R0.55 short of the bank payment (rounding).
        out('c', '2026-09-07', 29000.00, 'VKB'),
        out('d', '2026-09-07', 873.45, 'VKB'),
        // SRT's overpayment: in the bank a day later.
        out('e', '2026-11-08', 11172.76, 'srt fuel', 'Overpayment'),
        // Taken in from Xero before.
        out('f', '2026-11-10', 500, 'Novon'),
        // New: paid in Xero, not in the hub.
        out('g', '2026-11-12', 845.57, 'Novon'),
        // Not a hub supplier.
        out('h', '2026-11-12', 2000, 'Wages'),
        out('i', '2026-11-13', 1000, 'Wages'),
      ],
      suppliers: [eskom, vkb, srt, novon],
      payments: [
        pay('1', 'e', '2026-09-28', 10213.35),
        pay('2', 'v', '2026-09-07', 29874.00),
        pay('3', 's', '2026-11-09', 11172.76),
        pay('4', 'n', '2026-11-10', 500, 'From Xero: Bill X (Xero f)'),
      ],
    );
    expect([for (final p in r.add) (p.supplier.name, p.money.id, p.money.amount)], [('Novon', 'g', 845.57)]);
    expect(r.add.single.notes, 'From Xero: Bill (Xero g)');
    expect(r.alreadyIn, 6);
    expect(r.notSuppliers, {'Wages': 3000.0});
  });

  testWidgets('the page: balances side by side, and Xero\'s new supplier payments taken in once', (tester) async {
    final client = MockClient((req) async {
      final path = req.url.path;
      if (path.endsWith('/Contacts')) {
        return http.Response(jsonEncode({
          'Contacts': [
            {'Name': 'Laeveld Agrochem', 'Balances': {'AccountsPayable': {'Outstanding': 110228.0}}},
            {'Name': 'Novon', 'Balances': {'AccountsPayable': {'Outstanding': 11552.46}}},
          ]
        }), 200);
      }
      if (path.endsWith('/Payments')) {
        return http.Response(jsonEncode({
          'Payments': [
            {'PaymentID': 'p9', 'PaymentType': 'ACCPAYPAYMENT', 'Status': 'AUTHORISED', 'DateString': '2026-11-12T00:00:00', 'Amount': 845.57,
              'Invoice': {'InvoiceNumber': 'OBC-NOVON', 'Contact': {'Name': 'Novon'}}},
          ]
        }), 200);
      }
      return http.Response(jsonEncode({'BankTransactions': []}), 200);
    });
    final api = XeroApi(
        client: client,
        store: MemoryXeroStore()
          ..connection = XeroConnection(
              clientId: 'c', accessToken: 'a', refreshToken: 'r', expiresAt: DateTime.utc(2030), tenantId: 't', tenantName: 'Nanini'),
        wait: (_) async {});
    final novon = Supplier(id: 'n', name: 'Novon');
    final added = <XeroPaymentToAdd>[];
    await tester.pumpWidget(MaterialApp(
        home: XeroBalancesPage(
      api: api,
      loadHub: () async => XeroHubSide(
          suppliersDue: {'Laeveld Agrochem': 58793, 'Novon': 11552.46}, customersOwed: const {}, suppliers: [novon], payments: const []),
      addPayment: (p) async => added.add(p),
    )));
    await tester.pumpAndSettle();
    expect(find.text('1 differ'), findsOneWidget);
    expect(find.textContaining('R51 435.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('xero_take_payments')));
    await tester.pumpAndSettle();
    expect(find.text('Take 1 payment(s) from Xero?'), findsOneWidget);
    await tester.tap(find.text('Take them in'));
    await tester.pumpAndSettle();
    expect([for (final p in added) (p.supplier.id, p.money.date, p.money.amount)], [('n', '2026-11-12', 845.57)]);
  });
}
