import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_repository.dart';
import 'package:nanini_app/features/sales/sales_data.dart';
import 'package:nanini_app/features/sales/sales_models.dart';
import 'package:nanini_app/features/sales/sales_repository.dart';

class _FakeSales extends SalesRepository {
  int reportLoads = 0;
  final itemLoads = <List<String>>[];

  @override
  Future<List<SalesReport>> fetchReports() async {
    reportLoads++;
    return [];
  }

  @override
  Future<List<SalesLineItem>> fetchLineItemsForReports(List<String> reportIds) async {
    itemLoads.add(reportIds);
    return [
      for (final id in reportIds) SalesLineItem(reportId: id, category: 'peppers', subcategory: 'Red', grossAmount: 100, qty: 10),
    ];
  }
}

class _FakeDelivery extends DeliveryRepository {
  int loads = 0;
  @override
  Future<List<DeliveryNote>> fetchNotes() async {
    loads++;
    return [];
  }
}

void main() {
  test('loads once; line items fetched once and kept', () async {
    final sales = _FakeSales();
    final delivery = _FakeDelivery();
    final data = SalesData(sales, delivery: delivery);
    await Future<void>.delayed(Duration.zero);
    expect(sales.reportLoads, 1);
    expect(delivery.loads, 1);

    expect(data.itemsFor(['a', 'b']), isNull); // fetching
    expect(data.itemsFor(['a', 'b']), isNull); // not fetched twice
    await Future<void>.delayed(Duration.zero);
    expect(sales.itemLoads, [
      ['a', 'b'],
    ]);
    expect(data.itemsFor(['a', 'b'])!.length, 2);
    expect(data.itemsFor(['b'])!.single.reportId, 'b');
    expect(sales.itemLoads.length, 1); // everything from memory now

    // Only the refresh button loads again.
    await data.refresh();
    expect(sales.reportLoads, 2);
    expect(data.itemsFor(['a']), isNull);
  });
}
