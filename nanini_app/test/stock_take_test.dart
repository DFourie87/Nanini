import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/tuckshop/stock_take_pdf.dart';
import 'package:nanini_app/features/tuckshop/tuckshop_models.dart';
import 'package:nanini_app/features/tuckshop/tuckshop_repository.dart';
import 'package:nanini_app/features/tuckshop/tuckshop_stock_screen.dart';

// Made-up items.
TuckshopItem item(String id, String name, double stock, {double cost = 10, double? fixed, String farm = 'fh'}) => TuckshopItem(
      id: id,
      name: name,
      profitPct: 30,
      lastCostPrice: cost,
      farmId: farm,
      fixedSellPrice: fixed,
      batches: [TuckshopBatch(id: 'b$id', itemId: id, costPrice: cost, qty: stock, date: '2026-11-01')],
    );

class _Repo extends TuckshopRepository {
  _Repo(this.items);
  final List<TuckshopItem> items;
  @override
  Stream<List<TuckshopItem>> watchItems() => Stream.value(items);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final items = [
    item('a', 'Wors', 12, fixed: 45),
    item('b', 'Bread', 7),
    for (var i = 0; i < 40; i++) item('x$i', 'Item $i', i.toDouble()),
    item('o', 'Other shop', 3, farm: 'fl'),
  ];

  test('The stock take list: each item, its selling price and stock now, empty boxes to count; dated when printed', () async {
    final at = DateTime(2026, 11, 25, 7, 5);
    expect(stockTakeStamp(at), '25 Nov 2026 07:05');
    final doc = await buildStockTakePdf(farmName: 'Haaskraal', items: items.where((i) => i.farmId == 'fh').toList(), at: at);
    final bytes = await doc.save();
    // 42 items: over a page.
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length, greaterThanOrEqualTo(2));
    final out = Platform.environment['STOCKTAKE_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  testWidgets('Stock tab: the stock take button below the last item', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TuckshopStockScreen(repo: _Repo(items), farmId: 'fh', farmName: 'Farm Haaskraal - Swartwater'))));
    await tester.pumpAndSettle();
    expect(find.text('Wors'), findsOneWidget);
    expect(find.text('Other shop'), findsNothing);
    await tester.scrollUntilVisible(find.text('Print stock take list'), 300);
    expect(find.text('Print stock take list'), findsOneWidget);
  });
}
