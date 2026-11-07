import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'bag_stock.dart' show harvestSeasonStart, kBagsFrom;
import 'delivery_market_agents_screen.dart';
import 'delivery_models.dart';
import 'delivery_repository.dart';
import 'pallet_stock.dart';

/// Packaging > Pallets: the pallets sent to each market agent on the potato
/// delivery notes (this harvest season and all); pallets collected at an
/// agent (typed in here) against the pallets it paid for (Green Network's
/// pallet invoices), and the difference.
class DeliveryPalletsScreen extends StatefulWidget {
  const DeliveryPalletsScreen({super.key, required this.repo});
  final DeliveryRepository repo;
  @override
  State<DeliveryPalletsScreen> createState() => _DeliveryPalletsScreenState();
}

class _DeliveryPalletsScreenState extends State<DeliveryPalletsScreen> {
  late final _notes = widget.repo.watchNotes();
  late final _entries = widget.repo.watchPurchases();
  List<MarketAgent> agents = [];
  List<PalletsPaidFor> paid = [];

  @override
  void initState() {
    super.initState();
    _loadAgents();
    _loadPaid();
  }

  Future<void> _loadPaid() async {
    final p = await widget.repo.fetchPalletsPaidFor();
    if (mounted) setState(() => paid = p);
  }

  // The same list as a delivery note's Customer, so pallets collected and
  // pallets returned are counted under the same name.
  Future<void> _loadAgents() async {
    final a = await widget.repo.fetchCustomerChoices();
    if (mounted) setState(() => agents = [...a]..sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase())));
  }

  static String _n(int v) => (v < 0 ? '-' : '') + '${v.abs()}'.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DeliveryNote>>(
        stream: _notes,
        builder: (context, noteSnap) {
          final notes = noteSnap.data ?? const <DeliveryNote>[];
          // This harvest season: since the last 3-month break.
          final from = harvestSeasonStart([for (final n in notes) if (n.produceType == 'potato' && n.total > 0) n.noteDate]) ?? kBagsFrom;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sentCard(palletsSentByAgent(notes, from: from), from),
              const SizedBox(height: 12),
              StreamBuilder<List<PalletPurchase>>(
                stream: _entries,
                builder: (context, snap) => _collectedCard(
                    {for (final e in palletsSentByAgent(notes, from: from).entries) e.key: e.value.$1}, snap.data ?? const [], from),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => runOnce('pallets.add', () => _add(context, PalletEntryKind.collected)),
                    icon: const Icon(Icons.add),
                    label: const Text('Add collected'),
                  ),
                  MarketAgentsButton(repo: widget.repo, onDone: _loadAgents),
                ],
              ),
            ],
          );
        },
    );
  }

  /// Pallets sent loaded to each agent (the potato delivery notes): this
  /// season and all.
  Widget _sentCard(Map<String, (int, int)> sent, String from) {
    Widget row(String name, int season, int all, {bool bold = false}) {
      final style = TextStyle(fontWeight: bold ? FontWeight.w700 : null);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(children: [
          Expanded(child: Text(name, style: style)),
          SizedBox(width: 90, child: Text(_n(season), textAlign: TextAlign.right, style: style)),
          SizedBox(width: 90, child: Text(_n(all), textAlign: TextAlign.right, style: style)),
        ]),
      );
    }

    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Pallets sent to each agent', style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: [
            const Expanded(child: SizedBox()),
            SizedBox(
                width: 90,
                child: Text('This season\n(${fmtDateDisplay(from)})', textAlign: TextAlign.right, style: const TextStyle(color: NaniniColors.muted, fontSize: 12))),
            const SizedBox(width: 90, child: Text('All', textAlign: TextAlign.right, style: TextStyle(color: NaniniColors.muted, fontSize: 12))),
          ]),
        ),
        for (final e in sent.entries) row(e.key, e.value.$1, e.value.$2),
        if (sent.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No pallets sent yet.')),
        const Divider(height: 1),
        row('Total', sent.values.fold(0, (s, v) => s + v.$1), sent.values.fold(0, (s, v) => s + v.$2), bold: true),
        const SizedBox(height: 6),
      ]),
    );
  }

  /// Per agent this season: pallets sent, collected, paid for, and the
  /// difference (collected - sent + paid for) -- and each pallet invoice.
  Widget _collectedCard(Map<String, int> sent, List<PalletPurchase> entries, String from) {
    final rows = palletsCollectedAndPaidFor(sent, entries, paid, from: from);
    const head = TextStyle(color: NaniniColors.muted, fontSize: 12);
    Widget cell(String text, double width, TextStyle style) => SizedBox(width: width, child: Text(text, textAlign: TextAlign.right, style: style));
    Widget row(String name, (int, int, int, int) v, {bool bold = false}) {
      final style = TextStyle(fontWeight: bold ? FontWeight.w700 : null);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(children: [
          Expanded(child: Text(name, style: style)),
          cell(_n(v.$1), 58, style),
          cell(_n(v.$2), 66, style),
          cell(_n(v.$3), 58, style),
          cell(_n(v.$4), 72, style.copyWith(color: v.$4 < 0 ? NaniniColors.red : null)),
        ]),
      );
    }

    final total = rows.values.fold((0, 0, 0, 0), (t, v) => (t.$1 + v.$1, t.$2 + v.$2, t.$3 + v.$3, t.$4 + v.$4));
    final invoices = [...paid.where((p) => p.date.compareTo(from) >= 0)]..sort((a, b) => b.date.compareTo(a.date));
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text('Pallets collected and paid for', style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Text('This season (from ${fmtDateDisplay(from)}). Difference = collected - sent + paid for: minus is still out at the agent.',
              style: head),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: [
            const Expanded(child: SizedBox()),
            cell('Sent', 58, head),
            cell('Collected', 66, head),
            cell('Paid for', 58, head),
            cell('Difference', 72, head),
          ]),
        ),
        for (final e in rows.entries) row(e.key, e.value),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No pallets sent, collected or paid for this season.')),
        const Divider(height: 1),
        row('Total', total, bold: true),
        if (invoices.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Text('Paid for (the agent\'s pallet invoices)', style: head),
          ),
          for (final p in invoices)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
              child: Text('${fmtDateDisplay(p.date)} · ${p.agentName} · ${p.document} · ${_n(p.qty)} pallets · ${fmtRCents(p.amount)}',
                  style: const TextStyle(fontSize: 13)),
            ),
        ],
        const SizedBox(height: 8),
      ]),
    );
  }

  /// Pallets collected at an agent (a minus number: returned empty), an
  /// adjustment (plus or minus, with why) or a floor count.
  Future<void> _add(BuildContext context, PalletEntryKind kind) async {
    if (agents.isEmpty) await _loadAgents();
    if (!context.mounted) return;
    if (agents.isEmpty) return showProblem(context, "The market agents haven't loaded -- check the internet connection and try again.");
    var agent = agents.first.name;
    var date = DateTime.now();
    final qty = TextEditingController();
    final note = TextEditingController();
    String? error;
    final (title, qtyLabel, help, noteLabel) = switch (kind) {
      PalletEntryKind.collected => ('Add pallets collected', 'How many pallets', 'Empty pallets collected at the agent; a minus number for pallets returned empty', 'Note (optional)'),
      PalletEntryKind.adjust => ('Adjust pallets', 'How many pallets', 'Plus to add, minus to take off (broken, lost)', 'Why (e.g. broken, lost)'),
      PalletEntryKind.count => ('Floor count', 'How many of its pallets on the floor', 'From the end of this day the number starts from this count', 'Note (optional)'),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: dialogTitleWithError(title, error),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: agent,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Market agent'),
                items: [for (final a in agents) DropdownMenuItem(value: a.name, child: Text(a.name, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => agent = v ?? agent,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('pallets_qty'),
                controller: qty,
                keyboardType: TextInputType.numberWithOptions(signed: kind != PalletEntryKind.count),
                inputFormatters: [kind == PalletEntryKind.count ? FilteringTextInputFormatter.digitsOnly : FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
                decoration: InputDecoration(labelText: qtyLabel, helperText: help, helperMaxLines: 2),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (picked != null) setD(() => date = picked);
                },
                child: InputDecorator(decoration: const InputDecoration(labelText: 'Date'), child: Text(fmtDateDisplay(toDateStr(date)))),
              ),
              const SizedBox(height: 8),
              TextField(key: const Key('pallets_note'), controller: note, decoration: InputDecoration(labelText: noteLabel)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final n = int.tryParse(qty.text.trim());
                if (n == null || (n == 0 && kind != PalletEntryKind.count)) return setD(() => error = 'Type how many pallets');
                if (kind == PalletEntryKind.adjust && note.text.trim().isEmpty) return setD(() => error = 'Say why (e.g. broken, lost)');
                Navigator.pop(ctx, true);
              },
              child: Text(kind == PalletEntryKind.count ? 'Save count' : 'Add'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final n = int.parse(qty.text.trim());
    try {
      await widget.repo.addPalletEntry(
          agentName: agent, qty: n, date: toDateStr(date), kind: kind, description: note.text.trim().isEmpty ? null : note.text.trim());
      if (context.mounted) {
        showToast(context, '${kind == PalletEntryKind.count ? 'Counted' : kind == PalletEntryKind.adjust ? 'Adjusted' : 'Added'} ${_n(n)} pallets · $agent');
      }
    } catch (e) {
      if (context.mounted) showProblem(context, 'Not saved: $e');
    }
  }
}
