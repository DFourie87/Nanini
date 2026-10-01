import 'package:flutter/material.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/formatters.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'tuckshop_models.dart';
import 'tuckshop_repository.dart';

class TuckshopStockScreen extends StatelessWidget {
  const TuckshopStockScreen({super.key, required this.repo, required this.farmId, this.canManage = false});
  final TuckshopRepository repo;
  final String? farmId;

  /// Admin, or given this farm's tuck shop: restock, write off, edit, add.
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final isManager = canManage;
    return StreamBuilder<List<TuckshopItem>>(
      stream: repo.watchItems(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!.where((i) => i.farmId == farmId && !i.archived).toList();

        return Stack(
          children: [
            items.isEmpty
                ? const Center(child: Text('No items yet for this farm.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(item.name),
                          subtitle: Text('Stock: ${item.totalStock.toStringAsFixed(0)} · Sell ${fmtR(item.sellPrice)}${item.fixedSellPrice != null ? ' (fixed)' : ''}'),
                          trailing: Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _StockBadge(item: item),
                              if (isManager)
                                PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    if (v == 'restock') {
                                      await _showRestockDialog(context, repo, item);
                                    } else if (v == 'writeoff') {
                                      await _showWriteOffDialog(context, repo, item);
                                    } else if (v == 'edit') {
                                      await _showEditItemDialog(context, repo, item);
                                    } else if (v == 'remove') {
                                      await _removeItem(context, repo, item);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'restock', child: Text('Restock')),
                                    const PopupMenuItem(value: 'writeoff', child: Text('Write off')),
                                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                    if (item.outOfStock) const PopupMenuItem(value: 'remove', child: Text('Remove item')),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () async {
                  if (!canManage && !await requireAdmin(context)) return;
                  if (!context.mounted) return;
                  if (farmId == null) return showProblem(context, "Farms haven't loaded yet -- check the internet connection and try again.");
                  await _showAddItemDialog(context, repo, farmId!);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.item});
  final TuckshopItem item;
  @override
  Widget build(BuildContext context) {
    final (label, color) = item.outOfStock
        ? ('Out of stock', NaniniColors.red)
        : item.lowStock
            ? ('Low stock', NaniniColors.amber)
            : ('In stock', NaniniColors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

Future<void> _showAddItemDialog(BuildContext context, TuckshopRepository repo, String farmId) async {
  final nameCtrl = TextEditingController();
  final costCtrl = TextEditingController();
  final profitCtrl = TextEditingController(text: kDefaultProfitPct.toString());
  final fixedCtrl = TextEditingController();
  var fixed = false;
  final stockCtrl = TextEditingController(text: '0');
  String paidBy = kPaidByOptions.first;
  final sortedPaidByOptions = [...kPaidByOptions]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Add item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Cost price (R)'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              _SellPriceFields(
                cost: parseNum(costCtrl.text) ?? 0,
                fixed: fixed,
                profitCtrl: profitCtrl,
                fixedCtrl: fixedCtrl,
                onFixed: (v) => setState(() => fixed = v),
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Opening stock qty')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: paidBy,
                decoration: const InputDecoration(labelText: 'Paid by'),
                items: sortedPaidByOptions.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                onChanged: (v) => setState(() => paidBy = v!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return showProblem(ctx, 'Enter the item name.');
              final price = parseNum(fixedCtrl.text);
              if (fixed && (price == null || price <= 0)) return showProblem(ctx, 'Enter the selling price.');
              await repo.addItem(
                name: nameCtrl.text.trim(),
                costPrice: parseNum(costCtrl.text) ?? 0,
                profitPct: parseNum(profitCtrl.text) ?? kDefaultProfitPct,
                fixedSellPrice: fixed ? price : null,
                openingStock: int.tryParse(stockCtrl.text) ?? 0,
                paidBy: paidBy,
                farmId: farmId,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showEditItemDialog(BuildContext context, TuckshopRepository repo, TuckshopItem item) async {
  final nameCtrl = TextEditingController(text: item.name);
  final costCtrl = TextEditingController(text: item.currentCost.toString());
  final profitCtrl = TextEditingController(text: item.profitPct.toString());
  final fixedCtrl = TextEditingController(text: item.fixedSellPrice == null ? '' : item.fixedSellPrice!.toString().replaceFirst(RegExp(r'\.0$'), ''));
  var fixed = item.fixedSellPrice != null;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Edit item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Purchase price (R)'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              _SellPriceFields(
                cost: parseNum(costCtrl.text) ?? item.currentCost,
                fixed: fixed,
                profitCtrl: profitCtrl,
                fixedCtrl: fixedCtrl,
                onFixed: (v) => setState(() => fixed = v),
                onChanged: () => setState(() {}),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final price = parseNum(fixedCtrl.text);
              if (fixed && (price == null || price <= 0)) return showProblem(ctx, 'Enter the selling price.');
              await repo.updateItem(
                item.id,
                name: nameCtrl.text.trim(),
                profitPct: parseNum(profitCtrl.text) ?? item.profitPct,
                costPrice: parseNum(costCtrl.text) ?? item.currentCost,
                fixedSellPrice: fixed ? price : null,
                latestBatchId: item.latestBatchId,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showRestockDialog(BuildContext context, TuckshopRepository repo, TuckshopItem item) async {
  final qtyCtrl = TextEditingController();
  final costCtrl = TextEditingController(text: item.currentCost.toString());
  String paidBy = kPaidByOptions.first;
  final sortedPaidByOptions = [...kPaidByOptions]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Restock ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty bought')),
            const SizedBox(height: 10),
            TextField(controller: costCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cost price (R)')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: paidBy,
              decoration: const InputDecoration(labelText: 'Paid by'),
              items: sortedPaidByOptions.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
              onChanged: (v) => setState(() => paidBy = v!),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final qty = parseNum(qtyCtrl.text) ?? 0;
              if (qty <= 0) return showProblem(ctx, 'Enter how many were bought.');
              await repo.restock(itemId: item.id, qty: qty, costPrice: parseNum(costCtrl.text) ?? 0, paidBy: paidBy);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) showToast(context, 'Restocked ${item.name}');
            },
            child: const Text('Restock'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _removeItem(BuildContext context, TuckshopRepository repo, TuckshopItem item) async {
  final ok = await confirmDialog(
    context,
    message: 'Remove "${item.name}" from the stock list? Sales and write-offs already logged for it are kept.',
    danger: true,
  );
  if (!ok) return;
  await repo.archiveItem(item.id);
  if (context.mounted) showToast(context, '${item.name} removed');
}

Future<void> _showWriteOffDialog(BuildContext context, TuckshopRepository repo, TuckshopItem item) async {
  final qtyCtrl = TextEditingController();
  final reasonCtrl = TextEditingController();
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Write off ${item.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty')),
          const SizedBox(height: 10),
          TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final qty = parseNum(qtyCtrl.text) ?? 0;
            if (qty <= 0) return showProblem(ctx, 'Enter the quantity to write off.');
            await repo.writeOff(item: item, qty: qty, reason: reasonCtrl.text.trim());
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) showToast(context, 'Wrote off $qty × ${item.name}');
          },
          child: const Text('Write off'),
        ),
      ],
    ),
  );
}

/// How the selling price is set: a profit margin on the cost price, or a
/// fixed price -- with what that comes to.
class _SellPriceFields extends StatelessWidget {
  const _SellPriceFields({
    required this.cost,
    required this.fixed,
    required this.profitCtrl,
    required this.fixedCtrl,
    required this.onFixed,
    required this.onChanged,
  });
  final double cost;
  final bool fixed;
  final TextEditingController profitCtrl;
  final TextEditingController fixedCtrl;
  final ValueChanged<bool> onFixed;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final price = fixed ? (parseNum(fixedCtrl.text) ?? 0) : sellPriceFor(cost, parseNum(profitCtrl.text) ?? 0);
    final margin = cost > 0 && price > 0 ? (price / cost - 1) * 100 : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Selling price', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Profit margin %')),
            ButtonSegment(value: true, label: Text('Fixed price')),
          ],
          selected: {fixed},
          onSelectionChanged: (s) => onFixed(s.first),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
        ),
        const SizedBox(height: 10),
        if (fixed)
          TextField(
            controller: fixedCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Selling price', prefixText: 'R'),
            onChanged: (_) => onChanged(),
          )
        else
          TextField(
            controller: profitCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Profit margin %'),
            onChanged: (_) => onChanged(),
          ),
        const SizedBox(height: 6),
        Text(
          fixed
              ? (margin == null ? 'Sells at ${fmtR(price)}' : 'Sells at ${fmtR(price)} -- ${margin.toStringAsFixed(0)}% on cost')
              : 'Sells at ${fmtR(price)} (rounded to the rand)',
          style: TextStyle(color: margin != null && margin < 0 ? NaniniColors.red : NaniniColors.muted),
        ),
      ],
    );
  }
}
