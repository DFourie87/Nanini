import '../../core/formatters.dart';
import '../../core/supabase_client.dart';
import '../employees/employees_models.dart';
import 'tuckshop_models.dart';

class TuckshopRepository {
  Stream<List<TuckshopItem>> watchItems() {
    return sb.from('tuckshop_items').stream(primaryKey: ['id']).order('name').asyncMap((rows) async {
      final items = rows.map(TuckshopItem.fromJson).toList();
      final batchRows = await sb.from('tuckshop_batches').select().order('batch_date');
      final batches = (batchRows as List).map((r) => TuckshopBatch.fromJson(r as Map<String, dynamic>)).toList();
      return items.map((item) => item.withBatches(batches.where((b) => b.itemId == item.id).toList())).toList();
    });
  }

  Stream<List<TuckshopPurchase>> watchPurchases() => sb
      .from('tuckshop_purchases')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((r) => r.map(TuckshopPurchase.fromJson).toList());

  Stream<List<TuckshopWriteoff>> watchWriteoffs() => sb
      .from('tuckshop_writeoffs')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((r) => r.map(TuckshopWriteoff.fromJson).toList());

  Stream<List<TuckshopStockPurchase>> watchStockPurchases() => sb
      .from('tuckshop_stock_purchases')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((r) => r.map(TuckshopStockPurchase.fromJson).toList());

  Future<void> addItem({
    required String name,
    required double costPrice,
    required double profitPct,
    required int openingStock,
    required String paidBy,
    required String farmId,
  }) async {
    final item = await sb.from('tuckshop_items').insert({
      'name': name,
      'profit_pct': profitPct,
      'last_cost_price': costPrice,
      'farm_id': farmId,
    }).select().single();
    if (openingStock > 0) {
      await sb.from('tuckshop_batches').insert({
        'item_id': item['id'],
        'cost_price': costPrice,
        'qty': openingStock,
        'batch_date': todayStr(),
        'paid_by': paidBy,
      });
    }
  }

  Future<void> updateItem(String id, {required String name, required double profitPct, required double costPrice, String? latestBatchId}) async {
    await sb.from('tuckshop_items').update({'name': name, 'profit_pct': profitPct, 'last_cost_price': costPrice}).eq('id', id);
    if (latestBatchId != null) {
      await sb.from('tuckshop_batches').update({'cost_price': costPrice}).eq('id', latestBatchId);
    }
  }

  /// Hides the item from the Stock list and purchase pickers without
  /// deleting its row -- purchases/write-offs already logged against it
  /// keep their item_id and still resolve the item's name in reports.
  Future<void> archiveItem(String id) => sb.from('tuckshop_items').update({'archived': true}).eq('id', id);

  Future<void> restock({required String itemId, required double qty, required double costPrice, required String paidBy}) async {
    await sb.from('tuckshop_batches').insert({
      'item_id': itemId,
      'cost_price': costPrice,
      'qty': qty,
      'batch_date': todayStr(),
      'paid_by': paidBy,
    });
    await sb.from('tuckshop_items').update({'last_cost_price': costPrice}).eq('id', itemId);
  }

  /// FIFO consumption: depletes oldest batches first, returns total COGS.
  Future<double> _consumeFifo(TuckshopItem item, double qty) async {
    var remaining = qty;
    var cogs = 0.0;
    final batches = [...item.batches]..sort((a, b) => a.date.compareTo(b.date));
    for (final batch in batches) {
      if (remaining <= 0) break;
      final take = remaining < batch.qty ? remaining : batch.qty;
      cogs += take * batch.costPrice;
      remaining -= take;
      final newQty = batch.qty - take;
      if (newQty <= 0) {
        await sb.from('tuckshop_batches').delete().eq('id', batch.id);
      } else {
        await sb.from('tuckshop_batches').update({'qty': newQty}).eq('id', batch.id);
      }
    }
    if (remaining > 0) {
      cogs += remaining * item.lastCostPrice;
    }
    return cogs;
  }

  Future<void> logItemPurchase({required TuckshopItem item, required Employee employee, required double qty, required String date}) async {
    final cogs = await _consumeFifo(item, qty);
    final revenue = item.sellPrice * qty;
    await sb.from('tuckshop_purchases').insert({
      'employee_id': employee.id,
      'item_id': item.id,
      'qty': qty,
      'revenue': revenue,
      'cogs': cogs,
      'sale_date': date,
    });
  }

  Future<void> logManualPurchase({required Employee employee, required String from, required String to, required double total, required String farmId}) =>
      sb.from('tuckshop_purchases').insert({
        'employee_id': employee.id,
        'item_id': null,
        'qty': null,
        'revenue': total,
        'cogs': 0,
        'sale_date': to,
        'note': 'Manual shop total for $from to $to',
        'farm_id': farmId,
      });

  Future<void> writeOff({required TuckshopItem item, required double qty, String? reason}) async {
    final cogs = await _consumeFifo(item, qty);
    await sb.from('tuckshop_writeoffs').insert({
      'item_id': item.id,
      'qty': qty,
      'cogs': cogs,
      'reason': reason ?? '',
      'writeoff_date': todayStr(),
    });
  }
}
