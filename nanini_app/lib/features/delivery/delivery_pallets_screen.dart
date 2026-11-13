import 'dart:io';

import 'package:file_picker/file_picker.dart';
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
import 'pallet_report_xlsx.dart';
import 'pallet_stock.dart';

/// Packaging > Pallets: the pallets sent to each market agent on the potato
/// delivery notes (this harvest season and all); pallets collected at an
/// agent (typed in here) against the pallets it paid for (Green Network's
/// pallet invoices), and the difference.
class DeliveryPalletsScreen extends StatefulWidget {
  const DeliveryPalletsScreen({super.key, required this.repo, this.save});
  final DeliveryRepository repo;

  /// Saves an exported file (name, bytes); null: asks where (tests pass their own).
  final Future<bool> Function(String name, Uint8List bytes)? save;
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
                    {for (final e in palletsSentByAgent(notes, from: from).entries) e.key: e.value.$1}, snap.data ?? const [], from, notes),
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

  /// Per agent this season: pallets collected, returned (sent loaded, the
  /// delivery notes), paid for, and the difference (collected - returned +
  /// paid for). Tap a number: how it's made up; tap a name: export.
  Widget _collectedCard(Map<String, int> sent, List<PalletPurchase> entries, String from, List<DeliveryNote> notes) {
    final rows = palletsCollectedAndPaidFor(sent, entries, paid, from: from);
    const head = TextStyle(color: NaniniColors.muted, fontSize: 12);
    Widget col(Widget child) => Expanded(child: Align(alignment: Alignment.centerRight, child: child));
    // A number to tap: the lines behind it.
    Widget tap(String text, TextStyle style, String key, VoidCallback onTap) => col(InkWell(
          key: Key(key),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Text(text,
                textAlign: TextAlign.right,
                style: style.copyWith(decoration: TextDecoration.underline, decorationColor: NaniniColors.muted, decorationStyle: TextDecorationStyle.dotted)),
          ),
        ));
    Widget row(String name, (int, int, int, int) v, {bool bold = false, String? agent}) {
      final style = TextStyle(fontWeight: bold ? FontWeight.w700 : null, fontSize: 15);
      final who = agent ?? 'all';
      void show(PalletFigure f) => _showLines(f, v, notes: notes, entries: entries, from: from, agent: agent);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // The agent on its own line, in full: tap it to export its movements.
          agent == null
              ? Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))
              : InkWell(
                  key: Key('pallets_agent_$agent'),
                  onTap: () => _agentMenu(agent, notes: notes, entries: entries, from: from),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(child: Text(name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: NaniniColors.rustDark))),
                      const Icon(Icons.ios_share, size: 18, color: NaniniColors.muted),
                    ]),
                  ),
                ),
          Row(children: [
            tap(_n(v.$2), style, 'pallets_collected_$who', () => show(PalletFigure.collected)),
            tap(_n(v.$1), style, 'pallets_returned_$who', () => show(PalletFigure.sent)),
            tap(_n(v.$3), style, 'pallets_paid_$who', () => show(PalletFigure.paidFor)),
            tap(_n(v.$4), style.copyWith(color: v.$4 < 0 ? NaniniColors.red : null), 'pallets_difference_$who', () => _showDifference(name, v)),
          ]),
        ]),
      );
    }

    final total = rows.values.fold((0, 0, 0, 0), (t, v) => (t.$1 + v.$1, t.$2 + v.$2, t.$3 + v.$3, t.$4 + v.$4));
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text('Pallets collected and paid for', style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Text(
              'This season (from ${fmtDateDisplay(from)}). Returned = sent loaded on the delivery notes. '
              'Difference = collected - returned + paid for: minus is still out at the agent. '
              'Tap a number to see how it is made up, an agent for its pallet reconciliation (Excel, to send to the agent).',
              style: head),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(children: [
            for (final h in ['Collected', 'Returned', 'Paid for', 'Difference']) col(Text(h, textAlign: TextAlign.right, style: head)),
          ]),
        ),
        for (final e in rows.entries) ...[row(e.key, e.value, agent: e.key), const Divider(height: 1, indent: 16, endIndent: 16)],
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No pallets returned, collected or paid for this season.')),
        row('Total', total, bold: true),
        const SizedBox(height: 8),
      ]),
    );
  }

  /// Tapping an agent: export its pallet movements (this season or all).
  Future<void> _agentMenu(String agent, {required List<DeliveryNote> notes, required List<PalletPurchase> entries, required String from}) async {
    final all = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(agent, style: Theme.of(ctx).textTheme.titleMedium)),
          ListTile(
            key: const Key('pallets_export_season'),
            leading: const Icon(Icons.download),
            title: const Text('Pallet reconciliation: this season'),
            subtitle: Text('From ${fmtDateDisplay(from)} to today, as an Excel report to send to the agent'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            key: const Key('pallets_export_all'),
            leading: const Icon(Icons.download),
            title: const Text('Pallet reconciliation: all'),
            subtitle: const Text('Every delivery note, collected entry and pallet invoice, as an Excel report'),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ]),
      ),
    );
    if (all == null || !mounted) return;
    final today = toDateStr(DateTime.now());
    final rec = palletReconciliation(agent, notes: notes, entries: entries, paid: paid, from: all ? null : from, to: today);
    final safe = agent.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    final name = 'Pallet movement reconciliation - $safe - ${all ? 'to' : '$from to'} $today.xlsx';
    try {
      final bytes = Uint8List.fromList(palletReconciliationXlsx(rec, preparedOn: today));
      final saved = widget.save != null ? await widget.save!(name, bytes) : await _saveFile(name, bytes);
      if (saved && mounted) showToast(context, 'Saved the pallet reconciliation for $agent: ${rec.balance} pallets still at the agent');
    } catch (e) {
      if (mounted) await showProblem(context, friendlyDbError(e), title: 'Could not save');
    }
  }

  static Future<bool> _saveFile(String name, Uint8List bytes) async {
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Save $name', fileName: name, type: FileType.custom, allowedExtensions: const ['xlsx'], bytes: bytes);
    if (path == null) return false;
    // Windows and the desktop only give the path: write it here.
    if (!Platform.isAndroid && !Platform.isIOS) await File(path).writeAsBytes(bytes);
    return true;
  }

  /// The delivery notes, collected entries or pallet invoices behind a
  /// figure of [agent] (null: every agent), with their total.
  Future<void> _showLines(PalletFigure figure, (int, int, int, int) v,
      {required List<DeliveryNote> notes, required List<PalletPurchase> entries, required String from, String? agent}) {
    final lines = palletLines(figure, notes: notes, entries: entries, paid: paid, from: from, agent: agent);
    final (title, empty) = switch (figure) {
      PalletFigure.sent => ('Returned', 'No pallets sent loaded on the potato delivery notes this season.'),
      PalletFigure.collected => ('Collected', 'No pallets collected this season (Add collected below).'),
      PalletFigure.paidFor => ('Paid for', 'No pallet invoices from this agent this season.'),
    };
    final sum = lines.fold(0, (s, l) => s + l.pallets);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('$title -- ${agent ?? 'all agents'}', style: Theme.of(ctx).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('This season, from ${fmtDateDisplay(from)}', style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
            ),
            if (lines.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(empty)),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final l in lines)
                  ListTile(
                    dense: true,
                    title: Text(l.what),
                    subtitle: Text(agent == null ? '${fmtDateDisplay(l.date)} · ${l.agent}' : fmtDateDisplay(l.date)),
                    trailing: Text(_n(l.pallets), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
            const Divider(height: 1),
            ListTile(
              title: Text('Total: ${lines.length} line${lines.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Text('${_n(sum)} pallets', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }

  /// How the difference is worked out: collected - sent + paid for.
  Future<void> _showDifference(String name, (int, int, int, int) v) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          Widget line(String label, String value, {bool bold = false, Color? color}) => ListTile(
                dense: true,
                title: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null)),
                trailing: Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w600, color: color)),
              );
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Difference -- $name', style: Theme.of(ctx).textTheme.titleMedium),
              ),
              line('Collected', _n(v.$2)),
              line('less Returned (sent loaded)', '-${_n(v.$1)}'),
              line('plus Paid for', '+${_n(v.$3)}'),
              const Divider(height: 1),
              line('= Difference', _n(v.$4), bold: true, color: v.$4 < 0 ? NaniniColors.red : null),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                    v.$4 < 0
                        ? '${_n(-v.$4)} pallet${v.$4 == -1 ? ' is' : 's are'} still out at the agent (returned loaded, but not collected back or paid for).'
                        : v.$4 == 0
                            ? 'Every pallet sent is back or paid for.'
                            : '${_n(v.$4)} more collected or paid for than returned.',
                    style: const TextStyle(color: NaniniColors.muted)),
              ),
            ]),
            ),
          );
        },
      );

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
