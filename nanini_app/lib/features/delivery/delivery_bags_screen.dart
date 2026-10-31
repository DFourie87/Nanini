import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'bag_stock.dart';
import 'delivery_models.dart';
import 'delivery_repository.dart';

/// Packaging > Bags/Boxes: the potato bags, pepper boxes and butternut bags
/// on the floor to pack -- bought, less 1% for losses, less what went out on
/// the delivery notes (from 1 Feb 2025). Crown Bag's potato bag invoices come
/// in from email (scripts/fetch_crown_bags.py on the office PC); the rest is
/// typed in here.
class DeliveryBagsScreen extends StatefulWidget {
  const DeliveryBagsScreen({super.key, required this.repo});
  final DeliveryRepository repo;
  @override
  State<DeliveryBagsScreen> createState() => _DeliveryBagsScreenState();
}

class _DeliveryBagsScreenState extends State<DeliveryBagsScreen> {
  ProduceType produce = ProduceType.potato;
  late final _purchases = widget.repo.watchBagPurchases();
  late final _notes = widget.repo.watchNotes();

  static String _n(int v) => (v < 0 ? '-' : '') + '${v.abs()}'.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  String get _unit => produce == ProduceType.pepper ? 'boxes' : 'bags';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BagPurchase>>(
      stream: _purchases,
      builder: (context, purSnap) {
        return StreamBuilder<List<DeliveryNote>>(
          stream: _notes,
          builder: (context, noteSnap) {
            final purchases = purSnap.data ?? const <BagPurchase>[];
            final notes = noteSnap.data ?? const <DeliveryNote>[];
            final balances = bagBalances(produce, purchases, notes);
            final kinds = bagKinds(produce);
            final total = BagBalance(
              balances.values.fold(0, (s, b) => s + b.bought),
              balances.values.fold(0, (s, b) => s + b.used),
            );
            final received = purchases.where((b) => b.produce == produce).toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<ProduceType>(
                  segments: const [
                    ButtonSegment(value: ProduceType.potato, label: Text('Potatoes (Bags)', textAlign: TextAlign.center)),
                    ButtonSegment(value: ProduceType.pepper, label: Text('Peppers (Boxes)', textAlign: TextAlign.center)),
                    ButtonSegment(value: ProduceType.butternut, label: Text('Butternuts (Bags)', textAlign: TextAlign.center)),
                  ],
                  selected: {produce},
                  onSelectionChanged: (s) => setState(() => produce = s.first),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
                ),
                const SizedBox(height: 12),
                if (purSnap.hasError)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Bags bought can\'t be read yet -- run docs/sql/bag_purchases.sql in Supabase.', style: TextStyle(color: NaniniColors.red)),
                  ),
                Text('On the floor to pack', style: Theme.of(context).textTheme.titleMedium),
                Text('Bought, less ${(kBagLosses * 100).round()}% for losses, less what went out on the delivery notes -- from ${fmtDateDisplay(kBagsFrom)}.',
                    style: const TextStyle(color: NaniniColors.muted)),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final k in kinds) _balanceTile(k.label, balances[k.key]!),
                      const Divider(height: 1),
                      _balanceTile('Total', total, bold: true),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => runOnce('delivery_bags.add', () => _add(context)),
                  icon: const Icon(Icons.add),
                  label: Text('Add ${produce == ProduceType.pepper ? 'boxes' : 'bags'} received'),
                ),
                if (produce == ProduceType.potato)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Crown Bag\'s invoices come in from email: run scripts\\fetch_crown_bags.py on the office PC.',
                        style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
                  ),
                const SizedBox(height: 20),
                Text('Received', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (received.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('No $_unit received yet.', style: const TextStyle(color: NaniniColors.muted)))
                else
                  Card(
                    child: Column(
                      children: [
                        for (final b in received)
                          ListTile(
                            dense: true,
                            title: Text('${_n(b.qty)} × ${bagLabel(produce, b.item)}'),
                            subtitle: Text([
                              fmtDateDisplay(b.date),
                              if (b.fromEmail) 'Crown Bag ${b.reference ?? 'invoice'}' else if ((b.reference ?? '').isNotEmpty) b.reference!,
                              if (b.date.compareTo(kBagsFrom) < 0) 'before ${fmtDateDisplay(kBagsFrom)}: not counted',
                            ].join(' · ')),
                            // Invoice lines from email stay (they'd only come back on the next run).
                            trailing: b.fromEmail
                                ? const Icon(Icons.email_outlined, color: NaniniColors.muted)
                                : IconButton(
                                    tooltip: 'Delete',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => runOnce('delivery_bags.delete', () async {
                                      final ok = await confirmDialog(context,
                                          message: 'Delete ${_n(b.qty)} × ${bagLabel(produce, b.item)} received ${fmtDateDisplay(b.date)}?', confirmLabel: 'Delete', danger: true);
                                      if (!ok) return;
                                      await widget.repo.deleteBagPurchase(b.id);
                                    }),
                                  ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _balanceTile(String label, BagBalance b, {bool bold = false}) => ListTile(
        dense: true,
        title: Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
        subtitle: Text('Bought ${_n(b.bought)} · losses ${_n(b.losses)} · used ${_n(b.used)}'),
        trailing: Text(_n(b.available),
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: b.available < 0 ? NaniniColors.red : NaniniColors.ink)),
      );

  /// Bags or boxes received (a minus number: returned).
  Future<void> _add(BuildContext context) async {
    final kinds = bagKinds(produce);
    var item = kinds.first.key;
    var date = DateTime.now();
    final qty = TextEditingController();
    final ref = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: dialogTitleWithError('Add $_unit received', error),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: item,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: produce == ProduceType.pepper ? 'Box' : 'Bag'),
                  items: [for (final k in kinds) DropdownMenuItem(value: k.key, child: Text(k.label, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => item = v ?? item,
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('bags_qty'),
                  controller: qty,
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
                  decoration: InputDecoration(labelText: 'How many $_unit', helperText: 'A minus number for $_unit returned'),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2025), lastDate: DateTime(2100));
                    if (picked != null) setD(() => date = picked);
                  },
                  child: InputDecorator(decoration: const InputDecoration(labelText: 'Date'), child: Text(fmtDateDisplay(toDateStr(date)))),
                ),
                const SizedBox(height: 8),
                TextField(controller: ref, decoration: const InputDecoration(labelText: 'Invoice / reference (optional)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final n = int.tryParse(qty.text.trim()) ?? 0;
                if (n == 0) {
                  setD(() => error = 'Type how many $_unit');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final n = int.parse(qty.text.trim());
    try {
      await widget.repo.addBagPurchase(produce: produce, item: item, qty: n, date: toDateStr(date), reference: ref.text.trim().isEmpty ? null : ref.text.trim());
      if (context.mounted) showToast(context, 'Added ${_n(n)} × ${bagLabel(produce, item)}');
    } catch (e) {
      if (context.mounted) showProblem(context, 'Not added: $e');
    }
  }
}
