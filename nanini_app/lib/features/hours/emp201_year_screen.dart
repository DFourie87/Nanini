import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import 'emp201_year.dart';
import 'hours_models.dart';
import 'payroll_month.dart';
import 'pay_widgets.dart';

final _monthFmt = DateFormat('MMM yyyy');

/// Employees > Reports > EMP201 tax year (admins): every month's EMP201 --
/// UIF, SDL and PAYE worked out -- against what was submitted to SARS on
/// eFiling ("Ingedien"), and the difference. Months before the app's
/// payroll come from the old salary summary workbook. Download as Excel.
class Emp201YearScreen extends StatefulWidget {
  const Emp201YearScreen({super.key, required this.payslips, required this.employees, required this.includeSdl, this.farms = const []});
  final List<Payslip> payslips;
  final List<Employee> employees;
  final List<Farm> farms;
  final bool includeSdl;
  @override
  State<Emp201YearScreen> createState() => _Emp201YearScreenState();
}

class _Emp201YearScreenState extends State<Emp201YearScreen> {
  int taxYear = taxYearOf(DateTime.now().subtract(const Duration(days: 7)));
  List<Emp201HistoryLine> history = [];
  List<Emp201Submitted> submitted = [];
  bool loaded = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      List<Map<String, dynamic>> rows(Object r) => (r as List).cast<Map<String, dynamic>>();
      final h = rows(await sb.from('emp201_history').select().order('month')).map(Emp201HistoryLine.fromJson).toList();
      final s = rows(await sb.from('emp201_submissions').select().order('month')).map(Emp201Submitted.fromJson).toList();
      if (!mounted) return;
      setState(() {
        history = h;
        submitted = s;
        loaded = true;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loaded = true;
        error = friendlyDbError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final months = emp201Year(
      taxYear: taxYear,
      payslips: widget.payslips,
      history: history,
      employees: widget.employees,
      submitted: submitted,
      includeSdl: widget.includeSdl,
    );
    double sum(double Function(Emp201YearMonth) f) => months.fold(0.0, (s, m) => s + f(m));
    const head = TextStyle(fontWeight: FontWeight.w700);
    DataCell money(double? v, {bool bold = false}) => DataCell(Text(v == null ? '' : fmtRCents(v), style: TextStyle(fontWeight: bold ? FontWeight.w700 : null)));

    return Scaffold(
      appBar: NaniniAppBar(
        title: 'EMP201 tax year',
        actions: [
          IconButton(
            tooltip: 'Download Excel',
            onPressed: loaded ? () => runOnce('emp201_year.xlsx', () => _download(months)) : null,
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  IconButton(onPressed: () => setState(() => taxYear--), icon: const Icon(Icons.chevron_left)),
                  Expanded(
                    child: Column(children: [
                      Text('Tax year $taxYear', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                      Text('March ${taxYear - 1} to February $taxYear', style: const TextStyle(color: NaniniColors.muted)),
                    ]),
                  ),
                  IconButton(onPressed: () => setState(() => taxYear++), icon: const Icon(Icons.chevron_right)),
                ]),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Earlier months and submissions: $error', style: const TextStyle(color: NaniniColors.red)),
                  ),
                const SizedBox(height: 8),
                FarmSection(
                  title: 'EMP201 per month',
                  totals: fmtRCents(sum((m) => m.total)),
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 18,
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('Month', style: head)),
                          DataColumn(label: Text('UIF', style: head), numeric: true),
                          DataColumn(label: Text('SDL', style: head), numeric: true),
                          DataColumn(label: Text('PAYE', style: head), numeric: true),
                          DataColumn(label: Text('Total', style: head), numeric: true),
                        ],
                        rows: [
                          for (final m in months)
                            DataRow(
                              onSelectChanged: (_) => runOnce('emp201_year.submit', () => _editSubmitted(m)),
                              cells: [
                                DataCell(Text('${_monthFmt.format(DateTime.parse(m.month))}${m.fromHistory ? ' *' : ''}')),
                                money(m.uif),
                                money(m.sdl),
                                money(m.paye),
                                money(m.total, bold: true),
                              ],
                            ),
                          DataRow(cells: [
                            const DataCell(Text('Total', style: head)),
                            money(sum((m) => m.uif), bold: true),
                            money(sum((m) => m.sdl), bold: true),
                            money(sum((m) => m.paye), bold: true),
                            money(sum((m) => m.total), bold: true),
                          ]),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Text(
                        'UIF is the employees\' and the employer\'s together. * From the old salary summary. Tap a month to enter what '
                        'was submitted on eFiling -- it\'s in the Excel, with the difference.',
                        style: TextStyle(color: NaniniColors.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                FilledButton.icon(
                  onPressed: () => runOnce('emp201_year.xlsx', () => _download(months)),
                  icon: const Icon(Icons.download),
                  label: const Text('Download Excel -- everything on one sheet'),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'The months with what was submitted and the difference, then every employee paid in the tax year with each month\'s salary, UIF, SDL and PAYE, '
                    'in three groups: on EMP201, not on it with an ID/passport, not on it without.',
                    style: TextStyle(color: NaniniColors.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
    );
  }

  /// "Ingedien": what was submitted to SARS on eFiling for [m] -- starts at
  /// the amounts worked out.
  Future<void> _editSubmitted(Emp201YearMonth m) async {
    final s = m.submitted;
    String two(double v) => v.toStringAsFixed(2);
    final uif = TextEditingController(text: two(s?.uif ?? m.uif));
    final sdl = TextEditingController(text: two(s?.sdl ?? m.sdl));
    final paye = TextEditingController(text: two(s?.paye ?? m.paye));
    final ref = TextEditingController(text: s?.reference);
    var on = s?.submittedOn != null ? DateTime.parse(s!.submittedOn!) : DateTime.now();
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Submitted on eFiling -- ${_monthFmt.format(DateTime.parse(m.month))}'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Worked out: UIF ${fmtRCents(m.uif)} · SDL ${fmtRCents(m.sdl)} · PAYE ${fmtRCents(m.paye)}',
                    style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                const SizedBox(height: 8),
                for (final (label, c) in [('UIF', uif), ('SDL', sdl), ('PAYE', paye)]) ...[
                  TextField(
                    controller: c,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: label, prefixText: 'R'),
                  ),
                  const SizedBox(height: 8),
                ],
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text('Submitted on ${fmtDateDisplay(toDateStr(on))}'),
                  onTap: () async {
                    final d = await showDatePicker(context: ctx, initialDate: on, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setLocal(() => on = d);
                  },
                ),
                TextField(controller: ref, decoration: const InputDecoration(labelText: 'Reference (optional)', hintText: 'e.g. the eFiling payment reference')),
              ]),
            ),
          ),
          actions: [
            if (s != null)
              TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Delete', style: TextStyle(color: NaniniColors.red))),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'delete') {
        if (!await confirmDialog(context, message: 'Delete what was entered as submitted for this month?', confirmLabel: 'Delete', danger: true)) return;
        await sb.from('emp201_submissions').delete().eq('month', m.month);
      } else {
        await sb.from('emp201_submissions').upsert({
          'month': m.month,
          'uif': parseNum(uif.text) ?? 0,
          'sdl': parseNum(sdl.text) ?? 0,
          'paye': parseNum(paye.text) ?? 0,
          'submitted_on': toDateStr(on),
          'reference': ref.text.trim().isEmpty ? null : ref.text.trim(),
        });
      }
    } catch (e) {
      if (mounted) await showProblem(context, friendlyDbError(e));
      return;
    }
    await _load();
  }

  /// The tax year as an Excel workbook: the months (worked out, submitted,
  /// difference), every employee per month, and each employee's year.
  Future<void> _download(List<Emp201YearMonth> months) async {
    final bytes = emp201YearXlsx(taxYear, months, farms: widget.farms);
    final name = 'EMP201 $taxYear.xlsx';
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save $name',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: Uint8List.fromList(bytes),
      );
      if (path == null) return;
      // Windows and the desktop only give the path: write it here.
      if (!Platform.isAndroid && !Platform.isIOS) await File(path).writeAsBytes(bytes);
      if (mounted) showToast(context, 'Saved $name');
    } catch (e) {
      if (mounted) await showProblem(context, friendlyDbError(e), title: 'Could not save');
    }
  }
}

/// [months] of [taxYear] as an .xlsx file -- everything on one sheet, like
/// the salary summary: the months (worked out, submitted, difference), then
/// every employee paid in the tax year with each month's salary, UIF, SDL
/// and PAYE and the year, in three groups (on EMP201, not on it with an
/// ID/passport, not on it without), each with its totals.
List<int> emp201YearXlsx(int taxYear, List<Emp201YearMonth> months, {List<Farm> farms = const []}) {
  final x = Excel.createExcel();
  final name = 'EMP201 $taxYear';
  x.rename(x.getDefaultSheet() ?? 'Sheet1', name);
  final sh = x[name];
  final bold = CellStyle(bold: true);
  var row = 0;
  void put(int col, CellValue? v, {bool b = false}) {
    if (v == null) return;
    sh.updateCell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row), v, cellStyle: b ? bold : null);
  }

  void line(List<CellValue?> vs, {bool b = false}) {
    for (var c = 0; c < vs.length; c++) {
      put(c, vs[c], b: b);
    }
    row++;
  }

  CellValue t(String s) => TextCellValue(s);
  CellValue? n(double? v) => v == null ? null : DoubleCellValue((v * 100).roundToDouble() / 100);
  String month(String m) => DateFormat('MMMM yyyy').format(DateTime.parse(m));
  String farm(Employee? e) => farmShort(farms.where((f) => f.id == e?.farmId).firstOrNull);

  line([t('Nanini 121 CC -- EMP201 summary, tax year $taxYear (March ${taxYear - 1} to February $taxYear)')], b: true);
  row++;

  // 1. The months: worked out, submitted on eFiling, difference.
  line([t('EMP201 per month')], b: true);
  line([
    t('Month'), t('Employees'), t('Remuneration'), t('UIF'), t('SDL'), t('PAYE'), t('Total'), //
    t('Submitted UIF'), t('Submitted SDL'), t('Submitted PAYE'), t('Submitted total'), t('Difference'), t('Submitted on'), t('Reference'),
  ], b: true);
  for (final m in months) {
    final s = m.submitted;
    line([
      t(month(m.month)), IntCellValue(m.employees), n(m.salary), n(m.uif), n(m.sdl), n(m.paye), n(m.total), //
      n(s?.uif), n(s?.sdl), n(s?.paye), n(s?.total), n(m.difference), s?.submittedOn == null ? null : t(s!.submittedOn!), s?.reference == null ? null : t(s!.reference!),
    ]);
  }
  double tot(double Function(Emp201YearMonth) f) => months.fold(0.0, (s, m) => s + f(m));
  final subs = months.where((m) => m.submitted != null).toList();
  double sub(double Function(Emp201YearMonth) f) => subs.fold(0.0, (s, m) => s + f(m));
  line([
    t('Total'), null, n(tot((m) => m.salary)), n(tot((m) => m.uif)), n(tot((m) => m.sdl)), n(tot((m) => m.paye)), n(tot((m) => m.total)), //
    subs.isEmpty ? null : n(sub((m) => m.submitted!.uif)), subs.isEmpty ? null : n(sub((m) => m.submitted!.sdl)),
    subs.isEmpty ? null : n(sub((m) => m.submitted!.paye)), subs.isEmpty ? null : n(sub((m) => m.submitted!.total)),
    subs.isEmpty ? null : n(sub((m) => m.difference!)),
  ], b: true);
  line([t('Only employees on the EMP201 count. UIF is the employees\' and the employer\'s together. Difference: submitted less worked out. '
      'March to August ${taxYear - 1} as in the old salary summary.')]);
  row++;

  // 2. Every employee: per month salary, UIF, SDL, PAYE, then the year.
  const figures = ['Salary', 'UIF', 'SDL', 'PAYE'];
  double fig(Emp201EmployeeMonth l, int i) => switch (i) { 0 => l.salary, 1 => l.uif, 2 => l.sdl, _ => l.paye };
  // Not declared that month: no UIF, SDL or PAYE unless some was taken off.
  double? cell(Emp201EmployeeMonth? l, int i) => l == null || (i > 0 && fig(l, i).abs() < 0.005) ? null : fig(l, i);
  const first = 3; // Employee, Farm, ID/passport
  void heading() {
    for (var k = 0; k < months.length; k++) {
      put(first + k * 4, t(DateFormat('MMM yyyy').format(DateTime.parse(months[k].month))), b: true);
    }
    put(first + months.length * 4, t('Year $taxYear'), b: true);
    row++;
    line([t('Employee'), t('Farm'), t('ID/passport'), for (var k = 0; k <= months.length; k++) ...[for (final f in figures) t(f)]], b: true);
  }

  final people = emp201YearByEmployee(months);
  for (final g in Emp201Group.values) {
    final ls = people[g]!;
    line([t('${g.label} (${ls.length})')], b: true);
    if (g != Emp201Group.declared) {
      line([t('UIF here is what was taken off their pay (not declared).')]);
    }
    heading();
    for (final y in ls) {
      final year = [for (var i = 0; i < 4; i++) y.months.values.fold<double>(0, (s, l) => s + (cell(l, i) ?? 0))];
      line([
        t(y.name), t(farm(y.employee)), t(y.employee?.idOrPassport ?? ''), //
        for (final m in months) ...[for (var i = 0; i < 4; i++) n(cell(y.months[m.month], i))],
        for (final v in year) n(v),
      ]);
    }
    final totals = [
      for (final m in months)
        for (var i = 0; i < 4; i++) ls.fold<double>(0, (s, y) => s + (cell(y.months[m.month], i) ?? 0)),
    ];
    final year = [for (var i = 0; i < 4; i++) ls.fold<double>(0, (s, y) => s + y.months.values.fold<double>(0, (a, l) => a + (cell(l, i) ?? 0)))];
    line([t('Total'), null, null, for (final v in totals) n(v), for (final v in year) n(v)], b: true);
    row++;
  }
  sh.setColumnWidth(0, 28);
  sh.setColumnWidth(1, 14);
  sh.setColumnWidth(2, 16);
  return x.encode()!;
}
