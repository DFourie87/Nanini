import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/sales/sales_models.dart';

SalesLineItem li(String? desc, {double? qty, String? klass, String cat = 'peppers'}) =>
    SalesLineItem(category: cat, subcategory: 'Red', klass: klass, description: desc, grossAmount: 100, qty: qty);

void main() {
  test('boxes come from qty, else from the market report description', () {
    expect(li('5kg: 1,120 boxes @ R85.00/boxes').units, 1120);
    expect(li('L: 40 boxes @ R90.00/boxes', qty: 42).units, 42);
    expect(li('12.50 kg @ R50.00/kg', cat: 'tobacco').units, 12.5);
    expect(li(null).units, null);
  });

  test('pepper box size from class, else from the description', () {
    expect(li('5kg: 10 boxes @ R1.00/boxes').effectiveClass, '5kg');
    expect(li('L: 10 boxes @ R1.00/boxes').effectiveClass, '5kg');
    expect(li('M: 10 boxes @ R1.00/boxes').effectiveClass, '4kg');
    expect(li('M: 10 boxes @ R1.00/boxes', klass: '5kg').effectiveClass, '5kg');
    expect(li('10 boxes @ R1.00/boxes').effectiveClass, null);
  });
}
