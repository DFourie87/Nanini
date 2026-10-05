import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/suppliers/suppliers_allocation.dart';
import 'package:nanini_app/features/suppliers/suppliers_data.dart';
import 'package:nanini_app/features/suppliers/suppliers_models.dart';
import 'package:nanini_app/features/suppliers/suppliers_repository.dart';

void main() {
  final chart = [
    GlAccount(code: '3740/000', name: 'Fertilizer'),
    GlAccount(code: '4280/000', name: 'Packaging'),
    GlAccount(code: '3660/000', name: 'Transport'),
  ];
  final laeveld = Supplier(id: 'l', name: 'Laeveld', category: '3740/000 - Fertilizer');
  final inv = SupplierDoc(id: 'd', supplierId: 'l', kind: SupplierDocKind.invoice, date: '2026-09-10', amount: 1150, vatAmount: 150, reference: 'IN1', description: 'Nutricast');

  SuppliersData data({List<DocLine> lines = const [], List<GlRule> rules = const [], List<GlAccount>? accounts}) =>
      SuppliersData.forTest(SuppliersRepository(), suppliers: [laeveld], docs: [inv], glAccounts: accounts ?? chart, docLines: lines, glRules: rules);

  test('lines read from the PDF: each its remembered account, else the supplier\'s', () {
    final lines = [
      DocLine(id: 'a', docId: 'd', lineNo: 1, description: 'Nutricast', excl: 800, vat: 120),
      DocLine(id: 'b', docId: 'd', lineNo: 2, description: 'Bags', excl: 200, vat: 30),
    ];
    final rows = allocationFor(data(lines: lines, rules: [GlRule(supplierId: 'l', item: 'bags', glAccount: '4280/000')]), laeveld, inv, 1150, 150);
    expect(rows.map((r) => (r.lineId, r.account, r.read)), [('a', '3740/000', true), ('b', '4280/000', true)]);
  });

  test('no lines read: the invoice as one line; a supplier without a contra leaves it to choose', () {
    final rows = allocationFor(data(), laeveld, inv, 1150, 150);
    expect(rows.map((r) => (r.excl, r.vat, r.account)), [(1000.0, 150.0, '3740/000')]);
    final none = Supplier(id: 'l', name: 'Laeveld');
    final open = allocationFor(data(), none, inv, 1150, 150);
    expect(open.single.account, isNull);
    expect(allAllocated(data(), open), isFalse);
    // No chart of accounts set up: nothing to choose.
    expect(allAllocated(data(accounts: const []), open), isTrue);
  });

  test('lines that no longer add up to the total: the invoice as one line', () {
    final lines = [DocLine(id: 'a', docId: 'd', lineNo: 1, description: 'Nutricast', excl: 800, vat: 120)];
    final rows = allocationFor(data(lines: lines), laeveld, inv, 1150, 150);
    expect(rows.single.lineId, isNull);
  });
}
