import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../theme/nanini_theme.dart';
import '../delivery/delivery_models.dart';
import 'potato_fields.dart';
import 'sales_data.dart';

/// Sales > Summary, potatoes: per field the bags harvested (sent to market,
/// and packed but not sent) and what they sold for, each with a chart; and
/// the pallets packed but not sent, entered here.
class PotatoFieldsSection extends StatelessWidget {
  const PotatoFieldsSection({super.key, required this.data, required this.fields, required this.from, required this.to, this.salesLoading = false});
  final SalesData data;
  final PotatoFields fields;
  final DateTime from;
  final DateTime to;

  /// The account sales' line items are still being fetched.
  final bool salesLoading;

  static const _sentColor = NaniniColors.rust;
  static const _unsentColor = NaniniColors.amber;
  static const _unknownColor = NaniniColors.muted;

  @override
  Widget build(BuildContext context) {
    final list = fields.fields;
    final unsent = (data.unsent ?? const <UnsentPallets>[]).where((u) {
      final d = DateTime.tryParse(u.date);
      return d != null && !d.isBefore(from) && !d.isAfter(to);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final title = Theme.of(context).textTheme.titleMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('Harvested by field', style: title),
        const SizedBox(height: 4),
        const Text('Bags packed per field: sent to market on approved delivery notes, and packed but not sent.',
            style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
        const SizedBox(height: 12),
        if (list.every((f) => f.harvestedBags == 0))
          const Text('No bags with a field in this period.', style: TextStyle(color: NaniniColors.muted))
        else ...[
          _legend([('Sent to market', _sentColor), ('Packed, not sent', _unsentColor)]),
          const SizedBox(height: 8),
          _barChart(
            [for (final f in list) if (f.harvestedBags > 0) (f.name, [(f.sentBags.toDouble(), _sentColor), (f.unsentBags.toDouble(), _unsentColor)])],
            (v) => _n(v),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _table(
                ['Field', 'Sent', 'Not sent', 'Total', '%'],
                [
                  for (final f in list)
                    if (f.harvestedBags > 0)
                      [f.name, _n(f.sentBags), _n(f.unsentBags), _n(f.harvestedBags), _pct(f.harvestedBags, fields.harvestedBags)],
                ],
                total: ['Total', _n(fields.sentBags), _n(fields.unsentBags), _n(fields.harvestedBags), '100%'],
                flex: const [1.3, 1, 1, 1, 0.7],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text('Sales by field', style: title),
        const SizedBox(height: 4),
        const Text(
            'An account sale goes on a field through the delivery note on its agent\'s payment summary. '
            'Until it is paid, its field is not known yet. Pallets not sent are not in the sales or the prices.',
            style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
        const SizedBox(height: 12),
        if (salesLoading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
        else if (fields.totalNett == 0 && fields.totalBagsSold == 0)
          const Text('No potato sales in this period.', style: TextStyle(color: NaniniColors.muted))
        else ...[
          _barChart(
            [
              for (final f in list)
                if (f.nett != 0) (f.name, [(f.nett, _sentColor)]),
              if (fields.unknownNett != 0) ('Not known', [(fields.unknownNett, _unknownColor)]),
            ],
            (v) => fmtR(v),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _table(
                ['Field', 'Bags sold', 'Nett', 'Avg / bag', '%'],
                [
                  for (final f in list)
                    if (f.nett != 0 || f.bagsSold != 0)
                      [f.name, _n(f.bagsSold), fmtR(f.nett), f.avgPrice == null ? '' : fmtRCents(f.avgPrice), _pct(f.nett, fields.totalNett)],
                  if (fields.unknownNett != 0 || fields.unknownBags != 0)
                    [
                      'Field not known yet',
                      _n(fields.unknownBags),
                      fmtR(fields.unknownNett),
                      fields.unknownBags > 0 ? fmtRCents(fields.unknownNett / fields.unknownBags) : '',
                      _pct(fields.unknownNett, fields.totalNett),
                    ],
                ],
                total: [
                  'Total',
                  _n(fields.totalBagsSold),
                  fmtR(fields.totalNett),
                  fields.totalBagsSold > 0 ? fmtRCents(fields.totalNett / fields.totalBagsSold) : '',
                  '100%',
                ],
                flex: const [1.6, 1, 1.2, 1, 0.7],
                mutedRow: 'Field not known yet',
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Text('Packed, not sent', style: title)),
            if (!data.unsentMissing)
              OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: () => runOnce('potato_fields.add', () => _add(context)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text('Pallets packed from a field but not sent to market. They count in the bags harvested only.',
            style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
        const SizedBox(height: 8),
        if (data.unsentMissing)
          const Text('Run potato_unsent_pallets.sql in Supabase first.', style: TextStyle(color: NaniniColors.red))
        else if (unsent.isEmpty)
          const Text('None in this period.', style: TextStyle(color: NaniniColors.muted))
        else
          for (final u in unsent)
            Card(
              child: ListTile(
                title: Text('${u.field} · ${fmtDateDisplay(u.date)}'),
                subtitle: Text([
                  _sizes(u),
                  if ((u.reason ?? '').isNotEmpty) u.reason!,
                  if ((u.note ?? '').isNotEmpty) u.note!,
                ].join('\n')),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${_n(u.totalBags)} bags', style: const TextStyle(fontWeight: FontWeight.w600)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => runOnce('potato_fields.delete', () => _delete(context, u)),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  String _sizes(UnsentPallets u) => [
        for (final s in kPalletSizes)
          if ((u.pallets[s.key] ?? 0) > 0 || (u.bags[s.key] ?? 0) > 0)
            '${s.label}: ${[
              if ((u.pallets[s.key] ?? 0) > 0) '${u.pallets[s.key]} pallet${u.pallets[s.key] == 1 ? '' : 's'}',
              if ((u.bags[s.key] ?? 0) > 0) '${u.bags[s.key]} bags',
            ].join(' + ')}',
      ].join('\n');

  Future<void> _add(BuildContext context) async {
    final u = await showDialog<UnsentPallets>(context: context, builder: (_) => const UnsentPalletsDialog());
    if (u == null || !context.mounted) return;
    try {
      await data.repo.addUnsentPallets(u);
      await data.refresh();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _delete(BuildContext context, UnsentPallets u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('${u.field}, ${fmtDateDisplay(u.date)}: ${_n(u.totalBags)} bags not sent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || u.id == null || !context.mounted) return;
    try {
      await data.repo.deleteUnsentPallets(u.id!);
      await data.refresh();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  static String _n(num v) => fmtR(v).substring(1);
  static String _pct(num part, num whole) => whole == 0 ? '' : '${(part / whole * 100).toStringAsFixed(1)}%';

  Widget _legend(List<(String, Color)> items) => Wrap(
        spacing: 16,
        children: [
          for (final (label, color) in items)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
        ],
      );

  /// One bar per label, its parts stacked from the bottom.
  Widget _barChart(List<(String, List<(double, Color)>)> bars, String Function(double) fmt) {
    final maxY = bars.fold<double>(0, (m, b) => [m, b.$2.fold<double>(0, (s, p) => s + p.$1)].reduce((a, c) => a > c ? a : c));
    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 1 : maxY * 1.15,
          minY: 0,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => NaniniColors.ink,
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                '${bars[group.x].$1}\n${fmt(rod.toY)}',
                const TextStyle(color: NaniniColors.paper, fontSize: 12),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (v, meta) => Text(
                  fmt(bars[v.toInt()].$2.fold<double>(0, (s, p) => s + p.$1)),
                  style: const TextStyle(fontSize: 10, color: NaniniColors.muted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(bars[v.toInt()].$1.replaceFirst('Field ', 'F'), style: const TextStyle(fontSize: 11)),
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < bars.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  () {
                    var y = 0.0;
                    final stack = <BarChartRodStackItem>[];
                    for (final (v, c) in bars[i].$2) {
                      if (v <= 0) continue;
                      stack.add(BarChartRodStackItem(y, y + v, c));
                      y += v;
                    }
                    return BarChartRodData(
                      toY: y,
                      width: 22,
                      color: bars[i].$2.first.$2,
                      rodStackItems: stack.length > 1 ? stack : const [],
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    );
                  }(),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _table(List<String> head, List<List<String>> rows, {required List<String> total, required List<double> flex, String? mutedRow}) {
    const headStyle = TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12);
    Widget cell(String t, int i, {TextStyle? style, double v = 6}) => Padding(
          padding: EdgeInsets.symmetric(vertical: v),
          child: Text(t, textAlign: i == 0 ? TextAlign.left : TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        );
    return Table(
      columnWidths: {for (var i = 0; i < flex.length; i++) i: FlexColumnWidth(flex[i])},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: NaniniColors.line))),
          children: [for (var i = 0; i < head.length; i++) cell(head[i], i, style: headStyle, v: 8)],
        ),
        for (final r in rows)
          TableRow(children: [
            for (var i = 0; i < r.length; i++)
              cell(r[i], i,
                  style: r[0] == mutedRow
                      ? const TextStyle(color: NaniniColors.muted, fontStyle: FontStyle.italic)
                      : (i == 0 ? const TextStyle(fontWeight: FontWeight.w600) : null)),
          ]),
        TableRow(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: NaniniColors.line))),
          children: [for (var i = 0; i < total.length; i++) cell(total[i], i, style: const TextStyle(fontWeight: FontWeight.w700), v: 8)],
        ),
      ],
    );
  }
}

/// Entering pallets packed from a field but not sent to market.
class UnsentPalletsDialog extends StatefulWidget {
  const UnsentPalletsDialog({super.key});
  @override
  State<UnsentPalletsDialog> createState() => _UnsentPalletsDialogState();
}

class _UnsentPalletsDialogState extends State<UnsentPalletsDialog> {
  DateTime date = DateTime.now();
  String? field;
  String reason = kUnsentReasons.first;
  final note = TextEditingController();
  final pallets = {for (final s in kPalletSizes) s.key: TextEditingController()};
  final bags = {for (final s in kPalletSizes) s.key: TextEditingController()};
  String? error;

  @override
  void dispose() {
    note.dispose();
    for (final c in [...pallets.values, ...bags.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, int> _read(Map<String, TextEditingController> m) => {
        for (final e in m.entries)
          if ((int.tryParse(e.value.text.trim()) ?? 0) > 0) e.key: int.parse(e.value.text.trim()),
      };

  void _save() {
    final p = _read(pallets);
    final b = _read(bags);
    if (field == null) {
      setState(() => error = 'Choose the field.');
      return;
    }
    if (p.isEmpty && b.isEmpty) {
      setState(() => error = 'Enter the pallets (or bags) of at least one size.');
      return;
    }
    Navigator.pop(
      context,
      UnsentPallets(
        date: toDateStr(date),
        field: field!,
        pallets: p,
        bags: b,
        reason: reason,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _read(pallets);
    final b = _read(bags);
    final total = kPalletSizes.fold<int>(0, (s, sz) => s + (p[sz.key] ?? 0) * sz.bagsPerPallet + (b[sz.key] ?? 0));
    return AlertDialog(
      title: const Text('Packed, not sent'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: () => runOnce('potato_fields.date', () async {
                  final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (picked != null) setState(() => date = picked);
                }),
                child: Text('Packed on ${fmtDateDisplay(toDateStr(date))}'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: field,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Field'),
                items: [for (final f in kFieldNames) DropdownMenuItem(value: f, child: Text(f))],
                onChanged: (v) => setState(() => field = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: reason,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Why not sent'),
                items: [for (final r in kUnsentReasons) DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => reason = v ?? reason),
              ),
              const SizedBox(height: 12),
              const Row(children: [
                Expanded(flex: 3, child: Text('Size', style: TextStyle(color: NaniniColors.muted, fontSize: 12))),
                Expanded(flex: 1, child: Text('Pallets', style: TextStyle(color: NaniniColors.muted, fontSize: 12))),
                SizedBox(width: 8),
                Expanded(flex: 1, child: Text('Loose bags', style: TextStyle(color: NaniniColors.muted, fontSize: 12))),
              ]),
              for (final s in kPalletSizes)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text(s.label, style: const TextStyle(fontSize: 13))),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        key: Key('unsent_pallets_${s.key}'),
                        controller: pallets[s.key],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(isDense: true, hintText: '0'),
                        onChanged: (_) => setState(() => error = null),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        key: Key('unsent_bags_${s.key}'),
                        controller: bags[s.key],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(isDense: true, hintText: '0'),
                        onChanged: (_) => setState(() => error = null),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 12),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
              const SizedBox(height: 12),
              Text('$total bags', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: NaniniColors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
