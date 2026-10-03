import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/suppliers/suppliers_data.dart';
import 'package:nanini_app/features/suppliers/suppliers_home_screen.dart';
import 'package:nanini_app/features/suppliers/suppliers_models.dart';
import 'package:nanini_app/features/suppliers/suppliers_repository.dart';

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

void main() {
  test('amount due (from the latest statement), the account with running balance, statements checked', () {
    final a = SupplierAccount(agri, docs, payments);
    // The statement of 30 Sep says R1 600 (ours: 1000 opening + 500 + 250 invoices - 50 credit - 300 paid = 1400).
    expect(a.due, 1600);
    expect(a.balanceAt('2026-09-15'), 1150);
    expect(a.balanceAt('2026-08-31'), 0); // before the opening balance
    final l = a.ledger;
    expect(l.map((x) => x.label), ['Opening balance', 'Invoice INV100', 'Credit note CN7', 'Payment EFT 1', 'Invoice INV101', 'Balance on statement']);
    expect(l.map((x) => x.balance), [1000, 1500, 1450, 1150, 1400, 1600]);
    // After the statement: a payment comes off it.
    final later = SupplierPayment(id: 'p3', supplierId: 'a', date: '2026-10-02', amount: 700);
    final b = SupplierAccount(agri, docs, [...payments, later]);
    expect(b.due, 900);
    // R700 settles the R600 already due and R100 of the rest.
    expect(b.payable.map((x) => (x.dueDate, x.amount)), [('2026-10-30', 900.0)]);
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
    expect(a.ledger.map((x) => x.label), ['Balance on statement', 'Invoice FT-1', 'Payment']);
    // No due date on the statement: the terms (end of next month).
    final noDue = SupplierDoc(id: 'st', supplierId: 'v', kind: SupplierDocKind.statement, date: '2026-08-31', amount: 100);
    expect(SupplierAccount(vkb, [noDue], const []).payable.single.dueDate, '2026-09-30');
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final data = SuppliersData.forTest(SuppliersRepository(), suppliers: [fuel, agri], docs: docs, payments: payments);
    await tester.pumpWidget(MaterialApp(home: SuppliersHomeScreen(data: data)));
    await tester.pumpAndSettle();
  }

  testWidgets('Overview: each supplier and what\'s due, the total; tap opens the recon', (tester) async {
    await pump(tester);
    expect(find.text('Total due to suppliers'), findsOneWidget);
    expect(find.text('R1 600.00'), findsNWidgets(2)); // total and Agri (per the statement)
    expect(find.text('Agri Supplies'), findsOneWidget);
    expect(find.text('Fuel Depot'), findsOneWidget);
    expect(find.textContaining('differs by R200.00'), findsOneWidget);
    expect(find.text('Add supplier'), findsOneWidget);
    // Most owed first.
    expect(tester.getTopLeft(find.text('Agri Supplies')).dy, lessThan(tester.getTopLeft(find.text('Fuel Depot')).dy));

    // Overdue and next due on the overview line.
    expect(find.textContaining('R600.00 overdue'), findsOneWidget);

    // Tapped: the details -- payable when, banking details -- then Recon.
    await tester.tap(find.text('Agri Supplies'));
    await tester.pumpAndSettle();
    expect(find.text('Banking details'), findsOneWidget);
    expect(find.text('62012345678'), findsOneWidget);
    expect(find.text('250655'), findsOneWidget);
    expect(find.text('Payable'), findsOneWidget);
    expect(find.text('30 days from invoice'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Text && (w.data == 'By 30 Oct 2026' || w.data == 'Overdue -- was due 30 Oct 2026'), skipOffstage: false),
        findsOneWidget);
    expect(find.text('R1 000.00', skipOffstage: false), findsOneWidget);
    final recon = find.ancestor(of: find.text('Recon', skipOffstage: false), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton, skipOffstage: false));
    await tester.ensureVisible(recon);
    await tester.pumpAndSettle();
    await tester.tap(recon);
    await tester.pumpAndSettle();
    expect(find.text('Amount due'), findsOneWidget);
    expect(find.text('Statements'), findsOneWidget);
    expect(find.text('Statement 30 Sep 2026'), findsOneWidget);
    expect(find.textContaining('The statement shows more'), findsOneWidget);
    expect(find.text('Already due'), findsOneWidget);
    expect(find.text('Matches -- nothing to follow up.', skipOffstage: false), findsOneWidget);
    // Upload buttons and a manual payment.
    for (final b in ['Invoice', 'Statement', 'Credit note', 'Payment']) {
      expect(find.ancestor(of: find.text(b), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)), findsOneWidget, reason: b);
    }
    await tester.scrollUntilVisible(find.text('Invoice INV101'), 200);
    expect(find.text('owed R1 400.00'), findsOneWidget);
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
    expect(SupplierAccount(agri, [...docs, emailed], payments).due, 1600);
    expect(SupplierAccount(agri, [...docs, emailed], payments).toCheck.single.id, 'e1');

    final data = SuppliersData.forTest(SuppliersRepository(), suppliers: [fuel, agri], docs: [...docs, emailed], payments: payments);
    await tester.pumpWidget(MaterialApp(home: SuppliersHomeScreen(data: data)));
    await tester.pumpAndSettle();
    expect(find.text('1 from email to check'), findsNWidgets(1));
    expect(find.textContaining('1 from email to check'), findsNWidgets(2)); // total and Agri's line
    await tester.tap(find.text('Agri Supplies'));
    await tester.pumpAndSettle();
    final recon = find.ancestor(of: find.text('Recon', skipOffstage: false), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton, skipOffstage: false));
    await tester.ensureVisible(recon);
    await tester.pumpAndSettle();
    await tester.tap(recon);
    await tester.pumpAndSettle();
    expect(find.text('From email -- to check (1)'), findsOneWidget);
    expect(find.text('Confirm all (1)'), findsOneWidget);
    await tester.tap(find.text('Confirm all (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm 1 from email?'), findsOneWidget);
    expect(find.textContaining('invoices R999.00'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('R999.00'), findsOneWidget);
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

  testWidgets('Payment form: amount needed', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Recon'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a supplier to work on.'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fuel Depot').last);
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(of: find.text('Payment'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
    await tester.pumpAndSettle();
    expect(find.text('Payment -- Fuel Depot'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Type the amount paid.'), findsOneWidget);
  });
}
