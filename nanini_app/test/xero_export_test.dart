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

  test('an account sale at nett: produce gross, each deduction with its VAT to its expense; pallets paid for on their own invoice', () {
    final r = report('r1', 'potatoes', 'Botha Roodt', '15060', '2026-10-28', gross: 213500, commission: 24001.62, vat: 3600.29, nett: 185898.09);
    final invs = xeroInvoices(
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
    );
    expect(invs.length, 2);
    final inv = invs[0];
    expect(inv.contact, 'Botha Roodt Johannesburg');
    expect(inv.total, 185898.09);
    final pallets = invs[1];
    expect((pallets.number, pallets.contact, pallets.reference, pallets.total), ('IN160836', 'Botha Roodt Johannesburg', 'Pallets with account sale 15060', 2015.0));
    expect([for (final l in pallets.lines) (l.amount, l.account, l.taxType, l.tax)], [(1752.17, '4280/000', kStandardSales, 262.83)]);
    expect(inv.deductionsByLine, isTrue);
    expect([for (final l in inv.lines) (l.amount, l.account, l.taxType, l.tax)], [
      (125500.0, '1000/800', kZeroRated, null),
      (88000.0, '1000/800', kZeroRated, null),
      (-10675.0, '3490/000', kStandardPurchases, -1601.27),
      (-504.09, '3490/000', kStandardPurchases, -75.62),
      (-12810.0, '3490/000', kStandardPurchases, -1921.52),
      (-12.53, '3200/000', kStandardPurchases, -1.88),
    ]);
    expect(inv.lines[1].description, '1,320 bags @ R66.67/bags');
    expect(inv.lines[0].description, 'Potatoes Medium Class 1');

    final rows = xeroInvoiceRows(invs);
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

  test('supplier invoices as Xero bills: a line per item against its account, credit notes minus', () {
    final omnia = Supplier(id: 's1', name: 'Omnia', category: '3740 - Fertilizer', termsKind: PaymentTerms.daysFromStatement, termsDays: 30);
    final dealer = Supplier(id: 's2', name: 'Tractor Dealer', category: '5510/100');
    final docs = [
      SupplierDoc(id: 'd1', supplierId: 's1', kind: SupplierDocKind.invoice, date: '2026-09-10', amount: 1150, reference: 'IN1', vatAmount: 150),
      SupplierDoc(id: 'd2', supplierId: 's1', kind: SupplierDocKind.creditNote, date: '2026-09-12', amount: 115, reference: 'CN1', vatAmount: 15),
      SupplierDoc(id: 'd3', supplierId: 's2', kind: SupplierDocKind.invoice, date: '2026-09-15', amount: 115000, reference: 'T1', vatAmount: 15000),
      SupplierDoc(id: 'd4', supplierId: 's1', kind: SupplierDocKind.invoice, date: '2026-08-31', amount: 500, reference: 'OLD'),
      SupplierDoc(id: 'd5', supplierId: 's1', kind: SupplierDocKind.invoice, date: '2026-09-20', amount: 300, reference: 'IN2'),
    ];
    final lines = [
      DocLine(id: 'l1', docId: 'd1', lineNo: 1, description: 'Fertilizer 2:3:4', excl: 600, vat: 90),
      DocLine(id: 'l2', docId: 'd1', lineNo: 2, description: 'Transport', excl: 400, vat: 60, glAccount: '4800/000'),
    ];
    final accounts = [SupplierAccount(omnia, docs, const []), SupplierAccount(dealer, docs, const [])];
    final bills = xeroBills(purchasesFor(accounts, lines, const [], '2026-08-01', '2026-09-30'));
    expect([for (final b in bills) b.number], ['IN1', 'CN1', 'T1', 'IN2']); // August's is in Xero's opening balances
    expect([for (final l in bills[0].lines) (l.excl, l.vat, l.account)], [(600.0, 90.0, '3740/000'), (400.0, 60.0, '4800/000')]);
    expect(bills[0].dueDate, '2026-10-31');
    expect(bills[1].total, -115.0);
    final rows = xeroBillRows(bills);
    final h = {for (var i = 0; i < kXeroBillHeader.length; i++) kXeroBillHeader[i]: i};
    expect(rows.first, kXeroBillHeader);
    expect([rows[1][h['*ContactName']!], rows[1][h['*InvoiceDate']!], rows[1][h['*UnitAmount']!], rows[1][h['*TaxType']!], rows[1][h['TaxAmount']!]],
        ['Omnia', '10/09/2026', '600.00', kStandardPurchases, '90.00']);
    expect([rows[3][h['*UnitAmount']!], rows[3][h['TaxAmount']!]], ['-100.00', '-15.00']);
    expect([rows[4][h['*AccountCode']!], rows[4][h['*TaxType']!]], ['5510/100', kCapitalPurchases]);
    // Without an account: on the fallback (Suspense) when asked.
    final loose = Supplier(id: 's3', name: 'VKB');
    final vkb = xeroBills(purchasesFor([SupplierAccount(loose, [
      SupplierDoc(id: 'v', supplierId: 's3', kind: SupplierDocKind.invoice, date: '2026-09-05', amount: 115, reference: 'V1', vatAmount: 15),
    ], const [])], const [], const [], '2026-09-01', '2026-09-30'));
    expect(xeroBillRows(vkb)[1][h['*AccountCode']!], '');
    expect(xeroBillRows(vkb, fallbackAccount: kXeroSuspense)[1][h['*AccountCode']!], '9990/000');
    // A whole Omnia invoice as one line (VAT only on its transport): two lines.
    final whole = xeroBills(purchasesFor([SupplierAccount(omnia, [
      SupplierDoc(id: 'o', supplierId: 's1', kind: SupplierDocKind.invoice, date: '2026-10-16', amount: 81637.5, reference: 'OF27', vatAmount: 1138.5),
    ], const [])], const [], const [], '2026-10-01', '2026-10-31'));
    final parts = xeroBillRows(whole).skip(1).toList();
    expect([for (final r in parts) (r[h['*UnitAmount']!], r[h['*TaxType']!], r[h['TaxAmount']!])],
        [('7590.00', kStandardPurchases, '1138.50'), ('72909.00', kNoVat, '')]);
    // Interest on an account (the municipality's statement lines): Finance Charges.
    final muni = Supplier(id: 'm', name: 'Polokwane Municipality', category: '4290 - Rates & Taxes');
    final mlines = purchasesFor([SupplierAccount(muni, [
      SupplierDoc(id: 'md', supplierId: 'm', kind: SupplierDocKind.invoice, date: '2026-10-30', amount: 184.64, reference: 'M1'),
    ], const [])], [
      DocLine(id: 'a', docId: 'md', lineNo: 1, description: 'Debit Sms Notice Fee October', excl: 42.05, vat: 6.31),
      DocLine(id: 'b', docId: 'md', lineNo: 2, description: 'Rates Agricultural', excl: 134.93, vat: 0),
      DocLine(id: 'c', docId: 'md', lineNo: 3, description: 'Interest', excl: 1.35, vat: 0),
    ], const [], '2026-10-01', '2026-10-31');
    expect([for (final l in mlines) l.account], ['4290/000', '4290/000', '3680/000']);
    // Eskom's "Interest on overdue account" (no VAT): Finance Charges, No VAT -- even with the item remembered elsewhere.
    final eskom = Supplier(id: 'e', name: 'Eskom - 8621974700', category: '3650 - Electricity & Water');
    final ebills = xeroBills(purchasesFor([SupplierAccount(eskom, [
      SupplierDoc(id: 'ed', supplierId: 'e', kind: SupplierDocKind.invoice, date: '2026-10-05', amount: 1164.23, reference: 'E1'),
    ], const [])], [
      DocLine(id: 'e1', docId: 'ed', lineNo: 1, description: 'Charges', excl: 1000, vat: 150),
      DocLine(id: 'e2', docId: 'ed', lineNo: 2, description: 'Interest on overdue account', excl: 14.23, vat: 0),
    ], [GlRule(supplierId: 'e', item: 'interest on overdue account', glAccount: '3650/000')], '2026-10-01', '2026-10-31'));
    final erows = xeroBillRows(ebills).skip(1).toList();
    expect([for (final r in erows) (r[h['*AccountCode']!], r[h['*TaxType']!], r[h['TaxAmount']!])],
        [('3650/000', kStandardPurchases, '150.00'), ('3680/000', kNoVat, '')]);
    // No VAT read: No VAT, the whole amount.
    expect([rows[5][h['*UnitAmount']!], rows[5][h['*TaxType']!], rows[5][h['TaxAmount']!]], ['300.00', kNoVat, '']);
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
    expect(find.text('Supplier invoices'), findsOneWidget);
    expect(find.byKey(const Key('xero_from')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Suppliers'), 300);
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Suppliers'), findsOneWidget);

    await pump(AppUser(id: 'b', username: 'clerk', displayName: 'Clerk', role: 'user', modules: const ['suppliers']));
    expect(find.text('Sales invoices'), findsNothing);
    expect(find.text('Supplier invoices'), findsOneWidget);
    expect(find.text('Suppliers'), findsOneWidget);
    expect(const CsvToListConverter().convert('a,b').first, ['a', 'b']);
  });

  test('only what is not in Xero yet: new ones, changed since sent, already sent', () {
    // (document id, invoice total): r1 gives two Xero invoices (its pallets on their own).
    final items = [('r1', 100.0), ('r1', 20.15), ('r2', 50.0), ('r3', 75.0), ('r4', 10.0)];
    final split = xeroNotSentYet(items, (i) => i.$1, (i) => i.$2, {
      'r1': const XeroSent('2026-11-12T08:00:00Z', 120.15), // as sent
      'r2': const XeroSent('2026-11-12T08:00:00Z', 55.0), // changed since
      'r3': const XeroSent('2026-11-12T08:00:00Z', null), // marked from Xero's list: not compared
    });
    expect(split.fresh, [('r4', 10.0)]);
    expect(split.changed, [('r2', 50.0)]);
    expect(split.alreadySent, 2);
    expect(xeroTotalsByDoc(items, (i) => i.$1, (i) => i.$2), {'r1': 120.15, 'r2': 50.0, 'r3': 75.0, 'r4': 10.0});
  });

  testWidgets('the screen: invoices and bills only what is not in Xero yet, unless unticked', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final session = Session()..currentUser = AppUser(id: 'a', username: 'admin', displayName: 'Admin', role: 'admin');
    await tester.pumpWidget(ChangeNotifierProvider.value(value: session, child: MaterialApp(home: XeroExportScreen(save: (n, b) async => true))));
    await tester.pumpAndSettle();
    for (final k in ['xero_invoices_new_only', 'xero_bills_new_only']) {
      expect(tester.widget<CheckboxListTile>(find.byKey(Key(k))).value, isTrue, reason: k);
    }
    expect(find.text('Only what is not in Xero yet'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('xero_bills_new_only')));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('xero_bills_new_only'))).value, isFalse);
    expect(find.textContaining('they would be there twice'), findsOneWidget);
  });

  testWidgets('the screen: all customers / suppliers at once, or one picked', (tester) async {
    final session = Session()..currentUser = AppUser(id: 'a', username: 'admin', displayName: 'Admin', role: 'admin');
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
            home: XeroExportScreen(
          save: (n, b) async => true,
          loadCustomers: () async => customers,
          loadSuppliers: () async => [Supplier(id: 's1', name: 'Omnia'), Supplier(id: 's2', name: 'Noord Tranvaal Boere')],
        ))));
    await tester.pumpAndSettle();
    expect(find.text('All customers'), findsOneWidget);
    expect(find.text('All suppliers'), findsOneWidget);
    expect(find.text('Save invoices CSV'), findsOneWidget);

    // One customer: its name on the buttons.
    await tester.tap(find.byKey(const Key('xero_customer')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('xero_pick_search')), 'pepp');
    await tester.pumpAndSettle();
    expect(find.text('Botha Roodt Johannesburg'), findsNothing);
    await tester.tap(find.text('Peppadew International'));
    await tester.pumpAndSettle();
    expect(find.text('Save invoices CSV: Peppadew International'), findsOneWidget);
    expect(find.text('All customers'), findsNothing);

    // One supplier, then back to all of them.
    await tester.tap(find.byKey(const Key('xero_supplier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Noord Tranvaal Boere'));
    await tester.pumpAndSettle();
    expect(find.text('Save supplier invoices CSV: Noord Tranvaal Boere'), findsOneWidget);
    await tester.tap(find.byKey(const Key('xero_supplier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All suppliers').last);
    await tester.pumpAndSettle();
    expect(find.text('Save supplier invoices CSV'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('payments to match in Xero: each receipt with the invoices it paid, newest first', () {
    final pays = [
      CustomerPayment(id: 'p1', customerId: 'c1', date: '2026-11-11', amount: 553016.07, bankDate: '2026-11-11', lines: [
        CustomerPaymentLine(reportNumber: '16475', nett: 173078.23),
        CustomerPaymentLine(reportNumber: '16476', nett: 178848.15),
        CustomerPaymentLine(reportNumber: '16477', nett: 201089.69),
      ]),
      CustomerPayment(id: 'p2', customerId: 'c2', date: '2026-10-01', amount: 100, lines: [CustomerPaymentLine(reportNumber: '15290', nett: 100)]),
      CustomerPayment(id: 'p3', customerId: 'c1', date: '2026-08-01', amount: 50, lines: const []), // before the period
    ];
    final items = xeroPaymentsToMatch(payments: pays, customers: customers, sentReportNumbers: {'16475', '16476', '15290'}, from: '2026-09-01', to: '2026-11-30');
    expect([for (final i in items) i.payment.id], ['p1', 'p2']);
    expect(items.first.customer, 'Botha Roodt Johannesburg');
    expect([for (final i in items.first.invoices) (i.number, i.inXero)], [('16475', true), ('16476', true), ('16477', false)]);
    expect(items.first.allInXero, isFalse);
    expect(xeroPaymentsToMatch(payments: pays, customers: customers, sentReportNumbers: {}, from: '2026-09-01', to: '2026-11-30', customerId: 'c2').single.payment.id, 'p2');
  });

  testWidgets('payments to match: the receipt and its invoices to tick, the ones not in Xero in red', (tester) async {
    final items = xeroPaymentsToMatch(payments: [
      CustomerPayment(id: 'p1', customerId: 'c1', date: '2026-11-11', amount: 553016.07, bankDate: '2026-11-11', lines: [
        CustomerPaymentLine(reportNumber: '16475', nett: 173078.23),
        CustomerPaymentLine(reportNumber: '16477', nett: 201089.69),
      ]),
    ], customers: customers, sentReportNumbers: {'16475'}, from: '2026-09-01', to: '2026-11-30');
    await tester.pumpWidget(MaterialApp(home: XeroPaymentsPage(items: items, period: '2026-09-01 to 2026-11-30')));
    await tester.pumpAndSettle();
    expect(find.text('R553 016.07'), findsOneWidget);
    expect(find.textContaining('tick 2 invoices'), findsOneWidget);
    expect(find.text('16475'), findsOneWidget);
    expect(find.text('16477  (not in Xero yet)'), findsOneWidget);
    expect(find.textContaining('1 payment has invoices not in Xero yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
