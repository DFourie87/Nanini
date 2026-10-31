import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../sales/potato_fields.dart';
import 'bag_stock.dart';
import 'delivery_models.dart';
import 'delivery_repository.dart';

/// Packaging > Bags/Boxes: the potato bags, pepper boxes and butternut bags
/// on the floor to pack -- bought, less losses (1%; pepper boxes 0.25%), plus
/// adjustments, less what's loaded on the trucks (and potatoes packed but
/// not sent) (from 1 Feb 2026,
/// or the last floor count). Crown Bag's potato bag invoices come in from
/// email (scripts/fetch_crown_bags.py on the office PC); the rest is typed
/// in here, with adjustments (opening stock, losses) and floor counts.
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

  /// Potato pallets packed but not sent (Sales > Summary); read each time
  /// the tab opens.
  List<UnsentPallets> _unsent = const [];

  @override
  void initState() {
    super.initState();
    widget.repo.fetchUnsentPallets().then((u) {
      if (mounted) setState(() => _unsent = u);
    }, onError: (Object e) => debugPrint('Bags: unsent pallets: $e'));
  }

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
            final balances = bagBalances(produce, purchases, notes, unsent: _unsent);
            final kinds = bagKinds(produce);
            final total = BagBalance.total(balances.values);
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
                Text(
                    'Bought, less ${bagLossesText(produce)} for losses, plus adjustments, less what\'s loaded on the trucks (delivery notes)'
                    '${produce == ProduceType.potato ? ' and packed but not sent (Sales > Summary)' : ''} -- '
                    'from ${fmtDateDisplay(kBagsFrom)}, or from the last floor count.',
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => runOnce('delivery_bags.add', () => _add(context, BagEntryKind.bought)),
                      icon: const Icon(Icons.add),
                      label: Text('Add $_unit received'),
                    ),
                    // Opening stock, losses, damage: plus or minus, with why.
                    OutlinedButton.icon(
                      onPressed: () => runOnce('delivery_bags.adjust', () => _add(context, BagEntryKind.adjust)),
                      icon: const Icon(Icons.tune),
                      label: const Text('Adjust'),
                    ),
                    // What's really on the floor: the number starts from it.
                    OutlinedButton.icon(
                      onPressed: () => runOnce('delivery_bags.count', () => _add(context, BagEntryKind.count)),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Floor count'),
                    ),
                  ],
                ),
                if (produce == ProduceType.potato)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Crown Bag\'s invoices come in from email: run scripts\\fetch_crown_bags.py on the office PC.',
                        style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
                  ),
                const SizedBox(height: 20),
                Text('Received, adjusted and counted', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (received.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Nothing yet.', style: const TextStyle(color: NaniniColors.muted)))
                else
                  Card(
                    child: Column(
                      children: [
                        for (final b in received) _entryTile(context, b, balances[b.item]),
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

  /// A bag: its name and the number on the floor; tapped, how it's made up,
  /// each on its own line.
  Widget _balanceTile(String label, BagBalance b, {bool bold = false}) {
    Widget line(String text, int n, {bool strong = false}) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
          child: Row(children: [
            Expanded(child: Text(text, style: TextStyle(fontWeight: strong ? FontWeight.w700 : null))),
            Text(_n(n), style: TextStyle(fontWeight: strong ? FontWeight.w700 : null, color: n < 0 ? NaniniColors.red : NaniniColors.ink)),
          ]),
        );
    return ExpansionTile(
      key: PageStorageKey('bags_${produce.name}_$label'),
      dense: true,
      title: Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
      trailing: Text(_n(b.available),
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: b.available < 0 ? NaniniColors.red : NaniniColors.ink)),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        if (b.counted != null) line(b.countDate == null ? 'Stock take' : 'Stock take ${fmtDateDisplay(b.countDate)}', b.counted!),
        line('Add purchases', b.bought),
        line('Less losses (${bagLossesText(produce)})', -b.losses),
        if (b.adjusted != 0) line('Adjustments', b.adjusted),
        // Loaded on the trucks and packed but not sent, together.
        line('Less used', -(b.used + b.packed)),
        const Divider(height: 8, indent: 16, endIndent: 16),
        line('On the floor', b.available, strong: true),
      ],
    );
  }

  Widget _entryTile(BuildContext context, BagPurchase b, BagBalance? balance) {
    final label = bagLabel(produce, b.item);
    final title = switch (b.kind) {
      BagEntryKind.bought => '${_n(b.qty)} × $label',
      BagEntryKind.adjust => 'Adjusted ${b.qty > 0 ? '+' : ''}${_n(b.qty)} × $label',
      BagEntryKind.count => 'Counted ${_n(b.qty)} × $label',
    };
    final countDate = balance?.countDate;
    final beforeCount = countDate != null && b.date.compareTo(countDate) <= 0 && !(b.kind == BagEntryKind.count && b.date == countDate && b.qty == balance!.counted);
    return ListTile(
      dense: true,
      title: Text(title),
      subtitle: Text([
        fmtDateDisplay(b.date),
        if (b.fromEmail) 'Crown Bag ${b.reference ?? 'invoice'}' else if ((b.reference ?? '').isNotEmpty) b.reference!,
        if (b.kind != BagEntryKind.bought && (b.description ?? '').isNotEmpty) b.description!,
        if (beforeCount)
          'before the floor count: not in the number'
        else if (countDate == null && b.date.compareTo(kBagsFrom) < 0)
          'before ${fmtDateDisplay(kBagsFrom)}: not counted',
      ].join(' · ')),
      // Invoice lines from email stay (they'd only come back on the next run).
      trailing: b.fromEmail
          ? const Icon(Icons.email_outlined, color: NaniniColors.muted)
          : IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => runOnce('delivery_bags.delete', () async {
                final ok = await confirmDialog(context, message: 'Delete "$title" of ${fmtDateDisplay(b.date)}?', confirmLabel: 'Delete', danger: true);
                if (!ok) return;
                await widget.repo.deleteBagPurchase(b.id);
              }),
            ),
    );
  }

  /// Bags or boxes received (a minus number: returned), an adjustment (plus
  /// or minus, with why) or a floor count.
  Future<void> _add(BuildContext context, BagEntryKind kind) async {
    final kinds = bagKinds(produce);
    var item = kinds.first.key;
    var date = DateTime.now();
    final qty = TextEditingController();
    final note = TextEditingController();
    String? error;
    final (title, qtyLabel, help, noteLabel) = switch (kind) {
      BagEntryKind.bought => ('Add $_unit received', 'How many $_unit', 'A minus number for $_unit returned', 'Invoice / reference (optional)'),
      BagEntryKind.adjust => ('Adjust $_unit', 'How many $_unit', 'Plus to add (e.g. opening stock), minus to take off (losses, damaged)', 'Why (e.g. opening stock, losses)'),
      BagEntryKind.count => ('Floor count', 'How many $_unit on the floor', 'From the end of this day the number starts from this count', 'Note (optional)'),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: dialogTitleWithError(title, error),
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
                  keyboardType: TextInputType.numberWithOptions(signed: kind != BagEntryKind.count),
                  inputFormatters: [kind == BagEntryKind.count ? FilteringTextInputFormatter.digitsOnly : FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
                  decoration: InputDecoration(labelText: qtyLabel, helperText: help, helperMaxLines: 2),
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
                TextField(key: const Key('bags_note'), controller: note, decoration: InputDecoration(labelText: noteLabel)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final n = int.tryParse(qty.text.trim());
                if (n == null || (n == 0 && kind != BagEntryKind.count)) {
                  setD(() => error = 'Type how many $_unit');
                  return;
                }
                if (kind == BagEntryKind.adjust && note.text.trim().isEmpty) {
                  setD(() => error = 'Say why (e.g. opening stock, losses)');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(kind == BagEntryKind.count ? 'Save count' : 'Add'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final n = int.parse(qty.text.trim());
    final text = note.text.trim().isEmpty ? null : note.text.trim();
    try {
      await widget.repo.addBagPurchase(
        produce: produce,
        item: item,
        qty: n,
        date: toDateStr(date),
        kind: kind,
        reference: kind == BagEntryKind.bought ? text : null,
        description: kind == BagEntryKind.bought ? null : text,
      );
      if (context.mounted) showToast(context, '${kind == BagEntryKind.count ? 'Counted' : kind == BagEntryKind.adjust ? 'Adjusted' : 'Added'} ${_n(n)} × ${bagLabel(produce, item)}');
    } catch (e) {
      if (context.mounted) showProblem(context, 'Not saved: $e');
    }
  }
}
