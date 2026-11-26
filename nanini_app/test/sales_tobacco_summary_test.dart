import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/formatters.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_repository.dart';
import 'package:nanini_app/features/sales/sales_customers_models.dart';
import 'package:nanini_app/features/sales/sales_data.dart';
import 'package:nanini_app/features/sales/sales_models.dart';
import 'package:nanini_app/features/sales/sales_repository.dart';
import 'package:nanini_app/features/sales/sales_summary_screen.dart';

class _Repo extends SalesRepository {
  String get day => '${DateTime.now().year}-01-05';

  @override
  Future<List<SalesReport>> fetchReports() async => [
        // Made-up figures: 1 000 + 150 VAT, deductions 100 + 10 VAT; 200 + 30, deductions 50 (no VAT).
        SalesReport(id: 't1', category: 'tobacco', agent: 'Leaf', reportNumber: 'T-1', reportDate: day, grossTotal: 1000, vatOnSales: 150, commissionBeforeVat: 100, vat: 10, nettAmount: 1040),
        SalesReport(id: 't2', category: 'tobacco', agent: 'Leaf', reportNumber: 'T-2', reportDate: day, grossTotal: 200, vatOnSales: 30, commissionBeforeVat: 50, vat: 0, nettAmount: 180),
      ];

  @override
  Future<List<SalesLineItem>> fetchLineItemsForReports(List<String> reportIds) async => [];
  @override
  Future<List<Customer>> fetchCustomers() async => [];
  @override
  Future<List<CustomerPayment>> fetchCustomerPayments() async => [];
}

class _Delivery extends DeliveryRepository {
  @override
  Future<List<DeliveryNote>> fetchNotes() async => [];
}

void main() {
  testWidgets('Tobacco summary: Gross (VAT incl.) - VAT = Gross (VAT excl.) - Deductions (VAT excl.) = Nett', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = SalesData(_Repo(), delivery: _Delivery());
    final tobacco = kSalesCategories.firstWhere((c) => c.key == 'tobacco');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SalesSummaryScreen(data: data, category: tobacco))));
    await tester.pumpAndSettle();
    String valueOf(String label) {
      final row = find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
      final texts = tester.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text))).map((t) => t.data).toList();
      return texts.last!;
    }

    expect(valueOf('Gross sales (VAT incl.)'), fmtR(1380));
    expect(valueOf('VAT'), fmtR(-180));
    expect(valueOf('Gross sales (VAT excl.)'), fmtR(1200));
    expect(valueOf('Deductions (VAT excl.)'), fmtR(-150));
    expect(valueOf('Nett (VAT excl.)'), fmtR(1050));
    expect(find.textContaining('Paid out'), findsNothing);
  });
}
