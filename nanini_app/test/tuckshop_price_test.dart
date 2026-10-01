import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/tuckshop/tuckshop_models.dart';

void main() {
  test('sell price: cost plus margin, or the fixed price when set', () {
    final byMargin = TuckshopItem(id: 'a', name: 'Bread', profitPct: 35, lastCostPrice: 10);
    expect(byMargin.sellPrice, 14); // 13.50 rounded to the rand
    final fixed = TuckshopItem(id: 'b', name: 'Coke', profitPct: 35, lastCostPrice: 10, fixedSellPrice: 18);
    expect(fixed.sellPrice, 18);
    expect(fixed.marginPct, closeTo(80, 0.001));
    expect(TuckshopItem.fromJson({'id': 'c', 'name': 'Soap', 'last_cost_price': 20, 'fixed_sell_price': 25}).sellPrice, 25);
  });
}
