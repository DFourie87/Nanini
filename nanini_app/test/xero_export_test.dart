import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/auth/app_user.dart';
import 'package:nanini_app/core/auth/session.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/sales/sales_customers_models.dart';
import 'package:nanini_app/features/sales/sales_models.dart';
import 'package:nanini_app/features/suppliers/suppliers_models.dart';
import 'package:nanini_app/features/xero/xero_export.dart';
import 'package:nanini_app/features/xero/xero_export_screen.dart';
import 'package:provider/provider.dart';

SalesReport report(String id, String category, String agent, String no, String date,
        {required double gross, double commission = 0, double vat = 0, double? vatOnSales, required double nett}) =>
    SalesReport(
        id: id, category: category, agent: agent, reportNumber: no, reportDate: date, grossTotal: gross,
        commissionBeforeVat: commission, vat: vat, vatOnSales: vatOnSales, nettAmount: nett);

void main() {
  final customers = [
    Customer(id: 'c1', name: 'Botha Roodt Johannesburg', agent: 'Botha Roodt'),
    Customer(id: 'c2', name: 'Peppadew International', agent: 'Peppadew', terms: 'month_end_15'),
  ];

  test('an account sale at nett: produce gross, each deduction with its VAT to its expense, pallets paid for', () {
    final r = report('r1', 'potatoes', 'Botha Roodt', '15060', '2026-10-28', gross: 213500, commission: 24001.62, vat: 3600.29, nett: 185898.09);
    final inv = xeroInvoices(
      reports: [r],
      lineItems: {
        'r1': [
          SalesLineItem(reportId: 'r1', category: 'potatoes', subcategory: 'Large', klass: 'Class 1', description: '1,320 bags @ R66.67/bags', grossAmount: 88000),
          SalesLineItem(reportId: 'r1', category: 'potatoes', subcategory: 'Medium', klass: 'Class 1', grossAmount: 125500),
        ],
      },
      deductions: {
        'r1': const [
          XeroDeduction(reportId: 'r1', ord: 1, label: 'MARKET FEES', amount: 10675, vat: 1601.27),
          XeroDeduction(reportId: 'r1', ord: 2, label: 'POTATO ADMINISTRATION', amount: 504.09, vat: 75.62),
          XeroDeduction(reportId: 'r1', ord: 3, label: 'AGENT COMMISSION', amount: 12810, vat: 1921.52),
          XeroDeduction(reportId: 'r1', ord: 4, label: 'BANK CHARGES', amount: 12.53, vat: 1.88),
          XeroDeduction(reportId: 'r1', ord: 5, label: 'Pallets paid for: 31 PALLET @ R65 INCL (IN160836)', amount: -1752.17, vat: -262.83, kind: 'pallets'),
        ],
      },
      customers: customers,
    ).single;
    expect(inv.contact, 'Botha Roodt Johannesburg');
    expect(inv.total, 185898.09 + 2015.00);
    expect(inv.deductionsByLine, isTrue);
    expect([for (final l in inv.lines) (l.amount, l.account, l.taxType, l.tax)], [
      (125500.0, '1000/800', kZeroRated, null),
      (88000.0, '1000/800', kZeroRated, null),
      (-10675.0, '3490/000', kStandardPurchases, -1601.27),
      (-504.09, '3490/000', kStandardPurchases, -75.62),
      (-12810.0, '3490/000', kStandardPurchases, -1921.52),
      (-12.53, '3200/000', kStandardPurchases, -1.88),
      (1752.17, '4280/000', kStandardSales, 262.83),
    ]);
    expect(inv.lines[1].description, '1,320 bags @ R66.67/bags');
    expect(inv.lines[0].description, 'Potatoes Medium Class 1');

    final rows = xeroInvoiceRows([inv]);
    expect(rows.first, kXeroInvoiceHeader);
    final h = {for (var i = 0; i < kXeroInvoiceHeader.length; i++) kXeroInvoiceHeader[i]: i};
    expect(rows[1][h['*InvoiceNumber']!], '15060');
    expect(rows[1][h['*InvoiceDate']!], '28/10/2026');
    expect(rows[1][h['*DueDate']!], '04/11/2026');
    expect(rows[3][h['*UnitAmount']!], '-10675.00');
    expect(rows[3][h['TaxAmount']!], '-1601.27');
    expect(rows[1][h['TaxAmount']!], '');
  });

  test('tobacco: 15% VAT exactly as on the invoice; packing and handling to Packaging', () {
    final r = report('t', 'tobacco', 'Universal Leaf South Africa', 'ULSA006667', '2026-09-01',
        gross: 1000.03, vatOnSales: 150.01, commission: 30, vat: 4.5, nett: 1115.54);
    final inv = xeroInvoices(
      reports: [r],
      lineItems: {
        't': [
          SalesLineItem(reportId: 't', category: 'tobacco', subcategory: 'F2', grossAmount: 500.02),
          SalesLineItem(reportId: 't', category: 'tobacco', subcategory: 'F4', grossAmount: 500.01),
        ],
      },
      deductions: {
        't': const [
          XeroDeduction(reportId: 't', ord: 1, label: 'Packing Material', amount: 20, vat: 3),
          XeroDeduction(reportId: 't', ord: 2, label: 'Handling Fee', amount: 10, vat: 1.5),
        ],
      },
      customers: customers,
    ).single;
    expect([for (final l in inv.lines) (l.account, l.taxType, l.tax)], [
      ('1200/000', kStandardSales, 75.01),
      ('1200/000', kStandardSales, 75.0),
      ('4280/000', kStandardPurchases, -3.0),
      ('4280/000', kStandardPurchases, -1.5),
    ]);
    expect(inv.total, 1115.54);
  });

  test('deductions not read line by line: one line; Peppadew by its terms; no commission, no line', () {
    final invs = xeroInvoices(
      reports: [
        report('a', 'peppers', 'Wenpro', '1', '2026-09-03', gross: 1000, commission: 100, vat: 15, nett: 885),
        report('b', 'peppadew', 'Peppadew', 'P-1', '2026-09-20', gross: 2000, nett: 2000),
      ],
      lineItems: const {},
      deductions: const {},
      customers: customers,
    );
    expect(invs[0].contact, 'Wenpro');
    expect(invs[0].deductionsByLine, isFalse);
    expect([for (final l in invs[0].lines) (l.description, l.amount, l.account, l.tax)], [
      ('Account sale 1', 1000.0, '1000/400', null),
      ('Commission and charges (account sale 1)', -100.0, '3490/000', -15.0),
    ]);
    expect(invs[0].total, 885);
    expect(invs[1].lines.length, 1);
    expect(invs[1].dueDate, '2026-10-31');
    expect(invs[1].deductionsByLine, isTrue);
  });

  test('the same number at two agents: told apart', () {
    final invs = xeroInvoices(reports: [
      report('a', 'potatoes', 'Botha Roodt', '100', '2026-09-03', gross: 1, nett: 1),
      report('b', 'potatoes', 'Wenpro', '100', '2026-09-03', gross: 1, nett: 1),
    ], lineItems: const {}, deductions: const {}, customers: customers);
    expect({for (final i in invs) i.number}, {'100-BOT', '100-WEN'});
  });

  test('which expense a deduction goes to', () {
    expect(xeroDeductionAccount('Agent Commission'), '3490/000');
    expect(xeroDeductionAccount('MARKET FEES'), '3490/000');
    expect(xeroDeductionAccount('Bank Charges'), '3200/000');
    expect(xeroDeductionAccount('Packing Charges'), '4280/000');
    expect(xeroDeductionAccount('Handling Fee'), '4280/000');
    expect(xeroDeductionAccount('Transport'), '4800/000');
    expect(xeroMoney(-0.001), '0.00');
  });

  test('contacts: customers with the contact person, suppliers with bank details and terms', () {
    final c = xeroCustomerRows([Customer(id: '1', name: 'Wenpro Markagente', agent: 'W', accountNo: '92220')],
        [MarketAgent(id: 'm', name: 'Wenpro Markagente', attention: 'Jan')]);
    final h = {for (var i = 0; i < kXeroContactHeader.length; i++) kXeroContactHeader[i]: i};
    expect(c.first.length, 73);
    expect((c[1][h['*ContactName']!], c[1][h['AccountNumber']!], c[1][h['POAttentionTo']!]), ('Wenpro Markagente', '92220', 'Jan'));

    final s = xeroSupplierRows([
      Supplier(id: '1', name: 'Test Supplier', email: 'a@test.co.za', address: '1 Main Rd\nTown, Area\n0001\nExtra', bankName: 'ABSA',
          bankAccountHolder: 'Test', bankAccountNo: '000111', bankBranchCode: '632005', vatNo: '4000000000',
          termsKind: PaymentTerms.daysFromStatement, termsDays: 30),
    ]);
    final row = s[1];
    expect([row[h['POAddressLine1']!], row[h['POAddressLine2']!], row[h['POAddressLine3']!], row[h['POAddressLine4']!], row[h['POCountry']!]],
        ['1 Main Rd', 'Town', 'Area', '0001, Extra', 'South Africa']);
    expect((row[h['BankAccountNumber']!], row[h['BankAccountParticulars']!], row[h['TaxNumber']!]), ('000111', 'ABSA branch 632005', '4000000000'));
    expect((row[h['DueDateBillDay']!], row[h['DueDateBillTerm']!]), ('30', 'DAYSAFTERBILLMONTH'));
  });

  testWidgets('the screen: a card per export the user may make', (tester) async {
    final saved = <String, Uint8List>{};
    Future<void> pump(AppUser user) async {
      final session = Session()..currentUser = user;
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: session, child: MaterialApp(home: XeroExportScreen(save: (n, b) async {
            saved[n] = b;
            return true;
          }))));
      await tester.pumpAndSettle();
    }

    await pump(AppUser(id: 'a', username: 'admin', displayName: 'Admin', role: 'admin'));
    expect(find.text('Sales invoices'), findsOneWidget);
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Suppliers'), findsOneWidget);
    expect(find.byKey(const Key('xero_from')), findsOneWidget);

    await pump(AppUser(id: 'b', username: 'clerk', displayName: 'Clerk', role: 'user', modules: const ['suppliers']));
    expect(find.text('Sales invoices'), findsNothing);
    expect(find.text('Suppliers'), findsOneWidget);
    expect(const CsvToListConverter().convert('a,b').first, ['a', 'b']);
  });
}
