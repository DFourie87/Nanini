import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_repository.dart';
import 'package:nanini_app/features/sales/potato_fields.dart';
import 'package:nanini_app/features/sales/sales_customers_models.dart';
import 'package:nanini_app/features/sales/sales_data.dart';
import 'package:nanini_app/features/sales/sales_models.dart';
import 'package:nanini_app/features/sales/sales_repository.dart';
import 'package:nanini_app/features/sales/sales_summary_screen.dart';

final _year = DateTime.now().year;
String _day(int d) => '$_year-03-${d.toString().padLeft(2, '0')}';

DeliveryNote _note(int number, String field, Map<String, int> pallets, {List<Map<String, int>> mixed = const []}) => DeliveryNote(
      id: 'n$number',
      noteNumber: number,
      noteDate: _day(1),
      field: field,
      pallets: pallets,
      mixedPallets: mixed,
      produceType: 'potato',
      total: 0,
      createdAt: DateTime(_year, 3, 1),
    );

final _notes = [
  _note(3447, 'Field 2', {'med7': 2}, mixed: [
    {'large10': 30}
  ]), // 280 + 30 bags
  _note(3448, 'Field 5', {'large10': 1}), // 110 bags
];

final _reports = [
  // Paid with note 3447 (Field 2).
  SalesReport(id: 'r1', category: 'potatoes', agent: 'Botha Roodt Johannesburg', reportNumber: '111', reportDate: _day(4), grossTotal: 1000, commissionBeforeVat: 100, vat: 15, nettAmount: 885),
  // Not paid yet: field not known.
  SalesReport(id: 'r2', category: 'potatoes', agent: 'Botha Roodt Johannesburg', reportNumber: '112', reportDate: _day(5), grossTotal: 500, commissionBeforeVat: 50, vat: 7.5, nettAmount: 442.5),
];

final _items = [
  SalesLineItem(reportId: 'r1', category: 'potatoes', subcategory: 'Medium', klass: 'Class 1', grossAmount: 1000, qty: 100),
  SalesLineItem(reportId: 'r2', category: 'potatoes', subcategory: 'Large', klass: 'Class 1', grossAmount: 500, qty: 50),
];

final _customers = [Customer(id: 'c1', name: 'Grow Botha Roodt Johannesburg', agent: 'Botha Roodt Johannesburg')];
final _payments = [
  CustomerPayment(id: 'p1', customerId: 'c1', date: _day(10), amount: 885, lines: [CustomerPaymentLine(reportNumber: '111', deliveryNote: ' 3447 ', nett: 885)]),
];

class _Repo extends SalesRepository {
  final unsent = <UnsentPallets>[
    UnsentPallets(id: 'u1', date: _day(2), field: 'Field 5', pallets: {'large10': 1}, bags: {'large10': 10}, reason: 'Last truck of the week full'),
  ];

  @override
  Future<List<SalesReport>> fetchReports() async => _reports;
  @override
  Future<List<SalesLineItem>> fetchLineItemsForReports(List<String> reportIds) async => _items;
  @override
  Future<List<Customer>> fetchCustomers() async => _customers;
  @override
  Future<List<CustomerPayment>> fetchCustomerPayments() async => _payments;
  @override
  Future<List<UnsentPallets>> fetchUnsentPallets() async => List.of(unsent);
  @override
  Future<void> addUnsentPallets(UnsentPallets u) async =>
      unsent.add(UnsentPallets(id: 'u${unsent.length + 1}', date: u.date, field: u.field, pallets: u.pallets, bags: u.bags, reason: u.reason));
}

class _Delivery extends DeliveryRepository {
  @override
  Future<List<DeliveryNote>> fetchNotes() async => _notes;
}

PotatoFields _fields({List<UnsentPallets> unsent = const []}) => PotatoFields(
      notes: _notes,
      unsent: unsent,
      reports: _reports,
      items: _items,
      payments: _payments,
      customers: _customers,
      from: DateTime(_year, 1, 1),
      to: DateTime(_year, 12, 31),
      sizeClass: const {},
    );

void main() {
  test('Harvested per field: full and mixed pallets, plus packed-not-sent', () {
    final f = _fields(unsent: [UnsentPallets(date: _day(2), field: 'Field 5', pallets: {'large10': 1}, bags: {'large10': 10})]);
    final byName = {for (final x in f.fields) x.name: x};
    expect(byName['Field 2']!.sentBags, 310);
    expect(byName['Field 5']!.sentBags, 110);
    expect(byName['Field 5']!.unsentBags, 120);
    expect(f.harvestedBags, 540);
    expect(f.fields.map((x) => x.name), ['Field 2', 'Field 5']);
  });

  test('Sales per field through the payment summary; packed-not-sent never in sales', () {
    for (final unsent in [<UnsentPallets>[], [UnsentPallets(date: _day(2), field: 'Field 2', pallets: {'med7': 5})]]) {
      final f = _fields(unsent: unsent);
      final f2 = f.fields.firstWhere((x) => x.name == 'Field 2');
      expect(f2.nett, 900); // nett + VAT on commission
      expect(f2.bagsSold, 100);
      expect(f2.avgPrice, 9);
      expect(f.unknownNett, 450);
      expect(f.unknownBags, 50);
      expect(f.totalNett, 1350);
    }
  });

  testWidgets('Summary, potatoes: bags sold and by field at a glance, the rest below; adding pallets not sent', (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    final data = SalesData(repo, delivery: _Delivery());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SalesSummaryScreen(data: data, category: kSalesCategories.first))));
    await tester.pumpAndSettle();

    // At a glance: bags sold and the average price per subcategory, with the total.
    expect(find.text('Bags sold'), findsOneWidget);
    expect(find.text('Medium C1'), findsWidgets);
    expect(find.text('R9.00'), findsNWidgets(3));
    expect(find.text('150'), findsOneWidget);
    // Bags by field: Field 2 280 medium + 30 large; Field 5 110 sent + 120 not sent.
    expect(find.text('Bags by field'), findsOneWidget);
    expect(find.text('F2'), findsOneWidget);
    expect(find.text('310'), findsOneWidget);
    expect(find.text('230'), findsNWidgets(2)); // large in Field 5, and Field 5's total
    expect(find.text('260'), findsOneWidget);
    expect(find.text('540'), findsOneWidget);
    expect(find.textContaining('plus 120 bags packed but not sent'), findsOneWidget);
    // The rest opens below.
    expect(find.text('Sales by field'), findsNothing);
    await tester.tap(find.text('More detail: charts and sales by field'));
    await tester.pumpAndSettle();
    expect(find.text('Harvested by field'), findsOneWidget);
    expect(find.text('Sales by field'), findsOneWidget);
    expect(find.text('Field not known yet'), findsOneWidget);
    expect(find.text('R900'), findsWidgets);
    expect(find.text('R1 350'), findsWidgets);
    await tester.tap(find.text('Packed, not sent · 120 bags'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Last truck of the week full'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Choose the field.'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Field 3').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('unsent_pallets_med7')), '2');
    await tester.pumpAndSettle();
    expect(find.text('280 bags'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.unsent.last.field, 'Field 3');
    expect(repo.unsent.last.pallets, {'med7': 2});
    expect(repo.unsent.last.reason, 'No market for this size');
    // Field 3 now harvested, sales unchanged.
    expect(find.text('F3'), findsWidgets);
    expect(find.text('Packed, not sent · 400 bags'), findsOneWidget);
    expect(find.text('R9.00'), findsWidgets);
  });
}
