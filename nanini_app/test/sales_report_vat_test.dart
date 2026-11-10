import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/sales/sales_models.dart';
import 'package:nanini_app/features/sales/sales_reports_screen.dart';

SalesReport rep(String category, {double? vatOnSales, required double gross, required double ded, required double vat, required double nett}) => SalesReport(
    id: 'r', category: category, reportNumber: '1', reportDate: '2026-09-01', grossTotal: gross, commissionBeforeVat: ded, vat: vat, vatOnSales: vatOnSales, nettAmount: nett);

void main() {
  test('tobacco: the VAT on the sale shown, so gross + it - deductions - VAT = nett (ULSA006667)', () {
    final r = rep('tobacco', vatOnSales: 38579.40, gross: 257196, ded: 4960, vat: 744, nett: 290071.40);
    expect(reportVatOnSales(r), 38579.40);
    // Not captured on an older report: what makes it add up.
    final old = rep('tobacco', gross: 257196, ded: 4960, vat: 744, nett: 290071.40);
    expect(reportVatOnSales(old), closeTo(38579.40, 0.001));
    expect(old.grossTotal + reportVatOnSales(old) - old.commissionBeforeVat - old.vat, closeTo(old.nettAmount, 0.001));
  });

  test('produce: zero rated, no VAT on the sale', () {
    expect(reportVatOnSales(rep('peppers', gross: 1000, ded: 100, vat: 15, nett: 885)), 0);
  });
}
