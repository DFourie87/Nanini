import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'vat_models.dart';
import 'vat_repository.dart';
import 'vat_xlsx.dart';

/// Hub > Financials > VAT control: per two-month period the supplies and
/// input VAT from the hub (account sales, supplier invoices), what is kept
/// by hand (other supplies, the diesel refund, the VAT201 as submitted), the
/// net VAT and the difference with the VAT201; the declared sales agreed to
/// the financial statements; as Excel.
class VatScreen extends StatefulWidget {
  const VatScreen({super.key, this.repo, this.save, this.today});

  final VatRepository? repo;

  /// Tests: saves a file instead of the save dialog. True when saved.
  final Future<bool> Function(String name, Uint8List bytes)? save;
  final DateTime? today;

  @override
  State<VatScreen> createState() => _VatScreenState();
}

class _VatScreenState extends State<VatScreen> {
  late final VatRepository repo = widget.repo ?? VatRepository();
  late final DateTime today = widget.today ?? DateTime.now();
  late String yearStart = vatYearStart(toDateStr(today));
  VatYear? year;
  String? problem;
  String? hubProblem;

  String get yearEnd => toDateStr(DateTime(DateTime.parse(yearStart).year + 1, 3, 0));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final manual = await repo.fetchManual();
      final fs = await repo.fetchFsSales();
      var sales = const <VatSale>[];
      var purchases = const <VatPurchase>[];
      String? hp;
      try {
        sales = await repo.fetchSales(yearStart, yearEnd);
        purchases = await repo.fetchPurchases(yearStart, yearEnd);
      } catch (e) {
        hp = friendlyDbError(e);
      }
      if (!mounted) return;
      setState(() {
        year = vatYear(yearStart, vatHubFigures(yearStart, sales, purchases), manual, fsSales: fs[yearStart]);
        problem = null;
        hubProblem = hp;
      });
    } catch (e) {
      if (mounted) setState(() => problem = friendlyDbError(e));
    }
  }

  List<String> get years {
    final now = DateTime.parse(vatYearStart(toDateStr(today)));
    return [for (var i = 0; i < 4; i++) toDateStr(DateTime(now.year - i, 3, 1))];
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      appBar: const NaniniAppBar(title: 'VAT control'),
      body: problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$problem\n\n(Run nanini_app/docs/sql/vat_control.sql once?)', textAlign: TextAlign.center),
              ),
            )
          : year == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(year!, text)),
    );
  }

  Widget _row(String label, double? value, {bool bold = false, Color? color, Key? key, VoidCallback? onTap}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color);
    return InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
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

  Widget _body(VatYear y, TextTheme text) {
    final diff = y.salesDifference;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        DropdownButton<String>(
          key: const Key('vat_year'),
          value: yearStart,
          items: [
            for (final s in years)
              DropdownMenuItem(
                value: s,
                child: Text(
                  'Year ${DateTime.parse(s).year + 1} (${fmtDateDisplay(s)} to ${fmtDateDisplay(toDateStr(DateTime(DateTime.parse(s).year + 1, 3, 0)))})',
                ),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              yearStart = v;
              year = null;
            });
            _load();
          },
        ),
        if (hubProblem != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('The hub\'s sales or supplier invoices could not be read: $hubProblem', style: const TextStyle(color: NaniniColors.red)),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The year', style: text.titleSmall),
                const SizedBox(height: 6),
                _row('Output VAT', y.outputVat),
                _row('Input VAT', -y.inputVat),
                _row('Diesel refund', -y.dieselRefund),
                const Divider(),
                _row('Net VAT payable (refundable: minus)', y.net, bold: true),
                const SizedBox(height: 8),
                _row('Sales excluding VAT, as declared', y.salesExcl),
                _row('Sales per the financial statements', y.fsSales, key: const Key('vat_fs_sales'), onTap: _editFsSales),
                if (diff != null) _row('Difference', diff, color: diff.abs() > 0.5 ? NaniniColors.red : null, bold: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('vat_excel'),
          onPressed: () => runOnce('vat_excel', () => _saveExcel(y)),
          icon: const Icon(Icons.table_chart_outlined),
          label: const Text('VAT control (Excel)'),
        ),
        const SizedBox(height: 8),
        for (final p in y.periods) _period(p, text),
      ],
    );
  }

  Widget _period(VatPeriod p, TextTheme text) {
    final d = p.difference;
    return Card(
      key: Key('vat_period_${p.start}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(p.label, style: text.titleSmall)),
                TextButton.icon(
                  key: Key('vat_edit_${p.start}'),
                  onPressed: () => _edit(p),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Entered / VAT201'),
                ),
              ],
            ),
            _row('Standard rate supplies (incl. VAT)', p.standard),
            if (p.capitalSupplies != 0) _row('Capital supplies', p.capitalSupplies),
            _row('Zero rated supplies', p.zeroRated),
            _row('Output VAT', p.outputVat),
            _row('Input VAT: standard', p.inputStandard),
            _row('Input VAT: capital', p.inputCapital),
            if (p.dieselRefund != 0) _row('Diesel refund', p.dieselRefund),
            const Divider(),
            _row('Net VAT payable (refundable: minus)', p.net, bold: true),
            if (p.vat201Net != null) ...[
              _row('Per VAT201', p.vat201Net, color: NaniniColors.muted),
              _row('Difference', d, color: (d ?? 0).abs() > 0.5 ? NaniniColors.red : null, bold: true),
            ],
            if ((p.manual.notes ?? '').isNotEmpty) Text(p.manual.notes!, style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Future<void> _editFsSales() async {
    final c = TextEditingController(text: year?.fsSales?.toStringAsFixed(2) ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sales per the financial statements'),
        content: TextField(
          key: const Key('vat_fs_amount'),
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Total sales (R, excluding VAT); empty: none'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (value == null || !mounted) return;
    final v = double.tryParse(value.replaceAll(' ', '').replaceAll(',', ''));
    if (await trySave(context, () => repo.saveFsSales(yearStart, v))) await _load();
  }

  Future<void> _edit(VatPeriod p) async {
    final m = p.manual;
    String show(double? v) => v == null || v == 0 ? '' : v.toStringAsFixed(2);
    final fields = <String, TextEditingController>{
      'Other standard rate supplies, incl. VAT (hunting, game sales, rent)': TextEditingController(text: show(m.otherStandard)),
      'Other zero rated / exempt supplies': TextEditingController(text: show(m.otherZero)),
      'Capital supplies, incl. VAT (assets sold)': TextEditingController(text: show(m.capitalSupplies)),
      'Diesel refund': TextEditingController(text: show(m.dieselRefund)),
      'VAT201: output VAT': TextEditingController(text: show(m.vat201Output)),
      'VAT201: input VAT': TextEditingController(text: show(m.vat201Input)),
      'VAT201: diesel refund': TextEditingController(text: show(m.vat201Diesel)),
    };
    final notes = TextEditingController(text: m.notes ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.label),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in fields.entries)
                  TextField(
                    key: Key('vat_field_${e.key}'),
                    controller: e.value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: InputDecoration(labelText: e.key),
                  ),
                TextField(
                  key: const Key('vat_field_notes'),
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const Key('vat_save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    double? num(String k) => double.tryParse(fields[k]!.text.replaceAll(' ', '').replaceAll(',', ''));
    final keys = fields.keys.toList();
    final saved = VatManual(
      periodStart: p.start,
      otherStandard: num(keys[0]) ?? 0,
      otherZero: num(keys[1]) ?? 0,
      capitalSupplies: num(keys[2]) ?? 0,
      dieselRefund: num(keys[3]) ?? 0,
      vat201Output: num(keys[4]),
      vat201Input: num(keys[5]),
      vat201Diesel: num(keys[6]),
      notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
    );
    if (await trySave(context, () => repo.saveManual(saved))) await _load();
  }

  Future<void> _saveExcel(VatYear y) async {
    final bytes = Uint8List.fromList(vatControlXlsx(y, preparedOn: toDateStr(today)));
    final name = 'VAT control year ${DateTime.parse(y.yearStart).year + 1}.xlsx';
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
