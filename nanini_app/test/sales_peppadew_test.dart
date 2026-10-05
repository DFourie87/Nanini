import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_repository.dart';
import 'package:nanini_app/features/sales/sales_customers_models.dart';
import 'package:nanini_app/features/sales/sales_data.dart';
import 'package:nanini_app/features/sales/sales_models.dart';
import 'package:nanini_app/features/sales/sales_repository.dart';
import 'package:nanini_app/features/sales/sales_summary_screen.dart';

class _Repo extends SalesRepository {
  final today = DateTime.now();
  String get day => '${today.year}-01-05';

  @override
  Future<List<SalesReport>> fetchReports() async => [
        SalesReport(id: 'r1', category: 'peppadew', agent: 'Peppadew', reportNumber: 'GRV-1', reportDate: day, grossTotal: 1000, commissionBeforeVat: 0, vat: 0, nettAmount: 1000),
        SalesReport(id: 'r2', category: 'peppadew', agent: 'Peppadew', reportNumber: 'GRV-2', reportDate: day, grossTotal: 300, commissionBeforeVat: 0, vat: 0, nettAmount: 300),
      ];

  @override
  Future<List<SalesLineItem>> fetchLineItemsForReports(List<String> reportIds) async => [
        SalesLineItem(reportId: 'r1', category: 'peppadew', subcategory: 'Red', klass: 'Class 1', grossAmount: 900, qty: 50),
        SalesLineItem(reportId: 'r1', category: 'peppadew', subcategory: 'Red', klass: 'Class 2', grossAmount: 100, qty: 10),
        SalesLineItem(reportId: 'r1', category: 'peppadew', subcategory: 'Red', klass: 'Rejected', grossAmount: 0, qty: 20),
        SalesLineItem(reportId: 'r2', category: 'peppadew', subcategory: 'Yellow', klass: 'Class 1', grossAmount: 300, qty: 20),
      ];

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
  testWidgets('Peppadew: the table and pie per colour and grade, per colour, or per grade', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = SalesData(_Repo(), delivery: _Delivery());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SalesSummaryScreen(data: data))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peppadew'));
    await tester.pumpAndSettle();
    // Per colour and grade (the default).
    expect(find.text('Red (Class 1)'), findsWidgets);
    expect(find.text('Yellow (Class 1)'), findsWidgets);
    expect(find.text('Red (Rejected)'), findsWidgets);
    // Per colour.
    await tester.tap(find.text('Per colour and grade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Per colour').last);
    await tester.pumpAndSettle();
    expect(find.text('Red (Class 1)'), findsNothing);
    expect(find.text('R1 000'), findsWidgets); // red: R900 + R100
    expect(find.text('R300'), findsWidgets);
    // Per grade: Class 1 = R900 + R300.
    await tester.tap(find.text('Per colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Per grade').last);
    await tester.pumpAndSettle();
    expect(find.text('Class 1'), findsWidgets);
    expect(find.text('R1 200'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
