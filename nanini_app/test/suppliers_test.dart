import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/suppliers/suppliers_data.dart';
import 'package:nanini_app/features/suppliers/suppliers_home_screen.dart';
import 'package:nanini_app/features/suppliers/suppliers_models.dart';
import 'package:nanini_app/features/suppliers/suppliers_photo.dart';
import 'package:nanini_app/features/suppliers/suppliers_recon_screen.dart';
import 'package:nanini_app/features/suppliers/suppliers_repository.dart';
import 'package:nanini_app/theme/nanini_theme.dart';

final agri = Supplier(
    id: 'a',
    name: 'Agri Supplies',
    accountNo: 'NAN01',
    openingBalance: 1000,
    openingDate: '2026-09-01',
    bankName: 'FNB',
    bankAccountHolder: 'Agri Supplies (Pty) Ltd',
    bankAccountNo: '62012345678',
    bankBranchCode: '250655');
final fuel = Supplier(id: 'f', name: 'Fuel Depot');

SupplierDoc doc(String id, String sup, SupplierDocKind k, String date, double amount, {String? ref, String? file, double? overdue}) =>
    SupplierDoc(id: id, supplierId: sup, kind: k, date: date, amount: amount, reference: ref, filePath: file, overdueAmount: overdue);

final docs = [
  doc('i1', 'a', SupplierDocKind.invoice, '2026-09-10', 500, ref: 'INV100', file: 'a/1.pdf'),
  doc('i2', 'a', SupplierDocKind.invoice, '2026-09-25', 250, ref: 'INV101'),
  doc('c1', 'a', SupplierDocKind.creditNote, '2026-09-12', 50, ref: 'CN7'),
  doc('s1', 'a', SupplierDocKind.statement, '2026-09-15', 1150, ref: 'SEP-A'), // matches: 1000+500-50-300
  doc('s2', 'a', SupplierDocKind.statement, '2026-09-30', 1600, overdue: 600), // ours 1400: R200 more on theirs
  doc('i3', 'f', SupplierDocKind.invoice, '2026-09-05', 2000, ref: 'D-55'),
];
final payments = [
  SupplierPayment(id: 'p1', supplierId: 'a', date: '2026-09-14', amount: 300, reference: 'EFT 1'),
  SupplierPayment(id: 'p2', supplierId: 'f', date: '2026-09-06', amount: 2000),
];

/// The page's own (vertical) list, not the period chips' row.
final _vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

double _r15(double incl) => ((incl - incl / 1.15) * 100).roundToDouble() / 100;

void main() {
  test('amount due = opening + invoices - credit notes - payments; statements checked against it', () {
    final a = SupplierAccount(agri, docs, payments);
    // Ours: 1000 opening + 500 + 250 invoices - 50 credit - 300 paid = 1400. The
    // statement of 30 Sep says R1 600: R200 more, to follow up -- it doesn't change ours.
    expect(a.due, 1400);
    expect(a.balanceAt('2026-09-15'), 1150);
    expect(a.balanceAt('2026-08-31'), 1000); // the opening balance on 1 Sep: owed when that day began
    expect(a.balanceAt('2026-08-30'), 0);
    final l = a.ledger;
    expect(l.map((x) => x.label),
        ['Opening balance on 2026-09-01', 'Invoice INV100', 'Credit note CN7', 'Payment EFT 1', 'Statement -- matches', 'Invoice INV101', 'Statement differs']);
    expect(l.map((x) => x.balance), [1000, 1500, 1450, 1150, 1150, 1400, 1400]);
    expect((l.last.amount, l.last.check), (200, true));
    // An opening balance replaces what's in the app from before its date (a
    // February statement, February invoices): it isn't counted twice.
    final omnia = Supplier(id: 'o', name: 'Omnia', openingBalance: 415072.22, openingDate: '2026-03-01', termsDays: 30);
    final o = SupplierAccount(omnia, [
      doc('feb', 'o', SupplierDocKind.statement, '2026-02-28', 415072.22),
      doc('fi', 'o', SupplierDocKind.invoice, '2026-02-20', 15000), // on the February statement
      doc('mi', 'o', SupplierDocKind.invoice, '2026-03-10', 100000),
    ], [
      SupplierPayment(id: 'op', supplierId: 'o', date: '2026-04-05', amount: 200000),
      SupplierPayment(id: 'old', supplierId: 'o', date: '2026-02-25', amount: 50000), // before: in the opening balance
    ]);
    expect(o.due, 315072.22);
    expect(o.payable.fold<double>(0, (t, x) => t + x.amount), closeTo(315072.22, 0.001));
    // February's invoice and payment belong to the opening balance of 1 March: no warning.
    expect(o.hiddenByOpening, 0);
    // An opening balance dated the day the supplier was added hides the year's invoices and payments.
    final novon = Supplier(id: 'n', name: 'Novon', openingBalance: 26067.28, openingDate: '2026-10-03');
    final nv = SupplierAccount(novon, [doc('ni', 'n', SupplierDocKind.invoice, '2026-03-06', 3000.81)],
        [SupplierPayment(id: 'np', supplierId: 'n', date: '2026-03-05', amount: 26067.28)]);
    expect((nv.due, nv.hiddenByOpening), (26067.28, 2));
    final fixed = SupplierAccount(Supplier(id: 'n', name: 'Novon', openingBalance: 26067.28, openingDate: '2026-03-01'),
        [doc('ni', 'n', SupplierDocKind.invoice, '2026-03-06', 3000.81)], [SupplierPayment(id: 'np', supplierId: 'n', date: '2026-03-05', amount: 26067.28)]);
    expect((fixed.due, fixed.hiddenByOpening), (3000.81, 0));
    final ty = o.period('2026-03-01', '2027-02-28');
    expect((ty.opening, ty.invoices, ty.payments, ty.closing), (415072.22, 100000, 200000, 315072.22));
    // A later payment comes off ours; payments settle the oldest first.
    final later = SupplierPayment(id: 'p3', supplierId: 'a', date: '2026-10-02', amount: 700);
    final b = SupplierAccount(agri, docs, [...payments, later]);
    expect(b.due, 700);
    expect(b.payable.fold<double>(0, (t, x) => t + x.amount), 700);
    final s = a.statements;
    expect(s.map((c) => c.statement.id), ['s2', 's1']); // newest first
    expect(s.last.matches, isTrue);
    expect(s.first.matches, isFalse);
    expect(s.first.difference, 200);
    // Paid in full.
    expect(SupplierAccount(fuel, docs, payments).due, 0);
  });

  test('payable: payments and credits settle the oldest first; the rest by due date', () {
    // No statement: from the invoices.
    final p = SupplierAccount(agri, docs.where((d) => d.kind != SupplierDocKind.statement), payments).payable;
    // R350 paid/credited settles R350 of the opening balance.
    expect(p.map((x) => (x.dueDate, x.amount)), [('2026-09-01', 650.0), ('2026-10-10', 500.0), ('2026-10-25', 250.0)]);
    expect(p[1].invoices, ['INV100']);
    // 30 days from statement: the end of next month; other days: month end + days.
    final st = Supplier(id: 'a', name: 'X', termsKind: PaymentTerms.daysFromStatement, termsDays: 30);
    expect(st.dueDateFor('2026-09-08'), '2026-10-31');
    expect(st.dueDateFor('2026-10-15'), '2026-11-30');
    expect(st.dueDateFor('2026-12-31'), '2027-01-31');
    expect(Supplier(id: 'a', name: 'X', termsKind: PaymentTerms.daysFromStatement, termsDays: 60).dueDateFor('2026-12-05'), '2027-02-28');
    expect(Supplier(id: 'a', name: 'X', termsKind: PaymentTerms.daysFromStatement, termsDays: 45).dueDateFor('2026-09-10'), '2026-11-14');
    expect(Supplier(id: 'a', name: 'X', termsDays: 0).dueDateFor('2026-09-10'), '2026-09-10');
    expect(SupplierAccount(fuel, docs, payments).payable, isEmpty);
  });

  test('a due date printed on the document comes before the terms (Eskom)', () {
    final eskom = Supplier(id: 'e', name: 'Eskom', termsDays: 30);
    final bill = SupplierDoc(id: 'b', supplierId: 'e', kind: SupplierDocKind.invoice, date: '2026-09-20', amount: 3200, reference: 'SEP', dueDate: '2026-10-08');
    expect(SupplierAccount(eskom, [bill], const []).payable.single.dueDate, '2026-10-08');
  });

  test('VKB: only statements -- the balance and when it\'s due come from the latest one', () {
    final vkb = Supplier(id: 'v', name: 'VKB', termsKind: PaymentTerms.daysFromStatement, termsDays: 30);
    final aug = SupplierDoc(
        id: 'st', supplierId: 'v', kind: SupplierDocKind.statement, date: '2026-08-31', amount: 29873.45, overdueAmount: 16936.54, dueDate: '2026-09-30');
    var a = SupplierAccount(vkb, [aug], const []);
    expect(a.due, 29873.45);
    expect(a.payable.map((x) => (x.dueDate, x.amount)), [('2026-08-31', 16936.54), ('2026-09-30', 12936.91)]);
    expect(a.statements.single.checked, isFalse); // no invoices to check it against
    // An invoice after it (by email) and a payment.
    final inv = SupplierDoc(id: 'i', supplierId: 'v', kind: SupplierDocKind.invoice, date: '2026-09-15', amount: 500, reference: 'FT-1');
    final pay = SupplierPayment(id: 'p', supplierId: 'v', date: '2026-09-20', amount: 20000);
    a = SupplierAccount(vkb, [aug, inv], [pay]);
    expect(a.due, 10373.45);
    expect(a.payable.map((x) => (x.dueDate, x.amount)), [('2026-09-30', 9873.45), ('2026-10-31', 500.0)]);
    expect(a.ledger.map((x) => x.label), ['Balance per statement', 'Invoice FT-1', 'Payment']);
    // No due date on the statement: the terms (end of next month).
    final noDue = SupplierDoc(id: 'st', supplierId: 'v', kind: SupplierDocKind.statement, date: '2026-08-31', amount: 100);
    expect(SupplierAccount(vkb, [noDue], const []).payable.single.dueDate, '2026-09-30');
  });

  test('the account for a period: opening, invoices, payments, statements, closing', () {
    final a = SupplierAccount(agri, docs, payments);
    final p = a.period('2026-09-11', '2026-09-30');
    expect(p.opening, 1500); // opening 1000 + INV100 500
    expect(p.lines.map((l) => l.label), ['Credit note CN7', 'Payment EFT 1', 'Statement -- matches', 'Invoice INV101', 'Statement differs']);
    expect((p.invoices, p.creditNotes, p.payments, p.statementCharges), (250, 50, 300, 0));
    expect(p.closing, 1400);
    expect(p.differences.map((l) => (l.date, l.amount)), [('2026-09-30', 200.0)]);
    expect(p.opening + p.invoices - p.creditNotes - p.payments + p.statementCharges, p.closing);
    // Eskom's bills (invoice and statement in one): the charges are the
    // invoice, the payments come from the bank, the amount due checks it.
    final eskom = Supplier(id: 'e', name: 'Eskom - 1', category: '3650 - Electricity & Water');
    SupplierDoc bill(String id, String date, double due, double charges, double bf, String paidOn, double paid) => SupplierDoc(
        id: id,
        supplierId: 'e',
        kind: SupplierDocKind.statement,
        date: date,
        amount: due,
        reference: id,
        purchasesAmount: charges,
        vatAmount: _r15(charges),
        broughtForward: bf,
        paymentsReceived: [(date: paidOn, amount: paid)]);
    final bank = [
      SupplierPayment(id: 'p0', supplierId: 'e', date: '2026-07-10', amount: 900),
      SupplierPayment(id: 'p1', supplierId: 'e', date: '2026-08-20', amount: 1000),
      SupplierPayment(id: 'old', supplierId: 'e', date: '2026-06-10', amount: 800), // for a bill not in the app
    ];
    final e = SupplierAccount(eskom, [bill('B1', '2026-07-25', 1000, 1000, 900, '2026-07-10', 900), bill('B2', '2026-08-25', 1150, 1150, 1000, '2026-08-20', 1000)], bank);
    expect(e.ledger.map((l) => (l.label, l.balance)),
        [('Earlier bills (before 2026-07-25), expensed when paid', 900.0), ('Payment', 0.0), ('Invoice B1', 1000.0), ('Payment', 0.0), ('Invoice B2', 1150.0)]);
    final ep = e.period('2026-08-01', '2026-08-31');
    expect((ep.opening, ep.invoices, ep.payments, ep.statementCharges, ep.closing), (1000, 1150, 1000, 0, 1150));
    expect(e.statements.first.matches, isTrue);
    // The bill says more than the account: the difference shows.
    final off = SupplierAccount(eskom, [bill('B1', '2026-07-25', 1000, 1000, 900, '2026-07-10', 900), bill('B2', '2026-08-25', 1200, 1150, 1050, '2026-08-20', 1000)], bank);
    expect(off.ledger.last.label, "Difference to the bill's amount due");
    expect((off.ledger.last.amount, off.due), (50, 1200));
    // Before the bills Eskom was expensed when paid: nothing owing on 28 Feb.
    // The first bill lists a payment from before the bank payments here (26
    // Feb, expensed then); the rest of its balance brought forward is the
    // earlier bills' charges, expensed when paid (23 March).
    final feb = SupplierAccount(
        eskom,
        [
          SupplierDoc(
              id: 'A1',
              supplierId: 'e',
              kind: SupplierDocKind.statement,
              date: '2026-04-02',
              amount: -875.34,
              reference: 'A1',
              purchasesAmount: 4084.89,
              broughtForward: 8899.23,
              paymentsReceived: [(date: '2026-02-26', amount: 4960.23), (date: '2026-03-24', amount: 8899.23)]),
        ],
        [SupplierPayment(id: 'm', supplierId: 'e', date: '2026-03-23', amount: 8899.23)]);
    expect(feb.ledger.map((l) => (l.date, l.label, l.balance)), [
      ('2026-03-23', 'Earlier bills (before 2026-04-02), expensed when paid', 3939.0),
      ('2026-03-23', 'Payment', -4960.23),
      ('2026-04-02', 'Invoice A1', -875.34),
    ]);
    final year = feb.period('2026-03-01', '2027-02-28');
    expect((year.opening, year.invoices, year.payments, year.statementCharges, year.closing), (0, 8023.89, 8899.23, 0, -875.34));
    // In the purchases report too.
    final bought = purchasesFor([feb], const [], const [], '2026-03-01', '2027-02-28');
    expect(bought.map((l) => (l.description, l.excl, l.vat, l.account)), [
      (null, 4084.89, null, '3650/000'),
      // VAT was claimed on what was paid: 15/115 of the R3,939.00 paid on 23 March.
      ('Earlier bills (before 2026-04-02), expensed when paid (VAT on the amount paid)', 3425.22, 513.78, '3650/000'),
    ]);
  });

  test('purchases: lines per contra account -- by hand, remembered, the supplier\'s', () {
    final vkb = Supplier(id: 'v', name: 'VKB', category: 'Various');
    final eskom = Supplier(id: 'e', name: 'Eskom - 1', category: '3650 - Electricity & Water');
    final inv = SupplierDoc(id: 'i', supplierId: 'v', kind: SupplierDocKind.invoice, date: '2026-09-28', amount: 400, reference: 'PBAH1', vatAmount: 45);
    final cn = SupplierDoc(id: 'c', supplierId: 'v', kind: SupplierDocKind.creditNote, date: '2026-09-29', amount: 115, reference: 'PBAH2', vatAmount: 15);
    final bill = SupplierDoc(
        id: 'b', supplierId: 'e', kind: SupplierDocKind.statement, date: '2026-09-25', amount: 2000, purchasesAmount: 1150, vatAmount: 150, description: 'Electricity Sep');
    final lines = [
      DocLine(id: 'l1', docId: 'i', lineNo: 1, description: 'CHAIN WAX', excl: 200, vat: 30, glAccount: '4100/000'),
      DocLine(id: 'l2', docId: 'i', lineNo: 2, description: 'RAT PELLETS', excl: 100, vat: 0),
      DocLine(id: 'l3', docId: 'i', lineNo: 3, description: 'Fence  wire', excl: 55, vat: 15),
    ];
    final rules = [GlRule(supplierId: 'v', item: 'fence wire', glAccount: '4200/100')];
    final accounts = [SupplierAccount(vkb, [inv, cn], const []), SupplierAccount(eskom, [bill], const [])];
    final p = purchasesFor(accounts, lines, rules, '2026-09-01', '2026-09-30');
    expect(p.map((x) => (x.supplier.name, x.description, x.account, x.source, x.excl, x.vat, x.incl)), [
      ('Eskom - 1', 'Electricity Sep', '3650/000', GlSource.supplier, 1000.0, 150.0, 1150.0),
      // The bill's balance brought forward: the earlier bills (not here), expensed when paid.
      ('Eskom - 1', 'Earlier bills (before 2026-09-25), expensed when paid (VAT on the amount paid)', '3650/000', GlSource.supplier, 739.13, 110.87, 850.0),
      ('VKB', 'CHAIN WAX', '4100/000', GlSource.line, 200.0, 30.0, 230.0),
      ('VKB', 'RAT PELLETS', null, GlSource.none, 100.0, 0.0, 100.0),
      ('VKB', 'Fence  wire', '4200/100', GlSource.remembered, 55.0, 15.0, 70.0),
      ('VKB', null, null, GlSource.none, -100.0, -15.0, -115.0), // the credit note as one line
    ]);
    // Omnia: lines with VAT (transport) to 4800, the zero-rated fertilizer to its category.
    final omnia = Supplier(id: 'o', name: 'Omnia', category: '3740 - Fertilizer', vatAccount: '4800');
    final oi = SupplierDoc(id: 'oi', supplierId: 'o', kind: SupplierDocKind.invoice, date: '2026-09-08', amount: 33636, reference: 'OF27', vatAmount: 312);
    final ol = [
      DocLine(id: 'o1', docId: 'oi', lineNo: 1, description: 'POTASSIUM SULPHATE', excl: 31244, vat: 0),
      DocLine(id: 'o2', docId: 'oi', lineNo: 2, description: 'Own transport', excl: 2080, vat: 312),
    ];
    expect(purchasesFor([SupplierAccount(omnia, [oi], const [])], ol, const [], '2026-09-01', '2026-09-30').map((x) => (x.account, x.incl)),
        [('3740/000', 31244.0), ('4800/000', 2392.0)]);
    expect([categoryAccount('3650 - Electricity & Water'), categoryAccount('4200/100 Fencing'), categoryAccount('Various')], ['3650/000', '4200/100', null]);
    // The supplier's contra as entered when adding it: by code, else by the account's name in the chart.
    final chart = [GlAccount(code: '3740/000', name: 'Fertilizer'), GlAccount(code: '3700/000', name: 'Feed'), GlAccount(code: '3710/000', name: 'Feed - Supplements'), GlAccount(code: '3741/000', name: 'Insecticide')];
    expect([
      contraAccount('3650 - Electricity & Water', chart),
      contraAccount('fertilizer', chart),
      contraAccount('Feed', chart), // the one named so, not "Feed - Supplements"
      contraAccount('Fertilizer and seed', chart),
      contraAccount('Hardware', chart),
      contraAccount('Insectiside', chart), // spelt a little differently
    ], ['3650/000', '3740/000', '3700/000', '3740/000', null, '3741/000']);
    // Kalkor: lines with VAT are transport, the zero-rated rest fertilizer -- an
    // invoice read as one line is split by its VAT (15%).
    final kalkor = Supplier(id: 'k', name: 'Kalkor', category: '3740 - Fertilizer', vatAccount: '4800 - Transport');
    final ki = SupplierDoc(id: 'ki', supplierId: 'k', kind: SupplierDocKind.invoice, date: '2026-06-23', amount: 37127.19, vatAmount: 1173.91, description: 'Gips');
    expect(purchasesFor([SupplierAccount(kalkor, [ki], const [])], const [], const [], '2026-06-01', '2026-06-30').map((l) => (l.description, l.account, l.excl, l.vat)), [
      ('Gips (part with VAT)', '4800/000', 7826.07, 1173.91),
      ('Gips (zero-rated part)', '3740/000', 28127.21, 0.0),
    ]);
    final novon = Supplier(id: 'n', name: 'NOVON', category: 'Insecticide');
    final ni = SupplierDoc(id: 'ni', supplierId: 'n', kind: SupplierDocKind.invoice, date: '2026-09-10', amount: 1150, vatAmount: 150);
    expect(purchasesFor([SupplierAccount(novon, [ni], const [])], const [], const [], '2026-09-01', '2026-09-30', chart: chart).single.account, '3741/000');
    // Out of the period: nothing.
    expect(purchasesFor(accounts, lines, rules, '2026-10-01', '2026-10-31'), isEmpty);
    // The amount changed when confirming: the lines no longer add up -- one line.
    final changed = SupplierDoc(id: 'i', supplierId: 'v', kind: SupplierDocKind.invoice, date: '2026-09-28', amount: 999, vatAmount: 45);
    expect(purchasesFor([SupplierAccount(vkb, [changed], const [])], lines, rules, '2026-09-01', '2026-09-30').single.incl, 999);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final data = SuppliersData.forTest(SuppliersRepository(), suppliers: [fuel, agri], docs: docs, payments: payments, bankDate: '2026-09-30');
    await tester.pumpWidget(MaterialApp(home: SuppliersHomeScreen(data: data)));
    await tester.pumpAndSettle();
  }

  testWidgets('Due: the total, who to pay when and how much; Suppliers: each one, tap opens its page', (tester) async {
    await pump(tester);
    // Due: the total (owed in red), what's due now, then by day.
    expect(find.text('As at 30 Sep 2026 -- the bank statements up to then'), findsOneWidget);
    expect(find.text('Total due to suppliers'), findsOneWidget);
    expect((tester.widget<Text>(find.text('R1 400.00'))).style?.color, NaniniColors.red);
    // R650 of the opening balance (due 1 Sep) now; INV100 by 10 Oct, INV101 by 25 Oct.
    expect(find.text('Due now'), findsOneWidget);
    expect(find.text('R650.00'), findsNWidgets(2)); // due now: heading, Agri
    expect(find.text('By 10 Oct 2026'), findsOneWidget);
    expect(find.text('By 25 Oct 2026'), findsOneWidget);
    // Nothing owed to Fuel Depot: not listed here.
    expect(find.text('Fuel Depot'), findsNothing);
    expect(find.textContaining('Statement'), findsNothing);

    // List: each supplier A to Z, and Add supplier.
    await tester.tap(find.text('List').last);
    await tester.pumpAndSettle();
    expect(find.text('Agri Supplies'), findsOneWidget);
    expect(find.text('Fuel Depot'), findsOneWidget);
    expect(find.text('Add supplier'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Agri Supplies')).dy, lessThan(tester.getTopLeft(find.text('Fuel Depot')).dy));
    // No amounts on the list (they're on the Due tab).
    expect(find.text('R1 400.00'), findsNothing);

    // Tapped: the supplier's page -- each thing once.
    await tester.tap(find.text('Agri Supplies'));
    await tester.pumpAndSettle();
    // The recon: opening + invoices - credit notes - payments = amount due.
    expect(find.text('Opening balance 1 Mar 2026'), findsOneWidget);
    expect(find.text('+ Invoices'), findsOneWidget);
    expect(find.text('- Credit notes'), findsOneWidget);
    expect(find.text('- Payments'), findsOneWidget);
    expect(find.text('= Amount due'), findsOneWidget);
    expect(find.text('R1 400.00'), findsWidgets);
    // When it's payable: R650 of the opening balance (due 1 Sep) now, then INV100 and INV101 by their terms.
    expect(find.textContaining('R650.00 due now'), findsOneWidget);
    expect(find.text('R500.00 by 10 Oct 2026'), findsOneWidget);
    // The latest statement against it, once.
    expect(find.textContaining('Statement 30 Sep 2026: R1 600.00 -- R200.00 more than ours'), findsOneWidget);
    // Lines, statements among them.
    await tester.scrollUntilVisible(find.text('Invoice INV101'), 200, scrollable: _vertical);
    expect(find.text('owed R1 400.00'), findsOneWidget);
    expect(find.text('Statement differs'), findsOneWidget);
    // Newest at the top: the 30 Sep statement above the 25 Sep invoice.
    expect(tester.getTopLeft(find.text('Statement differs')).dy, lessThan(tester.getTopLeft(find.text('Invoice INV101')).dy));
    // The period.
    await tester.scrollUntilVisible(find.text('Dates'), -200, scrollable: _vertical);
    await tester.drag(_vertical, const Offset(0, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dates'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    // Adding: + at the top.
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    for (final b in ['Invoice', 'Credit note', 'Statement', 'Payment']) {
      expect(find.text(b), findsOneWidget, reason: b);
    }
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    // Details at the top: banking, terms, contact.
    await tester.scrollUntilVisible(find.text('Details'), -300, scrollable: _vertical);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Banking details'), findsOneWidget);
    expect(find.text('62012345678'), findsOneWidget);
    expect(find.text('250655'), findsOneWidget);
    expect(find.text('30 days from invoice'), findsOneWidget);
    expect(find.text('Change details'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The Purchases tab.
    await tester.tap(find.text('Purchases'));
    await tester.pumpAndSettle();
    expect(find.text('By contra account'), findsOneWidget);
    expect(find.text('All suppliers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('From email: listed to check, not counted until confirmed', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final emailed = SupplierDoc(
      id: 'e1',
      supplierId: 'a',
      kind: SupplierDocKind.invoice,
      date: '2026-09-28',
      amount: 999,
      reference: 'INV102',
      filePath: 'a/e1.pdf',
      fileName: 'INV102.pdf',
      toCheck: true,
      emailFrom: 'accounts@agri.co.za',
      emailSubject: 'Your invoice INV102',
      emailDate: '2026-09-28',
    );
    // Not in the account while it waits.
    expect(SupplierAccount(agri, [...docs, emailed], payments).due, 1400);
    expect(SupplierAccount(agri, [...docs, emailed], payments).toCheck.single.id, 'e1');

    final data = SuppliersData.forTest(SuppliersRepository(), suppliers: [fuel, agri], docs: [...docs, emailed], payments: payments);
    await tester.pumpWidget(MaterialApp(home: SuppliersHomeScreen(data: data)));
    await tester.pumpAndSettle();
    expect(find.text('1 from email to check'), findsNWidgets(1));
    expect(find.textContaining('1 from email to check'), findsNWidgets(1)); // on the total
    await tester.tap(find.text('List').last);
    await tester.pumpAndSettle();
    expect(find.text('1 from email to check'), findsOneWidget); // on Agri's line
    await tester.tap(find.text('Agri Supplies'));
    await tester.pumpAndSettle();
    expect(find.text('To check (1)'), findsOneWidget);
    expect(find.text('Confirm all (1)'), findsOneWidget);
    await tester.tap(find.text('Confirm all (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm 1 from email?'), findsOneWidget);
    expect(find.textContaining('invoices R999.00'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('R999.00'), findsOneWidget);
    await tester.ensureVisible(find.text('Invoice INV102 · 28 Sep 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invoice INV102 · 28 Sep 2026'));
    await tester.pumpAndSettle();
    expect(find.text('From email -- Agri Supplies'), findsOneWidget);
    expect(find.text('Open the PDF'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Invoice number'), findsOneWidget);
    expect(find.text('INV102'), findsOneWidget); // filled in from the PDF
    expect(find.text('999.00'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Purchases: totals per contra account; tap a line to allocate it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final vkb = Supplier(id: 'v', name: 'VKB', category: 'Various');
    final today = DateTime.now();
    final day = '${today.year}-${today.month.toString().padLeft(2, '0')}-01';
    final inv = SupplierDoc(id: 'i', supplierId: 'v', kind: SupplierDocKind.invoice, date: day, amount: 330, reference: 'PBAH1', vatAmount: 30);
    final data = SuppliersData.forTest(SuppliersRepository(),
        suppliers: [vkb],
        docs: [inv],
        docLines: [
          DocLine(id: 'l1', docId: 'i', lineNo: 1, description: 'CHAIN WAX', excl: 200, vat: 30, glAccount: '3740/000'),
          DocLine(id: 'l2', docId: 'i', lineNo: 2, description: 'RAT PELLETS', excl: 100, vat: 0),
        ],
        glAccounts: [GlAccount(code: '3650/000', name: 'Electricity & Water'), GlAccount(code: '3740/000', name: 'Fertilizer')]);
    await tester.pumpWidget(MaterialApp(home: SuppliersHomeScreen(data: data)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purchases'));
    await tester.pumpAndSettle();
    expect(find.text('3740/000 Fertilizer'), findsWidgets); // the total row (and the line)
    expect(find.text('Unallocated'), findsWidgets);
    expect(find.text('R330.00'), findsOneWidget); // the total incl.
    await tester.scrollUntilVisible(find.text('RAT PELLETS'), 200, scrollable: _vertical);
    await tester.tap(find.text('RAT PELLETS'));
    await tester.pumpAndSettle();
    expect(find.text('Contra account'), findsOneWidget);
    expect(find.text('3650/000 Electricity & Water'), findsOneWidget);
    expect(find.text('All 2 lines of this invoice'), findsOneWidget);
    expect(find.text('Remember for this item'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Account: an Eskom bill shows its summary, payments checked against the bank', (tester) async {
    final eskom = Supplier(id: 'e', name: 'Eskom - 1', category: '3650 - Electricity & Water');
    final b = SupplierDoc(
        id: 'b', supplierId: 'e', kind: SupplierDocKind.statement, date: '2026-09-28', amount: 75029.57, reference: '844541920439',
        purchasesAmount: 66784.55, vatAmount: 8697.30, broughtForward: 63211.85, paymentsReceived: [(date: '2026-09-08', amount: 54966.83)]);
    final data = SuppliersData.forTest(SuppliersRepository(),
        suppliers: [eskom],
        docs: [b],
        payments: [SupplierPayment(id: 'p', supplierId: 'e', date: '2026-09-07', amount: 54966.83)],
        docLines: [
          DocLine(id: 'l1', docId: 'b', lineNo: 1, description: 'Electricity', excl: 57981.99, vat: 8697.30),
          DocLine(id: 'l2', docId: 'b', lineNo: 2, description: 'Interest on overdue account', excl: 105.26, vat: 0),
        ]);
    final a = data.accounts.single;
    final inv = a.ledger.firstWhere((l) => l.label == 'Invoice 844541920439');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LedgerTile(line: inv, data: data))));
    expect(find.textContaining('Brought forward R63 211.85'), findsOneWidget);
    expect(find.textContaining('Paid R54 966.83 8 Sep 2026 ✓ bank'), findsOneWidget);
    expect(find.textContaining('Charges excl. R57 981.99 · VAT R8 697.30 · Interest etc. R105.26 · Amount due R75 029.57'), findsOneWidget);
    expect(find.text('R66 784.55'), findsOneWidget);
  });

  testWidgets('Electricity: per Eskom account, each bill\'s usage and fixed costs', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final e1 = Supplier(id: 'e1', name: 'Eskom - 6426721839', category: '3650 - Electricity & Water');
    final e2 = Supplier(id: 'e2', name: 'Eskom - 8441635490', category: '3650 - Electricity & Water');
    final today = DateTime.now();
    final day = '${today.year}-${today.month.toString().padLeft(2, '0')}-01';
    final bill = SupplierDoc.fromJson({
      'id': 'b',
      'supplier_id': 'e1',
      'kind': 'statement',
      'doc_date': day,
      'amount': 8543.17,
      'reference': '642778572350',
      'purchases_amount': 8543.17,
      'vat_amount': 1114.33,
      'description': 'Electricity March 2026',
      'status': 'confirmed',
      'bill_details': {
        'kwh': 1685.0,
        'days': 29,
        'from': '2026-02-11',
        'to': '2026-03-12',
        'reading': 'estimate',
        'charges': [
          {'description': 'Service and Administration Charge', 'kind': 'fixed', 'unit': 'day', 'rate': 24.5, 'days': 29, 'amount': 710.5},
          {'description': 'Network Capacity Charge', 'kind': 'fixed', 'unit': 'day', 'rate': 62.2, 'days': 29, 'amount': 1803.8},
          {'description': 'Network Demand Charge', 'kind': 'usage', 'quantity': 1685.0, 'unit': 'kWh', 'rate': 0.6166, 'amount': 1038.97},
          {'description': 'Ancillary Service Charge', 'kind': 'usage', 'quantity': 1685.0, 'unit': 'kWh', 'rate': 0.0041, 'amount': 6.91},
          {'description': 'Generation Capacity Charge', 'kind': 'fixed', 'unit': 'day', 'rate': 2.71, 'days': 29, 'amount': 78.59},
          {'description': 'Energy Charge', 'kind': 'usage', 'quantity': 1685.0, 'unit': 'kWh', 'rate': 2.2493, 'amount': 3790.07},
        ],
      },
    });
    expect((bill.billDetails!.usageTotal, bill.billDetails!.fixedTotal), (4835.95, 2592.89));
    final data = SuppliersData.forTest(SuppliersRepository(), suppliers: [e1, e2], docs: [bill]);
    await tester.pumpWidget(MaterialApp(home: SuppliersHomeScreen(data: data)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Electricity'));
    await tester.pumpAndSettle();
    expect(find.text('6426721839'), findsOneWidget); // a tab per account
    expect(find.text('8441635490'), findsOneWidget);
    await tester.tap(find.text('This month'));
    await tester.pumpAndSettle();
    // The period's, its estimated part and the bill's (on an estimated reading).
    expect(find.text('1 685 kWh'), findsWidgets);
    expect(find.text('  estimated by Eskom'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Used -- estimated by Eskom'), 200, scrollable: _vertical);
    expect(find.text('Used -- estimated by Eskom'), findsOneWidget);
    // Each bill its own formula.
    expect(find.text('1 685 kWh × (R0.6166 + R0.0041 + R2.2493) = R4 835.95  (R2.8700/kWh)', findRichText: true), findsOneWidget);
    expect(find.text('29 days × (R24.50 + R62.20 + R2.71) = R2 592.89  (R89.41/day)', findRichText: true), findsOneWidget);
    expect(find.text('R4 835.95'), findsWidgets);
    expect(find.text('ESTIMATED reading'), findsOneWidget);
    expect(find.text('1 (1 on estimated readings)'), findsOneWidget);
    expect(find.text('R2 592.89'), findsWidgets);
    expect(find.text('R7 428.84'), findsWidgets);
    // The other account: nothing in the period.
    await tester.scrollUntilVisible(find.text('8441635490'), -200, scrollable: _vertical);
    await tester.tap(find.text('8441635490'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No bills read in this period'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('a cash sale (paid at the till): a purchase, but not owed', () {
    final vkb = Supplier(id: 'v', name: 'VKB', termsKind: PaymentTerms.daysFromStatement, termsDays: 30);
    final st = SupplierDoc(id: 's', supplierId: 'v', kind: SupplierDocKind.statement, date: '2026-05-31', amount: 1000);
    final onAccount = SupplierDoc(id: 'i', supplierId: 'v', kind: SupplierDocKind.invoice, date: '2026-06-04', amount: 400, reference: 'PBAH1');
    final cash = SupplierDoc.fromJson({
      'id': 'c', 'supplier_id': 'v', 'kind': 'invoice', 'doc_date': '2026-06-05', 'amount': 1527, 'reference': 'BKAH126073',
      'status': 'confirmed', 'cash_sale': true, 'vat_amount': 0,
    });
    final a = SupplierAccount(vkb, [st, onAccount, cash], const []);
    expect(a.due, 1400);
    expect(a.ledger.map((l) => (l.label, l.amount, l.balance)), [
      ('Balance per statement', 1000.0, 1000.0),
      ('Invoice PBAH1', 400.0, 1400.0),
      ('Invoice BKAH126073', 1527.0, 2927.0),
      ('Paid at the till BKAH126073', -1527.0, 1400.0),
    ]);
    expect(a.payable.fold<double>(0, (t, p) => t + p.amount), 1400);
    final p = a.period('2026-06-01', '2026-06-30');
    expect((p.invoices, p.payments, p.closing), (1927, 1527, 1400));
    // In the purchases report it counts.
    expect(purchasesFor([a], const [], const [], '2026-06-01', '2026-06-30').map((l) => l.incl), [400.0, 1527.0]);
  });

  test('Eskom bill: two tariff periods -> a formula per period; a rebill credit', () {
    final d = BillDetails.fromJson({
      'kwh': 12106.0,
      'days': 154,
      'charges': [
        {'description': 'Service and Administration Charge', 'kind': 'fixed', 'unit': 'day', 'rate': 24.5, 'days': 98, 'amount': 2401.0},
        {'description': 'Service and Administration Charge', 'kind': 'fixed', 'unit': 'day', 'rate': 26.65, 'days': 56, 'amount': 1492.4},
        {'description': 'Network Capacity Charge', 'kind': 'fixed', 'unit': 'day', 'rate': 96.99, 'days': 98, 'amount': 9505.02},
        {'description': 'Network Demand Charge', 'kind': 'usage', 'quantity': 7704.0, 'unit': 'kWh', 'rate': 0.6166, 'amount': 4750.29},
        {'description': 'Network Demand Charge', 'kind': 'usage', 'quantity': 4402.0, 'unit': 'kWh', 'rate': 0.6706, 'amount': 2951.98},
        {'description': 'Energy Charge', 'kind': 'usage', 'quantity': 7704.0, 'unit': 'kWh', 'rate': 2.2493, 'amount': 17328.61},
        {'description': 'Energy Charge', 'kind': 'usage', 'quantity': 4402.0, 'unit': 'kWh', 'rate': 2.429, 'amount': 10692.46},
        {'description': 'Rebilled adjustments (earlier bills corrected)', 'kind': 'adjustment', 'unit': '', 'rate': 0, 'amount': -107114.59},
      ],
    });
    expect(d.kwhGroups.map((g) => '${g.$1}: ${g.$2.map((c) => c.rate).join(' + ')}'), ['7704.0: 0.6166 + 2.2493', '4402.0: 0.6706 + 2.429']);
    expect(d.dayGroups.map((g) => (g.$1, g.$2.length)), [(98.0, 2), (56.0, 1)]);
    expect(d.otherUsage, isEmpty);
    expect((d.adjustmentsTotal, d.fixed.length), (-107114.59, 3));
  });

  testWidgets('Invoice by photo: one photo, made into a PDF', (tester) async {
    // A 1x1 PNG for the camera.
    final png = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
    var shots = 0;
    takeInvoicePhoto = () async {
      shots++;
      return png;
    };
    await pump(tester);
    await tester.tap(find.text('List').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fuel Depot'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invoice'));
    await tester.pumpAndSettle();
    expect(find.text('Take a photo'), findsOneWidget);
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    expect(find.text('Photo taken -- retake'), findsOneWidget);
    expect(shots, 1);
    expect(find.text('Of it, VAT (optional -- for the purchases report)'), findsOneWidget);
    // Without the number: asked for, the photo kept.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Type the Invoice number'), findsOneWidget);
    expect(find.text('Photo taken -- retake'), findsOneWidget);

    final pdf = await tester.runAsync(() => photosToPdf([png]));
    expect(String.fromCharCodes(pdf!.take(4)), '%PDF');
  });

  testWidgets('Payment form: amount needed', (tester) async {
    await pump(tester);
    await tester.tap(find.text('List').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fuel Depot'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Payment').last);
    await tester.pumpAndSettle();
    expect(find.text('Payment -- Fuel Depot'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Type the amount paid.'), findsOneWidget);
  });
}
