import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/hours/emp201_year_pdf.dart';
import 'package:nanini_app/features/hours/emp201_year_sheet.dart';
import 'package:nanini_app/features/hours/emp201_year_xlsx.dart';
import 'package:nanini_app/features/customers/customer_ledger.dart';
import 'package:nanini_app/features/sales/sales_customers_models.dart';
import 'package:nanini_app/features/sales/sales_models.dart';

SalesReport sale(String id, String agent, String number, String date, double gross, double commission, double vat, {String category = 'potatoes'}) =>
    SalesReport(
      id: id,
      category: category,
      agent: agent,
      reportNumber: number,
      reportDate: date,
      grossTotal: gross,
      commissionBeforeVat: commission,
      vat: vat,
      nettAmount: gross - commission - vat,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final customers = [
    Customer(id: 'c1', name: 'Agent One', agent: 'Agent One Markagente', openingBalance: 1000, openingDate: '2026-09-01'),
    Customer(id: 'c2', name: 'Agent Two', agent: 'Agent Two'),
  ];
  final reports = [
    sale('r0', 'Agent One Markagente', '100', '2026-09-20', 2000, 200, 30), // before the period: 1 770
    sale('r1', 'Agent One Markagente', '101', '2026-10-05', 10000, 1000, 150), // 8 850
    sale('r2', 'Agent One Markagente', '102', '2026-10-12', 5000, 500, 75), // 4 425
    sale('r3', 'Agent Two', '201', '2026-10-07', 3000, 300, 45), // 2 655
  ];
  final items = {
    'r1': [
      SalesLineItem(reportId: 'r1', category: 'potatoes', subcategory: 'Medium', klass: 'Class 1', grossAmount: 6000, qty: 300),
      SalesLineItem(reportId: 'r1', category: 'potatoes', subcategory: 'Large', klass: 'Class 2', grossAmount: 4000, qty: 200),
    ],
    'r2': [SalesLineItem(reportId: 'r2', category: 'potatoes', subcategory: 'Medium', klass: 'Class 1', grossAmount: 5000, qty: 250)],
    'r3': [SalesLineItem(reportId: 'r3', category: 'potatoes', subcategory: 'Small', klass: 'Class 1', grossAmount: 2500, qty: 150)],
  };
  final payments = [
    CustomerPayment(id: 'p0', customerId: 'c1', date: '2026-09-25', amount: 1000, lines: [CustomerPaymentLine(reportNumber: 'x', nett: 1000)]),
    CustomerPayment(id: 'p1', customerId: 'c1', date: '2026-10-15', amount: 8350, method: 'EFT', lines: [
      CustomerPaymentLine(reportNumber: '101', nett: 8350, loans: 500),
    ]),
  ];

  List<SheetSection> sheet() => customerLedgerSheet(customers: customers, reports: reports, items: items, payments: payments, from: '2026-10-01', to: '2026-10-31');
  double? num(SheetRow r, int i) => r.cells[i].number;

  test('Customer ledger: brought forward, a row per account sale and payment, running balance, summary', () {
    final s = sheet();
    expect(s.map((x) => x.title), ['Customer ledger -- summary', 'Agent One', 'Agent Two']);

    final one = s[1].tables.single.rows;
    final head = one.first.cells.map((c) => c.text).toList();
    expect(head, [
      'Date', 'Invoice / ref', 'Medium C1', 'Large C2', 'Gross excl. VAT', 'VAT', 'Gross incl. VAT', //
      'Deductions excl. VAT', 'VAT on deductions', 'Deductions incl. VAT', 'Nett receivable', 'Payments', 'Loans', 'Balance',
    ]);
    // Every row as wide as the heading.
    expect(one.every((r) => r.cells.length == head.length), isTrue);
    // Brought forward: 1 000 opening + 1 770 (sale 100) - 1 000 paid = 1 770.
    expect(one[1].cells[1].text, 'Brought forward');
    expect(num(one[1], head.length - 1), 1770);
    // Sale 101: subcategories, gross, deductions, nett, balance.
    final r101 = one.firstWhere((r) => r.cells[1].text == '101');
    expect([num(r101, 2), num(r101, 3), num(r101, 4), num(r101, 9), num(r101, 10), num(r101, 13)], [6000, 4000, 10000, 1150, 8850, 10620]);
    // The payment settles what it paid plus the loans taken off.
    final pay = one.firstWhere((r) => r.cells[1].text == 'Payment (EFT)');
    expect([num(pay, 11), num(pay, 12), num(pay, 13)], [8350, 500, 6195]); // after sale 102 on the 12th
    // Total row: nett 13 275; closing balance 1 770 + 13 275 - 8 350 - 500.
    final total = one.last;
    expect([num(total, 10), num(total, 11), num(total, 12), num(total, 13)], [13275, 8350, 500, 6195]);

    // Summary: a row per customer and the total.
    final sum = s[0].tables.single.rows;
    expect(sum[1].cells.first.text, 'Agent One');
    expect([num(sum[1], 1), num(sum[1], 4), num(sum[1], 5), num(sum[1], 6), num(sum[1], 7)], [1770, 13275, 8350, 500, 6195]);
    expect([num(sum[2], 4), num(sum[2], 7)], [2655, 2655]);
    expect(num(sum.last, 7), 6195 + 2655);
  });

  test('Customer ledger: Excel with a sheet per customer, and the PDF', () async {
    final s = sheet();
    final bytes = sheetXlsx('Ledger', s, sheetPerSection: true);
    final x = Excel.decodeBytes(bytes);
    expect(x.tables.keys.toList(), ['Customer ledger - summary', 'Agent One', 'Agent Two']);
    final pdf = await (await buildSheetPdf(s)).save();
    expect(pdf.length, greaterThan(1000));
    final out = Platform.environment['LEDGER_OUT'];
    if (out != null) File(out).writeAsBytesSync(pdf);
  });

  test('Customer ledger: from the opening balance; payments for older sales pay it off', () {
    // Owed on 1 March 2026: what was paid in March for the February sale
    // (885 + 115). A payment from February is behind the opening balance.
    final c = Customer(id: 'c3', name: 'Agent Three', agent: 'Agent Three', openingBalance: 1000, openingDate: '2026-03-01');
    final rs = [
      sale('f1', 'Agent Three', '300', '2026-02-20', 1000, 100, 15), // before: settled in the opening balance
      sale('m1', 'Agent Three', '301', '2026-03-10', 2000, 200, 30), // 1 770
    ];
    final ps = [
      CustomerPayment(id: 'q0', customerId: 'c3', date: '2026-02-10', amount: 500, lines: [CustomerPaymentLine(reportNumber: '299', nett: 500)]),
      CustomerPayment(id: 'q1', customerId: 'c3', date: '2026-03-05', amount: 885, lines: [CustomerPaymentLine(reportNumber: '300', nett: 885)]),
      CustomerPayment(id: 'q2', customerId: 'c3', date: '2026-03-20', amount: 1885, method: 'EFT', lines: [
        CustomerPaymentLine(reportNumber: '300', nett: 115), // a late bit of the February sale
        CustomerPaymentLine(reportNumber: '301', nett: 1770),
      ]),
    ];
    final s = customerLedgerSheet(customers: [c], reports: rs, items: const {}, payments: ps, from: '2026-03-01', to: '2026-03-31');
    final rows = s[1].tables.single.rows;
    final last = rows.first.cells.length - 1;
    final opening = rows.firstWhere((r) => r.cells[1].text == 'Opening balance');
    expect(num(opening, last), 1000);
    expect(rows.where((r) => (r.cells[1].text ?? '').startsWith('Payment')).length, 2); // not February's
    final pay = rows.firstWhere((r) => r.cells[1].text == 'Payment (EFT)');
    expect(num(pay, last - 1), 1885);
    expect(num(rows.last, last), 0); // 1 000 + 1 770 - 885 - 1 885
    // The Customers tab agrees: nothing owed.
    expect(CustomerAccount(c, rs, ps).owed, 0);
    // A sale from March not paid yet: owed.
    final more = [...rs, sale('m2', 'Agent Three', '302', '2026-03-25', 500, 50, 7.5)];
    expect(CustomerAccount(c, more, ps).owed, 442.5);
  });
}
