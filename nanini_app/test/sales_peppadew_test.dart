import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_repository.dart';
import 'package:nanini_app/features/sales/peppadew_summary.dart';
import 'package:nanini_app/features/sales/sales_customers_models.dart';
import 'package:nanini_app/features/sales/sales_data.dart';
import 'package:nanini_app/features/sales/sales_home_screen.dart';
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
        SalesLineItem(reportId: 'r1', category: 'peppadew', subcategory: 'Red', klass: 'Rejected', grossAmount: 0, qty: 15, description: 'Sun burn: 15.00 kg @ R0.00/kg'),
        SalesLineItem(reportId: 'r1', category: 'peppadew', subcategory: 'Red', klass: 'Rejected', grossAmount: 0, qty: 5, description: 'Soft: 5.00 kg @ R0.00/kg'),
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
    // The rejected fruit per reason, as a share of the rejected fruit: sun
    // burn 15 of red's 20 kg rejected (and of the total, only red rejected).
    expect(find.text('Rejected fruit'), findsOneWidget);
    expect(find.text('Sun burn'), findsOneWidget);
    expect(find.text('Soft'), findsOneWidget);
    expect(find.text('75.0%'), findsNWidgets(2));
    expect(find.text('25.0%'), findsNWidgets(2));
    expect(find.text('100.0%'), findsNWidgets(2));
    // Rejected of the kg delivered, in the note: red 20 of 80 kg.
    expect(find.textContaining('Rejected: Red 25.0%, Yellow 0.0% of the kg delivered'), findsOneWidget);
    expect(find.text('Total rejected'), findsOneWidget);
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

  testWidgets('Sales opens on a tile per produce; a tile opens its Summary and Reports', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = SalesData(_Repo(), delivery: _Delivery());
    await tester.pumpWidget(MaterialApp(home: SalesHomeScreen(data: data)));
    await tester.pumpAndSettle();
    for (final c in kSalesCategories) {
      expect(find.text(c.label), findsOneWidget);
    }
    await tester.tap(find.text('Peppadew'));
    await tester.pumpAndSettle();
    // Only Peppadew: no produce picker.
    expect(find.text('Red (Class 1)'), findsWidgets);
    expect(find.text('Potatoes'), findsNothing);
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('All categories'), findsNothing);
    expect(find.textContaining('GRV-1'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('Peppadew rejects per reason; old loads as one total', () {
    final s = PeppadewSummary([
      SalesLineItem(category: 'peppadew', subcategory: 'Yellow', klass: 'Class 1', grossAmount: 300, qty: 20),
      SalesLineItem(category: 'peppadew', subcategory: 'Red', klass: 'Class 1', grossAmount: 900, qty: 50),
      SalesLineItem(category: 'peppadew', subcategory: 'Red', klass: 'Rejected', grossAmount: 0, qty: 15, description: 'Sun burn: 15.00 kg @ R0.00/kg'),
      SalesLineItem(category: 'peppadew', subcategory: 'Red', klass: 'Rejected', grossAmount: 0, qty: 5, description: 'Internal/Black spot: 5.00 kg @ R0.00/kg'),
      SalesLineItem(category: 'peppadew', subcategory: 'Yellow', klass: 'Rejected', grossAmount: 0, qty: 5, description: '5.00 kg @ R0.00/kg'),
    ]);
    expect(s.colours, ['Red', 'Yellow']);
    expect((s.delivered['Red'], s.delivered['Yellow']), (70.0, 25.0));
    expect(s.reasons, ['Sun burn', 'Internal/Black spot', PeppadewSummary.notItemised]);
    expect(s.rejectedOf('Red'), 20.0);
  });
}
