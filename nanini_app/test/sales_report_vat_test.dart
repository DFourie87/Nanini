import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/sales/sales_models.dart';
import 'package:nanini_app/features/sales/sales_reports_screen.dart';

SalesReport rep(String category, {double? vatOnSales, required double gross, required double ded, required double vat, required double nett}) => SalesReport(
    id: 'r', category: category, reportNumber: '1', reportDate: '2026-09-01', grossTotal: gross, commissionBeforeVat: ded, vat: vat, vatOnSales: vatOnSales, nettAmount: nett);

void main() {
  test('account sale card: gross (excl. VAT) less deductions is the nett, no VAT (ULSA006667)', () {
    final r = rep('tobacco', vatOnSales: 38579.40, gross: 257196, ded: 4960, vat: 744, nett: 290071.40);
    expect(reportNettExclVat(r), 252236);
    expect(reportNettExclVat(rep('peppers', gross: 1000, ded: 100, vat: 15, nett: 885)), 900);
  });
}
