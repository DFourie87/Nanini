import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/formatters.dart';
import '../../core/auth/session.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'tuckshop_models.dart';
import 'tuckshop_repository.dart';

class TuckshopStockScreen extends StatelessWidget {
  const TuckshopStockScreen({super.key, required this.repo, required this.farmId});
  final TuckshopRepository repo;
  final String? farmId;

  @override
  Widget build(BuildContext context) {
    final isManager = context.watch<Session>().isAdmin;
    return StreamBuilder<List<TuckshopItem>>(
      stream: repo.watchItems(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!.where((i) => i.farmId == farmId).toList();

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
                          subtitle: Text('Stock: ${item.totalStock.toStringAsFixed(0)} · Sell ${fmtR(item.sellPrice)}'),
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
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'restock', child: Text('Restock')),
                                    PopupMenuItem(value: 'writeoff', child: Text('Write off')),
                                    PopupMenuItem(value: 'edit', child: Text('Edit')),
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
                  if (!await requireAdmin(context)) return;
                  if (!context.mounted || farmId == null) return;
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
  final stockCtrl = TextEditingController(text: '0');
  String paidBy = kPaidByOptions.first;

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
              TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cost price (R)')),
              const SizedBox(height: 10),
              TextField(controller: profitCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Profit margin %')),
              const SizedBox(height: 10),
              TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Opening stock qty')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: paidBy,
                decoration: const InputDecoration(labelText: 'Paid by'),
                items: kPaidByOptions.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                onChanged: (v) => setState(() => paidBy = v!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await repo.addItem(
                name: nameCtrl.text.trim(),
                costPrice: double.tryParse(costCtrl.text) ?? 0,
                profitPct: double.tryParse(profitCtrl.text) ?? kDefaultProfitPct,
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
  final profitCtrl = TextEditingController(text: item.profitPct.toString());
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Edit item'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(controller: profitCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Profit margin %')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await repo.updateItem(item.id, name: nameCtrl.text.trim(), profitPct: double.tryParse(profitCtrl.text) ?? item.profitPct);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<void> _showRestockDialog(BuildContext context, TuckshopRepository repo, TuckshopItem item) async {
  final qtyCtrl = TextEditingController();
  final costCtrl = TextEditingController(text: item.currentCost.toString());
  String paidBy = kPaidByOptions.first;
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
            TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cost price (R)')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: paidBy,
              decoration: const InputDecoration(labelText: 'Paid by'),
              items: kPaidByOptions.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
              onChanged: (v) => setState(() => paidBy = v!),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final qty = double.tryParse(qtyCtrl.text) ?? 0;
              if (qty <= 0) return;
              await repo.restock(itemId: item.id, qty: qty, costPrice: double.tryParse(costCtrl.text) ?? 0, paidBy: paidBy);
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
            final qty = double.tryParse(qtyCtrl.text) ?? 0;
            if (qty <= 0) return;
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
