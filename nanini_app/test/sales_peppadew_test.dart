import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_repository.dart';
import 'package:nanini_app/features/sales/peppadew_summary.dart';
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
        SalesLineItem(reportId: 'r1', category: 'peppadew', subcategory: 'Red', klass: 'Rejected', grossAmount: 0, qty: 15, description: 'Sun burn: 15.00 kg @ R0.00/kg'),
        SalesLineItem(reportId: 'r1', category: 'peppadew', subcategory: 'Red', klass: 'Rejected', grossAmount: 0, qty: 5, description: 'Soft: 5.00 kg @ R0.00/kg'),
        SalesLineItem(reportId: 'r2', category: 'peppadew', subcategory: 'Yellow', klass: 'Rejected', grossAmount: 0, qty: 5, description: '5.00 kg @ R0.00/kg'),
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
  test('Peppadew summary: delivered, accepted, classes, rejected per reason', () {
    final s = PeppadewSummary([
      SalesLineItem(category: 'peppadew', subcategory: 'Yellow', klass: 'Class 1', grossAmount: 300, qty: 20),
      SalesLineItem(category: 'peppadew', subcategory: 'Red', klass: 'Class 1', grossAmount: 900, qty: 50),
      SalesLineItem(category: 'peppadew', subcategory: 'Red', klass: 'Rejected', grossAmount: 0, qty: 15, description: 'Sun burn: 15.00 kg @ R0.00/kg'),
      SalesLineItem(category: 'peppadew', subcategory: 'Red', klass: 'Rejected', grossAmount: 0, qty: 5, description: 'Internal/Black spot: 5.00 kg @ R0.00/kg'),
      SalesLineItem(category: 'peppadew', subcategory: 'Yellow', klass: 'Rejected', grossAmount: 0, qty: 5, description: '5.00 kg @ R0.00/kg'),
    ]);
    expect(s.colours, ['Red', 'Yellow']);
    expect((s.delivered['Red'], s.accepted['Red'], s.delivered['Yellow'], s.accepted['Yellow']), (70.0, 50.0, 25.0, 20.0));
    expect(s.classes['Red']!['Class 1'], (50.0, 900.0));
    expect(s.reasons, ['Sun burn', 'Internal/Black spot', PeppadewSummary.notItemised]);
    expect(s.rejectedOf('Red'), 20.0);
  });

  testWidgets('Peppadew tab: delivered and accepted, Class 1 and 2, rejected fruit', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = SalesData(_Repo(), delivery: _Delivery());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SalesSummaryScreen(data: data))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peppadew'));
    await tester.pumpAndSettle();
    expect(find.text('Nett sales by subcategory'), findsNothing);
    // Red: 80 kg delivered, 60 accepted (75%); yellow 25, 20 (80%).
    expect(find.text('Delivered and accepted'), findsOneWidget);
    expect(find.text('105 kg'), findsOneWidget); // delivered, both colours
    expect(find.text('75.0%'), findsOneWidget);
    expect(find.text('80.0%'), findsOneWidget);
    // Red Class 1: 50 kg, R900, R18.00/kg; Class 2: R10.00/kg.
    expect(find.text('Red Class 1'), findsOneWidget);
    expect(find.text('R18.00'), findsOneWidget);
    expect(find.text('R10.00'), findsOneWidget);
    // Rejected per reason; the old single total "Not itemised".
    expect(find.text('Sun burn'), findsOneWidget);
    expect(find.text('Soft'), findsOneWidget);
    expect(find.text(PeppadewSummary.notItemised), findsOneWidget);
    expect(find.text('18.8%'), findsOneWidget); // sun burn: 15 of red's 80 kg
    expect(tester.takeException(), isNull);
  });
}
