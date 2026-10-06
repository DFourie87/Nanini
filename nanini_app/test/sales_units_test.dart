import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/sales/sales_models.dart';

SalesLineItem li(String? desc, {double? qty, String? klass, String cat = 'peppers'}) =>
    SalesLineItem(category: cat, subcategory: 'Red', klass: klass, description: desc, grossAmount: 100, qty: qty);

void main() {
  test('boxes come from qty, else from the market report description', () {
    expect(li('5kg: 1,120 boxes @ R85.00/boxes').units, 1120);
    expect(li('L: 40 boxes @ R90.00/boxes', qty: 42).units, 42);
    expect(li('12.50 kg @ R50.00/kg', cat: 'tobacco').units, 12.5);
    // Wenpro, CL de Villiers, Botha Roodt, Dapper: "units".
    expect(li('120 units @ R85.00/units').units, 120);
    expect(li('?: 1,040 units @ R80.00/units').units, 1040);
    expect(li(null).units, null);
  });

  test('pepper box size from class, else from the description', () {
    expect(li('5kg: 10 boxes @ R1.00/boxes').effectiveClass, '5kg');
    expect(li('L: 10 boxes @ R1.00/boxes').effectiveClass, '5kg');
    expect(li('M: 10 boxes @ R1.00/boxes').effectiveClass, '4kg');
    expect(li('M: 10 boxes @ R1.00/boxes', klass: '5kg').effectiveClass, '5kg');
    expect(li('10 boxes @ R1.00/boxes').effectiveClass, null);
  });

  test('nett sales: VAT on commission claimed back, except tobacco', () {
    SalesReport r(String cat) => SalesReport(
        category: cat, reportNumber: '1', reportDate: '2026-08-31',
        grossTotal: 1000, commissionBeforeVat: 100, vat: 15, nettAmount: 885);
    expect(r('peppers').nettSales, 900);
    expect(r('potatoes').nettSales, 900);
    expect(r('butternut').nettSales, 900);
    expect(r('tobacco').nettSales, 885);
  });

  test('pumpkins and watermelons are counted each', () {
    expect(kSalesCategories.map((c) => c.key), containsAll(['pumpkin', 'watermelon']));
    expect((salesUnit('pumpkin'), salesUnit('watermelon', plural: false), salesUnit('butternut'), salesUnit('peppadew')), ('units', 'unit', 'bags', 'kg'));
    expect(SalesLineItem(category: 'pumpkin', grossAmount: 31600, description: 'Medium: 395 units @ R80.00/units').units, 395);
  });
}
