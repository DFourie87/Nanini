import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/tuckshop/tuckshop_models.dart';

void main() {
  test('each shop on its own: sales and write-offs at their own shop only', () {
    final itemFarm = {'bread': 'limpopo', 'mealie': 'haas'};
    TuckshopPurchase sale(String id, {String? farm, String? item}) =>
        TuckshopPurchase(id: id, employeeId: 'e', itemId: item, revenue: 10, cogs: 5, date: '2026-10-01', farmId: farm);
    // Saved with its shop.
    expect(purchaseShop(sale('1', farm: 'haas', item: 'mealie'), itemFarm), 'haas');
    // An older sale saved without its shop: its item's shop, not every shop.
    expect(purchaseShop(sale('2', item: 'bread'), itemFarm), 'limpopo');
    // A Limpopodraai write-off is never Haaskraal's.
    final wo = TuckshopWriteoff(id: 'w', itemId: 'bread', qty: 2, cogs: 20, date: '2026-10-02');
    expect(writeoffShop(wo, itemFarm), 'limpopo');
    expect(writeoffShop(TuckshopWriteoff(id: 'w2', itemId: 'mealie', qty: 1, cogs: 9, date: '2026-10-02'), itemFarm), 'haas');
  });
}
