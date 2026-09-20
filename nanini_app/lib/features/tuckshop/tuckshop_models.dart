const kPaidByOptions = ['Nanini Boerdery', 'DF Fourie'];
const kDefaultProfitPct = 35.0;
const kLowStock = 5;

class TuckshopBatch {
  TuckshopBatch({required this.id, required this.itemId, required this.costPrice, required this.qty, required this.date, this.paidBy});
  final String id;
  final String itemId;
  final double costPrice;
  final double qty;
  final String date;
  final String? paidBy;

  factory TuckshopBatch.fromJson(Map<String, dynamic> j) => TuckshopBatch(
        id: j['id'] as String,
        itemId: j['item_id'] as String,
        costPrice: (j['cost_price'] as num).toDouble(),
        qty: (j['qty'] as num).toDouble(),
        date: j['batch_date'] as String,
        paidBy: j['paid_by'] as String?,
      );
}

class TuckshopItem {
  TuckshopItem({
    required this.id,
    required this.name,
    required this.profitPct,
    required this.lastCostPrice,
    this.farmId,
    this.batches = const [],
  });
  final String id;
  final String name;
  final double profitPct;
  final double lastCostPrice;
  final String? farmId;
  final List<TuckshopBatch> batches;

  factory TuckshopItem.fromJson(Map<String, dynamic> j) => TuckshopItem(
        id: j['id'] as String,
        name: j['name'] as String,
        profitPct: (j['profit_pct'] as num?)?.toDouble() ?? kDefaultProfitPct,
        lastCostPrice: (j['last_cost_price'] as num?)?.toDouble() ?? 0,
        farmId: j['farm_id'] as String?,
      );

  TuckshopItem withBatches(List<TuckshopBatch> b) =>
      TuckshopItem(id: id, name: name, profitPct: profitPct, lastCostPrice: lastCostPrice, farmId: farmId, batches: b);

  double get totalStock => batches.fold<double>(0, (s, b) => s + b.qty);

  double get currentCost {
    if (batches.isEmpty) return lastCostPrice;
    return batches.first.costPrice;
  }

  double get sellPrice => (currentCost * (1 + profitPct / 100)).roundToDouble();

  bool get lowStock => totalStock > 0 && totalStock <= kLowStock;
  bool get outOfStock => totalStock <= 0;
}

class TuckshopPurchase {
  TuckshopPurchase({
    required this.id,
    required this.employeeId,
    this.itemId,
    this.qty,
    required this.revenue,
    required this.cogs,
    required this.date,
    this.note,
    this.farmId,
    this.payslipId,
  });
  final String id;
  final String employeeId;
  final String? itemId;
  final double? qty;
  final double revenue;
  final double cogs;
  final String date;
  final String? note;
  final String? farmId;

  /// Set once this purchase has been deducted from a payslip -- never
  /// pulled into a later payroll run.
  final String? payslipId;

  factory TuckshopPurchase.fromJson(Map<String, dynamic> j) => TuckshopPurchase(
        id: j['id'] as String,
        employeeId: j['employee_id'] as String,
        itemId: j['item_id'] as String?,
        qty: (j['qty'] as num?)?.toDouble(),
        revenue: (j['revenue'] as num).toDouble(),
        cogs: (j['cogs'] as num?)?.toDouble() ?? 0,
        date: j['sale_date'] as String,
        note: j['note'] as String?,
        farmId: j['farm_id'] as String?,
        payslipId: j['payslip_id'] as String?,
      );
}

class TuckshopWriteoff {
  TuckshopWriteoff({required this.id, required this.itemId, required this.qty, required this.cogs, this.reason, required this.date});
  final String id;
  final String itemId;
  final double qty;
  final double cogs;
  final String? reason;
  final String date;

  factory TuckshopWriteoff.fromJson(Map<String, dynamic> j) => TuckshopWriteoff(
        id: j['id'] as String,
        itemId: j['item_id'] as String,
        qty: (j['qty'] as num).toDouble(),
        cogs: (j['cogs'] as num?)?.toDouble() ?? 0,
        reason: j['reason'] as String?,
        date: j['writeoff_date'] as String,
      );
}

class TuckshopStockPurchase {
  TuckshopStockPurchase({required this.id, required this.itemId, required this.qty, required this.costPrice, required this.total, this.paidBy, required this.date});
  final String id;
  final String itemId;
  final double qty;
  final double costPrice;
  final double total;
  final String? paidBy;
  final String date;

  factory TuckshopStockPurchase.fromJson(Map<String, dynamic> j) => TuckshopStockPurchase(
        id: j['id'] as String,
        itemId: j['item_id'] as String,
        qty: (j['qty'] as num).toDouble(),
        costPrice: (j['cost_price'] as num).toDouble(),
        total: (j['total'] as num).toDouble(),
        paidBy: j['paid_by'] as String?,
        date: j['purchase_date'] as String,
      );
}
