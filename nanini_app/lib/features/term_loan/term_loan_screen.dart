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
import '../xero/xero_export_screen.dart' show showChangedSinceSent;
import 'term_loan_models.dart';
import 'term_loan_repository.dart';
import 'term_loan_xlsx.dart';

/// Hub > Financials > Term loan: ABSA's term loan from its statements
/// (scripts/import_term_loan.py reads the PDFs). The working paper per
/// financial year, lines the statement left out added by hand, the working
/// paper as Excel and the lines as a CSV for Xero's TERMLOAN account.
class TermLoanScreen extends StatefulWidget {
  const TermLoanScreen({super.key, this.repo, this.save, this.today});

  final TermLoanRepository? repo;

  /// Tests: saves a file instead of the save dialog. True when saved.
  final Future<bool> Function(String name, Uint8List bytes)? save;
  final DateTime? today;

  @override
  State<TermLoanScreen> createState() => _TermLoanScreenState();
}

class _TermLoanScreenState extends State<TermLoanScreen> {
  late final TermLoanRepository repo = widget.repo ?? TermLoanRepository();
  List<TermLoanStatement>? statements;
  List<TermLoanLine> lines = const [];
  Map<String, double> openings = const {};
  String? problem;
  late String yearStart = termLoanYearStart(toDateStr(widget.today ?? DateTime.now()));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await repo.fetchStatements();
      final l = await repo.fetchLines();
      final o = await repo.fetchOpenings();
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

  TermLoanYear get year => termLoanYear(yearStart: yearStart, opening: openings[yearStart], statements: statements ?? const [], lines: lines);

  List<String> get years {
    final out = {
      termLoanYearStart(toDateStr(widget.today ?? DateTime.now())),
      for (final s in statements ?? const <TermLoanStatement>[]) termLoanYearStart(s.date),
    }.toList()..sort();
    return out.reversed.toList();
  }

  String _yearName(String start) =>
      'Year ${DateTime.parse(start).year + 1} (${fmtDateDisplay(start)} to ${fmtDateDisplay(toDateStr(DateTime(DateTime.parse(start).year + 1, 3, 0)))})';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      appBar: const NaniniAppBar(title: 'Term loan'),
      body: problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$problem\n\n(Run nanini_app/docs/sql/term_loan.sql once?)', textAlign: TextAlign.center),
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
        Text('ABSA term loan $kTermLoanAccount', style: text.titleMedium),
        const SizedBox(height: 4),
        DropdownButton<String>(
          key: const Key('term_loan_year'),
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
              key: const Key('term_loan_xero_csv'),
              onPressed: y.months.isEmpty ? null : () => runOnce('term_loan_xero', () => _saveXero(y)),
              icon: const Icon(Icons.upload_file),
              label: const Text('CSV for Xero'),
            ),
            OutlinedButton.icon(
              key: const Key('term_loan_excel'),
              onPressed: y.months.isEmpty ? null : () => runOnce('term_loan_excel', () => _saveExcel(y)),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Working paper (Excel)'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'New statements: save the PDF in the client folder\'s <year>\\Bank\\Term Loan; the import on the office PC '
          '(scripts\\run_import_task.bat, or py scripts\\import_term_loan.py "D:\\Kliente\\Nanini 121 BK") adds them here.',
          style: TextStyle(color: NaniniColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (y.opening == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Enter the opening balance above to see the year.', style: TextStyle(color: NaniniColors.muted)),
          )
        else if (y.months.isEmpty)
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

  Widget _lead(TermLoanYear y, TextTheme text) {
    final last = y.months.isEmpty ? null : y.months.last.statement;
    final xo = y.xeroOpening;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Working paper', style: text.titleSmall),
            const SizedBox(height: 6),
            _row(
              'Opening balance ${fmtDateDisplay(y.yearStart)}${y.openingEntered || y.opening == null ? '' : ' (last statement)'}',
              y.opening,
              key: const Key('term_loan_opening'),
              onTap: () => _editOpening(y),
            ),
            _row('Paid into the loan', y.paidIn),
            _row('Drawn from the loan', y.drawn),
            _row('Interest and charges (net)', y.interest),
            const Divider(),
            _row('Balance per statement${last == null ? '' : ' ${fmtDateDisplay(last.date)}'}', y.closing, bold: true),
            if (last != null) ...[
              _row('Capital outstanding', -last.capital, color: NaniniColors.muted),
              _row('Prepaid (Arrear/Advance)', last.advance, color: NaniniColors.muted),
              if (last.amountPayable != null) _row('Next instalment ${fmtDateDisplay(last.payableDate)}', last.amountPayable, color: NaniniColors.muted),
            ],
            if (xo != null) ...[
              const SizedBox(height: 6),
              Text(
                'Xero\'s $kTermLoanXeroAccount account should open on ${fmtRCents(xo)} at 31 Aug 2026.',
                style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 6),
            const Text(
              'Balance: the prepaid amount less the capital still owed, as on the statement. Plus: more paid in than owed.',
              style: TextStyle(color: NaniniColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _month(TermLoanMonth m, TextTheme text) {
    final s = m.statement;
    final all = [...m.money, ...m.info]..sort((a, b) => a.date.compareTo(b.date));
    return Card(
      key: Key('term_loan_month_${s.date}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Statement ${fmtDateDisplay(s.date)}', style: text.titleSmall)),
                TextButton.icon(
                  key: Key('term_loan_add_${s.date}'),
                  onPressed: () => _addLine(m),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add line'),
                ),
              ],
            ),
            if (s.from != null) Text('${fmtDateDisplay(s.from)} to ${fmtDateDisplay(s.to)}', style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
            const SizedBox(height: 4),
            _row('Balance before', m.opening, color: NaniniColors.muted),
            for (final l in all)
              Row(
                children: [
                  Expanded(
                    child: _row(
                      '${fmtDateDisplay(l.date)}  ${l.description}${m.money.contains(l) ? '' : ' (in the interest)'}${l.manual ? ' -- added' : ''}',
                      l.amount,
                      color: m.money.contains(l) ? null : NaniniColors.muted,
                    ),
                  ),
                  if (l.manual)
                    IconButton(key: Key('term_loan_delete_${l.id}'), icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _deleteLine(l))
                  else
                    const SizedBox(width: 40),
                ],
              ),
            Padding(
              padding: const EdgeInsets.only(right: 40),
              child: _row('Interest and charges (net)', m.interest, color: m.looksShort ? NaniniColors.red : null),
            ),
            if (m.looksShort)
              const Padding(
                padding: EdgeInsets.only(right: 40, bottom: 4),
                child: Text(
                  'More than a month\'s interest: the statement left a payment or drawing out? Add it with "Add line".',
                  style: TextStyle(color: NaniniColors.red, fontSize: 12),
                ),
              ),
            Padding(padding: const EdgeInsets.only(right: 40), child: _row('Balance per statement', s.balance, bold: true)),
          ],
        ),
      ),
    );
  }

  Future<void> _editOpening(TermLoanYear y) async {
    final c = TextEditingController(text: y.opening == null ? '' : y.opening!.toStringAsFixed(2));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Opening balance ${fmtDateDisplay(y.yearStart)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('As in the financial statements. Minus: owed to ABSA; plus: more paid in than owed.'),
            const SizedBox(height: 8),
            TextField(
              key: const Key('term_loan_opening_amount'),
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
    if (await trySave(context, () => repo.saveOpening(y.yearStart, value))) await _load();
  }

  Future<void> _addLine(TermLoanMonth m) async {
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
              const Text('A payment into the loan or a drawing from it that the statement left out (see the ABSA bank statement).'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('term_loan_line_date'),
                onPressed: () async {
                  final first = s.from == null ? DateTime.parse(s.date).subtract(const Duration(days: 40)) : DateTime.parse(s.from!);
                  final picked = await pickDate(ctx, initialDate: date, firstDate: first, lastDate: DateTime.parse(s.date));
                  if (picked != null) setLocal(() => date = picked);
                },
                icon: const Icon(Icons.event),
                label: Text(fmtDateDisplay(toDateStr(date))),
              ),
              TextField(
                key: const Key('term_loan_line_what'),
                controller: what,
                decoration: const InputDecoration(labelText: 'Description (e.g. Payment from ABSA current account)'),
              ),
              TextField(
                key: const Key('term_loan_line_amount'),
                controller: amt,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: const InputDecoration(labelText: 'Amount (R): plus paid in, minus drawn'),
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
      await showProblem(context, 'Give a description and an amount (plus paid in, minus drawn).');
      return;
    }
    if (await trySave(context, () => repo.addLine(statementId: s.id, date: toDateStr(date), description: what.text.trim(), amount: amount))) await _load();
  }

  Future<void> _deleteLine(TermLoanLine l) async {
    if (!await confirmDialog(context, message: 'Remove "${l.description}" (${fmtRCents(l.amount)}, ${fmtDateDisplay(l.date)})?')) return;
    if (!mounted) return;
    if (await trySave(context, () => repo.deleteLine(l.id))) await _load();
  }

  Future<void> _saveXero(TermLoanYear y) async {
    final r = termLoanXeroItems(y);
    if (r.items.isEmpty) {
      if (r.changed.isEmpty) {
        showToast(context, 'Nothing new for Xero: everything from ${fmtDateDisplay(kTermLoanXeroFrom)} is there already.');
      } else {
        await _changed(r.changed, nothingNew: true);
      }
      return;
    }
    final name =
        'Xero $kTermLoanXeroAccount ${fmtDateDisplay(r.items.first.date).replaceAll('/', '-')} to ${fmtDateDisplay(r.items.last.date).replaceAll('/', '-')}.csv';
    final bytes = Uint8List.fromList(utf8.encode(const ListToCsvConverter().convert(termLoanXeroRows(r.items))));
    if (!await _save(name, bytes, 'csv') || !mounted) return;
    try {
      await repo.markSent(r.items);
    } catch (e) {
      if (mounted) await showProblem(context, 'Saved, but not marked as sent: ${friendlyDbError(e)}', title: 'Not marked');
    }
    await _load();
    if (!mounted) return;
    final total = r.items.fold(0.0, (s, i) => s + i.amount);
    showToast(context, 'Saved ${r.items.length} line(s), ${fmtRCents(total)}: in Xero, Bank accounts > $kTermLoanXeroAccount > Import a statement');
    await _changed(r.changed);
  }

  Future<void> _changed(List<TermLoanMonth> months, {bool nothingNew = false}) async {
    if (months.isEmpty || !mounted) return;
    final labels = {
      for (final m in months)
        'Interest and charges to ${fmtDateDisplay(m.statement.date)}: now ${fmtRCents(m.interest)}, sent ${fmtRCents(m.statement.xeroInterestSent)}',
    };
    if (!await showChangedSinceSent(context, labels, nothingNew: nothingNew) || !mounted) return;
    if (await trySave(
      context,
      () => repo.markSent([for (final m in months) TermLoanXeroItem(date: m.statement.date, amount: m.interest, description: '', reference: '', month: m)]),
    )) {
      await _load();
    }
  }

  Future<void> _saveExcel(TermLoanYear y) async {
    final bytes = Uint8List.fromList(termLoanWorkingPaperXlsx(y, preparedOn: toDateStr(widget.today ?? DateTime.now())));
    final name = 'Term loan working paper year ${DateTime.parse(y.yearStart).year + 1}.xlsx';
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
