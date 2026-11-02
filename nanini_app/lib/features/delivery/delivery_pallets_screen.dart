import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'bag_stock.dart' show harvestSeasonStart, kBagsFrom, kFewTrucksLeft, trucksLeft;
import 'delivery_market_agents_screen.dart';
import 'delivery_models.dart';
import 'delivery_repository.dart';
import 'pallet_stock.dart';

/// Packaging > Pallets: the pallets on the floor, per market agent -- as
/// Bags/Boxes. Each agent: its name and number; tapped, the last floor
/// count, pallets collected empty there, less 8% not useable, adjustments
/// and pallets returned
/// loaded (the potato delivery notes). Collected, adjustments and floor
/// counts are typed in here.
class DeliveryPalletsScreen extends StatefulWidget {
  const DeliveryPalletsScreen({super.key, required this.repo});
  final DeliveryRepository repo;
  @override
  State<DeliveryPalletsScreen> createState() => _DeliveryPalletsScreenState();
}

class _DeliveryPalletsScreenState extends State<DeliveryPalletsScreen> {
  late final _entries = widget.repo.watchPurchases();
  late final _notes = widget.repo.watchNotes();
  List<MarketAgent> agents = [];

  @override
  void initState() {
    super.initState();
    _loadAgents();
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
    return StreamBuilder<List<PalletPurchase>>(
      stream: _entries,
      builder: (context, entrySnap) => StreamBuilder<List<DeliveryNote>>(
        stream: _notes,
        builder: (context, noteSnap) {
          final balances = palletBalances(entrySnap.data ?? const [], noteSnap.data ?? const []);
          final total = PalletBalance.total(balances.values);
          // The average pallets a potato truck this harvest season (since the
          // last 3-month break), and how many trucks the pallets are enough for.
          final notes = noteSnap.data ?? const <DeliveryNote>[];
          final from = harvestSeasonStart([for (final n in notes) if (n.produceType == 'potato' && n.total > 0) n.noteDate]) ?? kBagsFrom;
          final (perTruck, trucks) = palletsPerTruck(notes, from: from);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Column(children: [
                  for (final e in balances.entries) _balanceTile(e.key, e.value, perTruck: perTruck, trucks: trucks, from: from),
                  if (balances.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No pallets yet.')),
                  const Divider(height: 1),
                  _balanceTile('Total', total, bold: true, perTruck: perTruck, trucks: trucks, from: from),
                ]),
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
                  OutlinedButton.icon(
                    onPressed: () => runOnce('pallets.adjust', () => _add(context, PalletEntryKind.adjust)),
                    icon: const Icon(Icons.tune),
                    label: const Text('Adjust'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => runOnce('pallets.count', () => _add(context, PalletEntryKind.count)),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Floor count'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Manage market agents (admin)',
                    onPressed: () => runOnce('pallets.agents', () async {
                      if (!await requireAdmin(context)) return;
                      if (!context.mounted) return;
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryMarketAgentsScreen(repo: widget.repo)));
                      await _loadAgents();
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _sentCard(palletsSentByAgent(notes, from: from), from),
            ],
          );
        },
      ),
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

  /// An agent: its name and the pallets on the floor; tapped, how it's made
  /// up, each on its own line.
  Widget _balanceTile(String label, PalletBalance b, {bool bold = false, double perTruck = 0, int trucks = 0, String from = ''}) {
    final left = trucks == 0 ? null : trucksLeft(b.onFloor, perTruck);
    String one(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    Widget line(String text, int n, {bool strong = false}) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
          child: Row(children: [
            Expanded(child: Text(text, style: TextStyle(fontWeight: strong ? FontWeight.w700 : null))),
            Text(_n(n), style: TextStyle(fontWeight: strong ? FontWeight.w700 : null, color: n < 0 ? NaniniColors.red : NaniniColors.ink)),
          ]),
        );
    return ExpansionTile(
      key: PageStorageKey('pallets_$label'),
      dense: true,
      title: Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
      subtitle: left == null
          ? null
          : Text.rich(TextSpan(children: [
              TextSpan(text: 'Avg ${_n(perTruck.round())} a truck'),
              TextSpan(text: '  ·  ≈ ${one(left)} trucks left', style: TextStyle(fontWeight: FontWeight.w700, color: left <= kFewTrucksLeft ? NaniniColors.red : NaniniColors.ink)),
            ]), style: const TextStyle(color: NaniniColors.muted)),
      trailing: Text(_n(b.onFloor), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: b.onFloor < 0 ? NaniniColors.red : NaniniColors.ink)),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        if (b.counted != null) line(b.countDate == null ? 'Stock take' : 'Stock take ${fmtDateDisplay(b.countDate)}', b.counted!),
        line('Add collected', b.collected),
        line('Less not useable ($kPalletLossText)', -b.losses),
        if (b.adjusted != 0) line('Adjustments', b.adjusted),
        line('Less returned loaded', -b.returned),
        const Divider(height: 8, indent: 16, endIndent: 16),
        line('On the floor', b.onFloor, strong: true),
        if (left != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Text('Average ${one(perTruck)} pallets a potato truck ($trucks trucks this season, since ${fmtDateDisplay(from)}): enough for about ${one(left)} trucks',
                style: const TextStyle(color: NaniniColors.muted)),
          ),
      ],
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
