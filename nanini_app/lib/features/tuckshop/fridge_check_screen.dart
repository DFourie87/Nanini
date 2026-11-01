import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../capture/fridge_sheet_capture.dart' show isFridgeItemName;
import 'fridge_check.dart';
import 'tuckshop_models.dart';
import 'tuckshop_repository.dart';

/// Tuck Shop > Fridge check: every fridge count (wors, chicken pieces)
/// against the one before -- opening + bought - taken on the fridge sheets
/// and sales - written off = should be there; the count shows what's
/// missing. Counts come from the phone (Tuck shop > FRIDGE COUNT, on pay day
/// after the sheet) or are typed here.
class FridgeCheckScreen extends StatefulWidget {
  const FridgeCheckScreen({super.key, required this.repo, required this.farmId, required this.farmName, this.canWriteOff = false});
  final TuckshopRepository repo;
  final String farmId;
  final String farmName;

  /// May write a shortage off the stock (the farm's tuck shop managers).
  final bool canWriteOff;
  @override
  State<FridgeCheckScreen> createState() => _FridgeCheckScreenState();
}

class _FridgeCheckScreenState extends State<FridgeCheckScreen> {
  late final _items = widget.repo.watchItems();
  late final _counts = widget.repo.watchCounts();
  late final _bought = widget.repo.watchStockPurchases();
  late final _sales = widget.repo.watchPurchases();
  late final _writeoffs = widget.repo.watchWriteoffs();

  static String _n(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NaniniAppBar(title: 'Fridge check -- ${widget.farmName}'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => runOnce('fridge_check.add', _addCount),
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Add count'),
      ),
      body: StreamBuilder<List<TuckshopItem>>(
        stream: _items,
        builder: (context, itemSnap) => StreamBuilder<List<TuckshopCount>>(
          stream: _counts,
          builder: (context, countSnap) => StreamBuilder<List<TuckshopStockPurchase>>(
            stream: _bought,
            builder: (context, boughtSnap) => StreamBuilder<List<TuckshopPurchase>>(
              stream: _sales,
              builder: (context, saleSnap) => StreamBuilder<List<TuckshopWriteoff>>(
                stream: _writeoffs,
                builder: (context, woSnap) {
                  if (!itemSnap.hasData) return const Center(child: CircularProgressIndicator());
                  final items = _fridgeItems(itemSnap.data!);
                  final checks = fridgeChecks(
                    items: items,
                    counts: countSnap.data ?? const [],
                    bought: boughtSnap.data ?? const [],
                    sales: saleSnap.data ?? const [],
                    writeoffs: woSnap.data ?? const [],
                  );
                  final byDay = <String, List<FridgeCheck>>{};
                  for (final c in checks) {
                    (byDay[c.closeDate] ??= []).add(c);
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                    children: [
                      if (countSnap.hasError || boughtSnap.hasError)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text("Counts can't be read yet -- run docs/sql/fridge_count.sql in Supabase.", style: TextStyle(color: NaniniColors.red)),
                        ),
                      const Text(
                        'On pay day, after the fridge sheet is photographed and before new stock goes in: count the fridge '
                        '(phone: Tuck shop > FRIDGE COUNT, or Add count here). Each count is checked against the one before.',
                        style: TextStyle(color: NaniniColors.muted),
                      ),
                      const SizedBox(height: 12),
                      if (items.isEmpty) const Text('No fridge items (wors, chicken) in this shop.'),
                      if (items.isNotEmpty && byDay.isEmpty) const Text('No counts yet.'),
                      for (final e in byDay.entries) _dayCard(e.key, e.value),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<TuckshopItem> _fridgeItems(List<TuckshopItem> all) =>
      [for (final i in all) if (i.farmId == widget.farmId && !i.archived && isFridgeItemName(i.name)) i]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Widget _dayCard(String day, List<FridgeCheck> checks) {
    final short = checks.fold(0.0, (s, c) => s + (c.short > 0 ? c.short * c.item.sellPrice : 0));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Expanded(child: Text('Count ${fmtDateDisplay(day)}', style: Theme.of(context).textTheme.titleMedium)),
            if (short > 0) Text('${fmtR(short)} short', style: const TextStyle(color: NaniniColors.red, fontWeight: FontWeight.w700)),
          ]),
        ),
        for (final c in checks) _checkTile(c),
      ]),
    );
  }

  Widget _checkTile(FridgeCheck c) {
    Widget line(String text, double n, {bool strong = false, Color? color}) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
          child: Row(children: [
            Expanded(child: Text(text, style: TextStyle(fontWeight: strong ? FontWeight.w700 : null))),
            Text(_n(n), style: TextStyle(fontWeight: strong ? FontWeight.w700 : null, color: color ?? NaniniColors.ink)),
          ]),
        );
    final (verdict, color) = c.isFirst
        ? ('First count: ${_n(c.counted)} -- the check starts here', NaniniColors.muted)
        : c.short > 0.001
            ? ('${_n(c.short)} short (${fmtR(c.short * c.item.sellPrice)})${c.shortWrittenOff ? ' -- written off' : ''}', NaniniColors.red)
            : c.short < -0.001
                ? ('${_n(-c.short)} more than expected', NaniniColors.amber)
                : ('All there', NaniniColors.green);
    return ExpansionTile(
      key: PageStorageKey('fridge_${c.item.id}_${c.closeDate}'),
      dense: true,
      title: Text(c.item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(verdict, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        if (!c.isFirst) ...[
          line('Opening (count ${fmtDateDisplay(c.openDate)})', c.opening!),
          line('Add bought', c.bought),
          line('Less taken (fridge sheets and sales)', -c.taken),
          if (c.writtenOff != 0) line('Less written off', -c.writtenOff),
          const Divider(height: 8, indent: 16, endIndent: 16),
          line('Should be in the fridge', c.shouldBe, strong: true),
        ],
        line('Counted ${fmtDateDisplay(c.closeDate)}', c.counted, strong: true),
        if (!c.isFirst && c.short.abs() > 0.001) line(c.short > 0 ? 'Short' : 'More than expected', c.short.abs(), strong: true, color: color),
        if (widget.canWriteOff && c.short > 0.001 && !c.shortWrittenOff)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => runOnce('fridge_check.writeoff', () => _writeOff(c)),
                icon: const Icon(Icons.remove_circle_outline),
                label: Text('Write off ${_n(c.short)} (stock matches the fridge)'),
              ),
            ),
          ),
      ],
    );
  }

  /// The shortage off the stock, so the stock matches what's in the fridge.
  Future<void> _writeOff(FridgeCheck c) async {
    try {
      await widget.repo.writeOff(item: c.item, qty: c.short, reason: shortWriteoffReason(c.closeDate));
      if (mounted) showToast(context, '${_n(c.short)} ${c.item.name} written off');
    } catch (e) {
      if (mounted) showToast(context, 'Could not write it off: $e', isError: true);
    }
  }

  /// A count typed in the hub: what's in the fridge on a day, per item.
  Future<void> _addCount() async {
    final items = _fridgeItems(await widget.repo.watchItems().first);
    if (!mounted) return;
    if (items.isEmpty) return showToast(context, 'No fridge items (wors, chicken) in this shop', isError: true);
    final ctrls = {for (final i in items) i.id: TextEditingController()};
    var date = DateTime.now();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: dialogTitleWithError('Fridge count', error),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2025), lastDate: DateTime.now());
                  if (picked != null) setD(() => date = picked);
                },
                child: InputDecorator(decoration: const InputDecoration(labelText: 'Date'), child: Text(fmtDateDisplay(toDateStr(date)))),
              ),
              for (final i in items)
                TextField(
                  key: Key('fridge_count_${i.id}'),
                  controller: ctrls[i.id],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: '${i.name} in the fridge'),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (ctrls.values.any((c) => c.text.trim().isEmpty)) return setD(() => error = 'Type a count for each (0 for none)');
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repo.addCounts(toDateStr(date), {for (final e in ctrls.entries) e.key: double.parse(e.value.text.trim())}, countedBy: 'Hub');
      if (mounted) showToast(context, 'Count saved');
    } catch (e) {
      if (mounted) showToast(context, 'Could not save the count: $e', isError: true);
    }
  }
}
