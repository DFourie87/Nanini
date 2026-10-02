import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/suppliers/suppliers_data.dart';
import 'package:nanini_app/features/suppliers/suppliers_home_screen.dart';
import 'package:nanini_app/features/suppliers/suppliers_models.dart';
import 'package:nanini_app/features/suppliers/suppliers_repository.dart';

final agri = Supplier(id: 'a', name: 'Agri Supplies', accountNo: 'NAN01', openingBalance: 1000, openingDate: '2026-09-01');
final fuel = Supplier(id: 'f', name: 'Fuel Depot');

SupplierDoc doc(String id, String sup, SupplierDocKind k, String date, double amount, {String? ref, String? file}) =>
    SupplierDoc(id: id, supplierId: sup, kind: k, date: date, amount: amount, reference: ref, filePath: file);

final docs = [
  doc('i1', 'a', SupplierDocKind.invoice, '2026-09-10', 500, ref: 'INV100', file: 'a/1.pdf'),
  doc('i2', 'a', SupplierDocKind.invoice, '2026-09-25', 250, ref: 'INV101'),
  doc('c1', 'a', SupplierDocKind.creditNote, '2026-09-12', 50, ref: 'CN7'),
  doc('s1', 'a', SupplierDocKind.statement, '2026-09-15', 1150, ref: 'SEP-A'), // matches: 1000+500-50-300
  doc('s2', 'a', SupplierDocKind.statement, '2026-09-30', 1600), // ours 1400: R200 more on theirs
  doc('i3', 'f', SupplierDocKind.invoice, '2026-09-05', 2000, ref: 'D-55'),
];
final payments = [
  SupplierPayment(id: 'p1', supplierId: 'a', date: '2026-09-14', amount: 300, reference: 'EFT 1'),
  SupplierPayment(id: 'p2', supplierId: 'f', date: '2026-09-06', amount: 2000),
];

void main() {
  test('amount due, the account with running balance, statements checked', () {
    final a = SupplierAccount(agri, docs, payments);
    // 1000 opening + 500 + 250 invoices - 50 credit - 300 paid.
    expect(a.due, 1400);
    expect(a.balanceAt('2026-09-15'), 1150);
    expect(a.balanceAt('2026-08-31'), 0); // before the opening balance
    final l = a.ledger;
    expect(l.map((x) => x.label), ['Opening balance', 'Invoice INV100', 'Credit note CN7', 'Payment EFT 1', 'Invoice INV101']);
    expect(l.map((x) => x.balance), [1000, 1500, 1450, 1150, 1400]);
    final s = a.statements;
    expect(s.map((c) => c.statement.id), ['s2', 's1']); // newest first
    expect(s.last.matches, isTrue);
    expect(s.first.matches, isFalse);
    expect(s.first.difference, 200);
    // Paid in full.
    expect(SupplierAccount(fuel, docs, payments).due, 0);
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
    expect(find.text('R1 400.00'), findsNWidgets(2)); // total and Agri
    expect(find.text('Agri Supplies'), findsOneWidget);
    expect(find.text('Fuel Depot'), findsOneWidget);
    expect(find.textContaining('differs by R200.00'), findsOneWidget);
    expect(find.text('Add supplier'), findsOneWidget);
    // Most owed first.
    expect(tester.getTopLeft(find.text('Agri Supplies')).dy, lessThan(tester.getTopLeft(find.text('Fuel Depot')).dy));

    await tester.tap(find.text('Agri Supplies'));
    await tester.pumpAndSettle();
    expect(find.text('Amount due'), findsOneWidget);
    expect(find.text('Statements'), findsOneWidget);
    expect(find.text('Statement 30 Sep 2026'), findsOneWidget);
    expect(find.textContaining('The statement shows more'), findsOneWidget);
    expect(find.text('Matches -- nothing to follow up.', skipOffstage: false), findsOneWidget);
    // Upload buttons and a manual payment.
    for (final b in ['Invoice', 'Statement', 'Credit note', 'Payment']) {
      expect(find.ancestor(of: find.text(b), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)), findsOneWidget, reason: b);
    }
    await tester.scrollUntilVisible(find.text('Invoice INV101'), 200);
    expect(find.text('owed R1 400.00'), findsOneWidget);
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
