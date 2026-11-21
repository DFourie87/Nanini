import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/date_pick.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'card_models.dart';
import 'card_repository.dart';
import 'card_xlsx.dart';

/// Hub > Financials > Credit card / Fleet card: the card from its ABSA
/// statements (scripts/import_card_statements.py reads the PDFs). The
/// working paper per financial year, lines added by hand, the working paper
/// as Excel and the lines as a CSV for the card's bank account in Xero.
class CardScreen extends StatefulWidget {
  const CardScreen({super.key, required this.card, this.repo, this.save, this.today});

  final CardKind card;
  final CardRepository? repo;

  /// Tests: saves a file instead of the save dialog. True when saved.
  final Future<bool> Function(String name, Uint8List bytes)? save;
  final DateTime? today;

  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen> {
  late final CardRepository repo = widget.repo ?? CardRepository();
  List<CardStatement>? statements;
  List<CardLine> lines = const [];
  Map<String, double> openings = const {};
  String? problem;
  late String yearStart = cardYearStart(toDateStr(widget.today ?? DateTime.now()));

  CardKind get card => widget.card;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await repo.fetchStatements(card);
      final l = await repo.fetchLines([for (final x in s) x.id]);
      final o = await repo.fetchOpenings(card);
      if (!mounted) return;
      setState(() {
        statements = s;
        lines = l;
        openings = o;
        problem = null;
      });
    } catch (e) {
      if (mounted) setState(() => problem = friendlyDbError(e));
    }
  }

  CardYear get year => cardYear(card: card, yearStart: yearStart, opening: openings[yearStart], statements: statements ?? const [], lines: lines);

  List<String> get years {
    final out = {
      cardYearStart(toDateStr(widget.today ?? DateTime.now())),
      for (final s in statements ?? const <CardStatement>[]) cardYearStart(s.date),
    }.toList()..sort();
    return out.reversed.toList();
  }

  String _yearName(String start) {
    final y = DateTime.parse(start).year;
    return 'Year ${y + 1} (${fmtDateDisplay(start)} to ${fmtDateDisplay(toDateStr(DateTime(y + 1, 3, 0)))})';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      appBar: NaniniAppBar(title: card.label),
      body: problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$problem\n\n(Run nanini_app/docs/sql/card_statements.sql once?)', textAlign: TextAlign.center),
              ),
            )
          : statements == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(text)),
    );
  }

  Widget _body(TextTheme text) {
    final y = year;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text('ABSA ${card.label.toLowerCase()} -- in Xero: ${card.xeroAccount}', style: text.titleMedium),
        const SizedBox(height: 4),
        DropdownButton<String>(
          key: const Key('card_year'),
          value: yearStart,
          items: [for (final s in years) DropdownMenuItem(value: s, child: Text(_yearName(s)))],
          onChanged: (v) => setState(() => yearStart = v ?? yearStart),
        ),
        const SizedBox(height: 8),
        _lead(y, text),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('card_xero_csv'),
              onPressed: y.months.isEmpty ? null : () => runOnce('card_xero_${card.code}', () => _toXero(y)),
              icon: const Icon(Icons.upload_file),
              label: const Text('CSV for Xero'),
            ),
            OutlinedButton.icon(
              key: const Key('card_excel'),
              onPressed: y.months.isEmpty ? null : () => runOnce('card_excel_${card.code}', () => _saveExcel(y)),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Working paper (Excel)'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'New statements: save the PDF as downloaded from ABSA (not printed to PDF) in the client folder\'s <year>\\Bank\\${card.folder}; the import on the '
          'office PC (scripts\\run_import_task.bat, or py scripts\\import_card_statements.py "D:\\Kliente\\Nanini 121 BK") adds them here.',
          style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (y.months.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No statements in this year yet.', style: TextStyle(color: NaniniColors.muted)),
          ),
        for (final m in y.months.reversed) _month(m, text),
      ],
    );
  }

  Widget _row(String label, double? value, {bool bold = false, Key? key, VoidCallback? onTap, Color? color}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color);
    return InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: style)),
            if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.edit, size: 16, color: NaniniColors.muted),
              ),
            Text(value == null ? '--' : fmtRCents(value), style: style),
          ],
        ),
      ),
    );
  }

  Widget _lead(CardYear y, TextTheme text) {
    final last = y.months.isEmpty ? null : y.months.last.statement;
    final xo = y.xeroOpening;
    final from = y.openingFrom == 'entered' || y.opening == null ? '' : ' (${y.openingFrom})';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Working paper', style: text.titleSmall),
            const SizedBox(height: 6),
            _row('Opening balance ${fmtDateDisplay(y.yearStart)}$from', y.opening, key: const Key('card_opening'), onTap: () => _editOpening(y)),
            _row('Payments and credits', y.paidIn),
            _row('Spent and charged', y.spent),
            if (y.differences != 0) _row('Not explained by the lines', y.differences, color: NaniniColors.red),
            const Divider(),
            _row('Balance per statement${last == null ? '' : ' ${fmtDateDisplay(last.date)}'}', y.closing, bold: true),
            if (xo != null) ...[
              const SizedBox(height: 6),
              Text(
                'Xero\'s ${card.xeroAccount} account should open on ${fmtRCents(xo)} at 31 Aug 2026.',
                style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 6),
            const Text('Plus: in credit; minus: owed to ABSA.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _month(CardMonth m, TextTheme text) {
    final s = m.statement;
    return Card(
      key: Key('card_month_${s.date}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Statement ${fmtDateDisplay(s.date)}${s.number == null ? '' : ' (no. ${s.number})'}', style: text.titleSmall)),
                TextButton.icon(
                  key: Key('card_add_${s.date}'),
                  onPressed: () => _addLine(m),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add line'),
                ),
              ],
            ),
            if (s.from != null) Text('${fmtDateDisplay(s.from)} to ${fmtDateDisplay(s.to)}', style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 40),
              child: _row('Balance before', m.opening, color: NaniniColors.muted),
            ),
            for (final l in m.lines)
              Row(
                children: [
                  Expanded(
                    child: _row('${fmtDateDisplay(l.date)}  ${l.description}${l.manual ? ' -- added' : ''}${l.xeroSentAt != null ? '  ✓ Xero' : ''}', l.amount),
                  ),
                  if (l.manual)
                    IconButton(key: Key('card_delete_${l.id}'), icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _deleteLine(l))
                  else
                    const SizedBox(width: 40),
                ],
              ),
            if (m.difference != 0) ...[
              Padding(
                padding: const EdgeInsets.only(right: 40),
                child: _row('Not explained by the lines', m.difference, color: NaniniColors.red),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 40, bottom: 4),
                child: Text(
                  'A line left out (add it with "Add line"), or the balance brought forward isn\'t the last closing balance (a statement missing?).',
                  style: TextStyle(color: NaniniColors.red, fontSize: 12),
                ),
              ),
            ],
            Padding(padding: const EdgeInsets.only(right: 40), child: _row('Balance per statement', s.closing, bold: true)),
          ],
        ),
      ),
    );
  }

  Future<void> _editOpening(CardYear y) async {
    final c = TextEditingController(text: y.opening == null ? '' : y.opening!.toStringAsFixed(2));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Opening balance ${fmtDateDisplay(y.yearStart)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('As in the financial statements. Minus: owed to ABSA; plus: in credit.'),
            const SizedBox(height: 8),
            TextField(
              key: const Key('card_opening_amount'),
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: const InputDecoration(labelText: 'Balance (R)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.replaceAll(' ', '').replaceAll(',', ''))), child: const Text('Save')),
        ],
      ),
    );
    if (value == null || !mounted) return;
    if (await trySave(context, () => repo.saveOpening(card, y.yearStart, value))) await _load();
  }

  Future<void> _addLine(CardMonth m) async {
    final s = m.statement;
    var date = DateTime.parse(s.date);
    final what = TextEditingController();
    final amt = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Add a line to the statement of ${fmtDateDisplay(s.date)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('A line the statement left out.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('card_line_date'),
                onPressed: () async {
                  final first = s.from == null ? DateTime.parse(s.date).subtract(const Duration(days: 40)) : DateTime.parse(s.from!);
                  final picked = await pickDate(ctx, initialDate: date, firstDate: first, lastDate: DateTime.parse(s.date));
                  if (picked != null) setLocal(() => date = picked);
                },
                icon: const Icon(Icons.event),
                label: Text(fmtDateDisplay(toDateStr(date))),
              ),
              TextField(
                key: const Key('card_line_what'),
                controller: what,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextField(
                key: const Key('card_line_amount'),
                controller: amt,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: const InputDecoration(labelText: 'Amount (R): plus paid in, minus spent or charged'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final amount = double.tryParse(amt.text.replaceAll(' ', '').replaceAll(',', ''));
    if (amount == null || amount == 0 || what.text.trim().isEmpty) {
      await showProblem(context, 'Give a description and an amount (plus paid in, minus spent or charged).');
      return;
    }
    if (await trySave(context, () => repo.addLine(statementId: s.id, date: toDateStr(date), description: what.text.trim(), amount: amount))) await _load();
  }

  Future<void> _deleteLine(CardLine l) async {
    if (!await confirmDialog(context, message: 'Remove "${l.description}" (${fmtRCents(l.amount)}, ${fmtDateDisplay(l.date)})?')) return;
    if (!mounted) return;
    if (await trySave(context, () => repo.deleteLine(l.id))) await _load();
  }

  /// The lines not in Xero yet: saved as a CSV, or marked as already in Xero
  /// (put in by hand or by an earlier CSV) without saving.
  Future<void> _toXero(CardYear y) async {
    final todo = cardXeroLines(y);
    if (todo.isEmpty) {
      showToast(context, 'Nothing new for Xero: every line from ${fmtDateDisplay(kCardXeroFrom)} is there already.');
      return;
    }
    final total = todo.fold(0.0, (s, l) => s + l.amount);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${todo.length} line(s) for Xero, ${fmtRCents(total)}'),
        content: Text(
          '${fmtDateDisplay(todo.first.date)} to ${fmtDateDisplay(todo.last.date)}, for ${card.xeroAccount}.\n\n'
          'Already in Xero (imported before, or typed in)? "Already in Xero" marks them without saving a CSV.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          OutlinedButton(key: const Key('card_already_in_xero'), onPressed: () => Navigator.pop(ctx, 'mark'), child: const Text('Already in Xero')),
          FilledButton(key: const Key('card_save_csv'), onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save CSV')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'save') {
      final statementOf = {for (final s in statements ?? const <CardStatement>[]) s.id: s};
      final name = 'Xero ${card.label} ${fmtDateDisplay(todo.first.date)} to ${fmtDateDisplay(todo.last.date)}.csv';
      final bytes = Uint8List.fromList(utf8.encode(const ListToCsvConverter().convert(cardXeroRows(card, todo, statementOf))));
      if (!await _save(name, bytes, 'csv') || !mounted) return;
    }
    if (!await trySave(context, () => repo.markSent([for (final l in todo) l.id])) || !mounted) return;
    await _load();
    if (!mounted) return;
    showToast(
      context,
      choice == 'save'
          ? 'Saved ${todo.length} line(s): in Xero, Bank accounts > ${card.xeroAccount} > Import a statement'
          : '${todo.length} line(s) marked as in Xero',
    );
  }

  Future<void> _saveExcel(CardYear y) async {
    final bytes = Uint8List.fromList(cardWorkingPaperXlsx(y, preparedOn: toDateStr(widget.today ?? DateTime.now())));
    final name = '${card.label} working paper year ${DateTime.parse(y.yearStart).year + 1}.xlsx';
    if (await _save(name, bytes, 'xlsx') && mounted) showToast(context, 'Saved $name');
  }

  Future<bool> _save(String name, Uint8List bytes, String ext) async {
    if (widget.save != null) return widget.save!(name, bytes);
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Save $name', fileName: name, type: FileType.custom, allowedExtensions: [ext], bytes: bytes);
    if (path == null) return false;
    if (!Platform.isAndroid && !Platform.isIOS) await File(path).writeAsBytes(bytes);
    return true;
  }
}
