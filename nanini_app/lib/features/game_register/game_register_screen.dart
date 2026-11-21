import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'game_register_models.dart';
import 'game_register_repository.dart';
import 'game_register_xlsx.dart';

/// Hub > Financials > Game register: the game counted on each farm at the
/// year end (28 February) with its value per head, the totals and the fair
/// value movement on last year, started from last year's list; as Excel.
class GameRegisterScreen extends StatefulWidget {
  const GameRegisterScreen({super.key, this.repo, this.save, this.today});

  final GameRegisterRepository? repo;

  /// Tests: saves a file instead of the save dialog. True when saved.
  final Future<bool> Function(String name, Uint8List bytes)? save;
  final DateTime? today;

  @override
  State<GameRegisterScreen> createState() => _GameRegisterScreenState();
}

class _GameRegisterScreenState extends State<GameRegisterScreen> {
  late final GameRegisterRepository repo = widget.repo ?? GameRegisterRepository();
  late final DateTime today = widget.today ?? DateTime.now();
  late String yearStart = gameYearStart(toDateStr(today));
  List<GameCount>? all;
  ({int females, int males})? buffalo;
  String? problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await repo.fetchAll();
      final b = await repo.buffaloOnFarm();
      if (!mounted) return;
      setState(() {
        all = a;
        buffalo = b;
        problem = null;
      });
    } catch (e) {
      if (mounted) setState(() => problem = friendlyDbError(e));
    }
  }

  GameYear get year => GameYear(
    yearStart,
    [
      for (final r in all ?? const <GameCount>[])
        if (r.yearStart == yearStart) r,
    ],
    [
      for (final r in all ?? const <GameCount>[])
        if (r.yearStart == previousYear(yearStart)) r,
    ],
  );

  List<String> get years {
    final now = gameYearStart(toDateStr(today));
    final out = {now, for (final r in all ?? const <GameCount>[]) r.yearStart}.toList()..sort();
    return out.reversed.toList();
  }

  String _yearName(String s) => 'Count at 28 Feb ${DateTime.parse(s).year + 1}';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      appBar: const NaniniAppBar(title: 'Game register'),
      body: problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$problem\n\n(Run nanini_app/docs/sql/vat_control.sql once?)', textAlign: TextAlign.center),
              ),
            )
          : all == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(year, text)),
    );
  }

  Widget _body(GameYear y, TextTheme text) {
    final move = y.fairValueMovement;
    final lastRows = [
      for (final r in all!)
        if (r.yearStart == previousYear(yearStart)) r,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        DropdownButton<String>(
          key: const Key('game_year'),
          value: yearStart,
          items: [for (final s in years) DropdownMenuItem(value: s, child: Text(_yearName(s)))],
          onChanged: (v) => setState(() => yearStart = v ?? yearStart),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in y.farms) _line('$f (${y.farmHead(f)} head)', y.farmTotal(f)),
                const Divider(),
                _line('Total', y.total, bold: true),
                if (move != null) ...[
                  _line('Last year', y.lastTotal, color: NaniniColors.muted),
                  _line('Fair value movement', move, bold: true, color: move < 0 ? NaniniColors.red : null),
                ],
                if (buffalo != null && (buffalo!.females + buffalo!.males) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Buffalo register (Game breeding): ${buffalo!.females} female(s), ${buffalo!.males} male(s) on the farms now.',
                      style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (y.rows.isEmpty && lastRows.isNotEmpty)
              FilledButton.icon(
                key: const Key('game_from_last_year'),
                onPressed: () => runOnce('game_copy', () => _copyLastYear(lastRows)),
                icon: const Icon(Icons.copy_all),
                label: const Text('Start from last year\'s list'),
              ),
            OutlinedButton.icon(key: const Key('game_add'), onPressed: () => _edit(null, y), icon: const Icon(Icons.add), label: const Text('Add species')),
            OutlinedButton.icon(
              key: const Key('game_excel'),
              onPressed: y.rows.isEmpty ? null : () => runOnce('game_excel', () => _saveExcel(y)),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Game register (Excel)'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final f in y.farms)
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Text(f, style: text.titleSmall),
                ),
                for (final r in y.of(f))
                  ListTile(
                    key: Key('game_${r.farm}_${r.species}'),
                    dense: true,
                    title: Text(r.species),
                    subtitle: Text('${r.head} x ${fmtR(r.value)}${y.lastHead(f, r.species) == null ? '' : '  (last year ${y.lastHead(f, r.species)})'}'),
                    trailing: Text(fmtR(r.total)),
                    onTap: () => _edit(r, y),
                  ),
                Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 10), child: _line('Total', y.farmTotal(f), bold: true)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _line(String label, double value, {bool bold = false, Color? color}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(fmtR(value), style: style),
        ],
      ),
    );
  }

  Future<void> _copyLastYear(List<GameCount> last) async {
    if (await trySave(context, () => repo.saveAll([for (final r in last) r.copyWith(yearStart: yearStart)]))) await _load();
    if (mounted) showToast(context, 'Last year\'s list copied: put in this year\'s count and values');
  }

  Future<void> _edit(GameCount? r, GameYear y) async {
    final farm = TextEditingController(text: r?.farm ?? (y.farms.isEmpty ? '' : y.farms.first));
    final species = TextEditingController(text: r?.species ?? '');
    final head = TextEditingController(text: r == null ? '' : '${r.head}');
    final value = TextEditingController(text: r == null ? '' : r.value.toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r == null ? 'Add species' : '${r.species}, ${r.farm}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (r == null) ...[
              TextField(
                key: const Key('game_edit_farm'),
                controller: farm,
                decoration: const InputDecoration(labelText: 'Farm (e.g. PLAAS HAASKRAAL)'),
              ),
              TextField(
                key: const Key('game_edit_species'),
                controller: species,
                decoration: const InputDecoration(labelText: 'Species (e.g. Kudu)'),
              ),
            ],
            TextField(
              key: const Key('game_edit_head'),
              controller: head,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Head counted'),
            ),
            TextField(
              key: const Key('game_edit_value'),
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Value per head (R)'),
            ),
          ],
        ),
        actions: [
          if (r != null) TextButton(key: const Key('game_edit_delete'), onPressed: () => Navigator.pop(ctx, null), child: const Text('Remove')),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const Key('game_edit_save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == null && r?.id != null) {
      if (await confirmDialog(context, message: 'Remove ${r!.species} (${r.farm}) from this year?') && mounted) {
        if (await trySave(context, () => repo.delete(r.id!))) await _load();
      }
      return;
    }
    if (ok != true) return;
    final h = int.tryParse(head.text.trim());
    final v = double.tryParse(value.text.replaceAll(' ', '').replaceAll(',', ''));
    if (h == null || v == null || farm.text.trim().isEmpty || species.text.trim().isEmpty) {
      await showProblem(context, 'Give the farm, species, head counted and value per head.');
      return;
    }
    final row = r == null
        ? GameCount(
            yearStart: yearStart,
            farm: farm.text.trim(),
            species: species.text.trim(),
            head: h,
            value: v,
            ord: y.rows.fold(0, (m, x) => x.ord > m ? x.ord : m) + 1,
          )
        : r.copyWith(head: h, value: v);
    if (await trySave(context, () => repo.save(row))) await _load();
  }

  Future<void> _saveExcel(GameYear y) async {
    final bytes = Uint8List.fromList(gameRegisterXlsx(y, preparedOn: toDateStr(today)));
    final name = 'Game register ${DateTime.parse(y.yearStart).year + 1}.xlsx';
    final saved = widget.save != null ? await widget.save!(name, bytes) : await _saveFile(name, bytes);
    if (saved && mounted) showToast(context, 'Saved $name');
  }

  static Future<bool> _saveFile(String name, Uint8List bytes) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save $name',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      bytes: bytes,
    );
    if (path == null) return false;
    if (!Platform.isAndroid && !Platform.isIOS) await File(path).writeAsBytes(bytes);
    return true;
  }
}
