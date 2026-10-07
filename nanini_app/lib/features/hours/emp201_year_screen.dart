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
  _Figure figure = _Figure.salary;

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
    final people = emp201YearByEmployee(months);
    double sum(double Function(Emp201YearMonth) f) => months.fold(0.0, (s, m) => s + f(m));
    final subs = months.where((m) => m.submitted != null);
    const head = TextStyle(fontWeight: FontWeight.w700);
    DataCell money(double? v, {bool bold = false, Color? color}) =>
        DataCell(Text(v == null ? '' : fmtRCents(v), style: TextStyle(fontWeight: bold ? FontWeight.w700 : null, color: color)));
    Color? diffColor(double? d) => d == null ? null : d.abs() < 0.01 ? NaniniColors.green : NaniniColors.red;

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
                          DataColumn(label: Text('Submitted', style: head), numeric: true),
                          DataColumn(label: Text('Difference', style: head), numeric: true),
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
                                m.submitted == null
                                    ? const DataCell(Text('enter', style: TextStyle(color: NaniniColors.rust)))
                                    : money(m.submitted!.total),
                                money(m.difference, color: diffColor(m.difference)),
                              ],
                            ),
                          DataRow(cells: [
                            const DataCell(Text('Total', style: head)),
                            money(sum((m) => m.uif), bold: true),
                            money(sum((m) => m.sdl), bold: true),
                            money(sum((m) => m.paye), bold: true),
                            money(sum((m) => m.total), bold: true),
                            money(subs.isEmpty ? null : subs.fold<double>(0, (s, m) => s + m.submitted!.total), bold: true),
                            money(subs.isEmpty ? null : subs.fold<double>(0, (s, m) => s + m.difference!), bold: true),
                          ]),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Text(
                        'UIF is the employees\' and the employer\'s together. Tap a month to enter what was submitted on eFiling; '
                        'the difference is submitted less worked out. * From the old salary summary.',
                        style: TextStyle(color: NaniniColors.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                // Like the salary summary: everyone, a column per month, in
                // the three groups -- filled in as each month's payroll runs.
                Text('Per employee', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<_Figure>(
                  segments: [for (final f in _Figure.values) ButtonSegment(value: f, label: Text(f.label))],
                  selected: {figure},
                  onSelectionChanged: (v) => setState(() => figure = v.first),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
                ),
                const SizedBox(height: 8),
                for (final g in Emp201Group.values) _groupTable(g, people[g]!, months),
              ],
            ),
    );
  }

  /// One group's employees: [figure] per month, and the year.
  Widget _groupTable(Emp201Group g, List<Emp201EmployeeYear> ls, List<Emp201YearMonth> months) {
    const head = TextStyle(fontWeight: FontWeight.w700);
    // Not declared that month (e.g. before they were registered for UIF): no
    // UIF, SDL or PAYE shown unless some was taken off their pay.
    double? of(Emp201EmployeeMonth? l) => l == null || (figure != _Figure.salary && figure.of(l).abs() < 0.005) ? null : figure.of(l);
    double total(Iterable<double?> vs) => vs.fold(0.0, (s, v) => s + (v ?? 0));
    // Not declared, yet UIF or PAYE taken off: shown in red.
    bool flag(Emp201EmployeeMonth? l) => l != null && l.withheldNotDeclared;
    final yearTotal = total(ls.map((y) => total(y.months.values.map(figure.of))));
    return FarmSection(
      title: g.label,
      totals: '${ls.length} · ${fmtR(yearTotal)}',
      children: [
        if (ls.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Nobody this tax year.', style: TextStyle(color: NaniniColors.muted)))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 14,
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columns: [
                const DataColumn(label: Text('Employee', style: head)),
                const DataColumn(label: Text('Farm', style: head)),
                for (final m in months) DataColumn(label: Text(DateFormat('MMM').format(DateTime.parse(m.month)), style: head), numeric: true),
                const DataColumn(label: Text('Year', style: head), numeric: true),
              ],
              rows: [
                for (final y in ls)
                  DataRow(cells: [
                    DataCell(Text(y.name)),
                    DataCell(Text(farmShort(widget.farms.where((f) => f.id == y.employee?.farmId).firstOrNull), style: const TextStyle(color: NaniniColors.muted))),
                    for (final m in months)
                      DataCell(Text(
                        of(y.months[m.month]) == null ? '' : fmtRCents(of(y.months[m.month])),
                        style: TextStyle(color: flag(y.months[m.month]) ? NaniniColors.red : null),
                      )),
                    DataCell(Text(fmtRCents(total(y.months.values.map(figure.of))), style: head)),
                  ]),
                DataRow(cells: [
                  const DataCell(Text('Total', style: head)),
                  const DataCell(Text('')),
                  for (final m in months) DataCell(Text(fmtRCents(total(ls.map((y) => of(y.months[m.month])))), style: head)),
                  DataCell(Text(fmtRCents(yearTotal), style: head)),
                ]),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Text(
            g == Emp201Group.declared
                ? 'On the EMP201: UIF is the employee\'s and the employer\'s together. Months before someone was registered show their salary only.'
                : 'Not on the EMP201 (tick "On EMP201" in Employees > List). UIF is what was taken off their pay -- red: UIF or PAYE taken off but not declared.',
            style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
          ),
        ),
      ],
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

/// [months] of [taxYear] as an .xlsx file, like the salary summary: the
/// months (worked out, submitted, difference), then per figure (salary,
/// UIF, SDL, PAYE) every employee with a column per month, in the three
/// groups, and every payslip line per month.
List<int> emp201YearXlsx(int taxYear, List<Emp201YearMonth> months, {List<Farm> farms = const []}) {
  final x = Excel.createExcel();
  final first = x.getDefaultSheet() ?? 'Sheet1';
  final sum = 'EMP201 $taxYear';
  x.rename(first, sum);
  CellValue t(String s) => TextCellValue(s);
  CellValue? n(double? v) => v == null ? null : DoubleCellValue((v * 100).roundToDouble() / 100);
  String month(String m) => DateFormat('MMMM yyyy').format(DateTime.parse(m));
  String farm(Employee? e) => farmShort(farms.where((f) => f.id == e?.farmId).firstOrNull);

  x.appendRow(sum, [t('Nanini 121 CC -- EMP201, tax year $taxYear (March ${taxYear - 1} to February $taxYear)')]);
  x.appendRow(sum, [t('')]);
  x.appendRow(sum, [
    t('Month'), t('Employees'), t('Remuneration'), t('UIF'), t('SDL'), t('PAYE'), t('Total'), //
    t('Submitted UIF'), t('Submitted SDL'), t('Submitted PAYE'), t('Submitted total'), t('Difference'), t('Submitted on'), t('Reference'), t('Source'),
  ]);
  for (final m in months) {
    final s = m.submitted;
    x.appendRow(sum, [
      t(month(m.month)), IntCellValue(m.employees), n(m.salary), n(m.uif), n(m.sdl), n(m.paye), n(m.total), //
      n(s?.uif), n(s?.sdl), n(s?.paye), n(s?.total), n(m.difference), s?.submittedOn == null ? null : t(s!.submittedOn!), s?.reference == null ? null : t(s!.reference!),
      t(m.lines.isEmpty ? '' : m.fromHistory ? 'Old salary summary' : 'App payslips'),
    ]);
  }
  double tot(double Function(Emp201YearMonth) f) => months.fold(0.0, (s, m) => s + f(m));
  final subs = months.where((m) => m.submitted != null);
  x.appendRow(sum, [
    t('Total'), null, n(tot((m) => m.salary)), n(tot((m) => m.uif)), n(tot((m) => m.sdl)), n(tot((m) => m.paye)), n(tot((m) => m.total)), //
    n(subs.fold<double>(0, (s, m) => s + m.submitted!.uif)), n(subs.fold<double>(0, (s, m) => s + m.submitted!.sdl)),
    n(subs.fold<double>(0, (s, m) => s + m.submitted!.paye)), n(subs.fold<double>(0, (s, m) => s + m.submitted!.total)),
    n(subs.fold<double>(0, (s, m) => s + m.difference!)),
  ]);
  x.appendRow(sum, [t('')]);
  x.appendRow(sum, [t('Only employees on the EMP201 count. UIF is the employees\' and the employer\'s together. Difference: submitted less worked out.')]);

  // Per figure: everyone, a column per month, in the three groups.
  final people = emp201YearByEmployee(months);
  final cols = [for (final m in months) DateFormat('MMM yyyy').format(DateTime.parse(m.month))];
  for (final f in _Figure.values) {
    final sheet = f.label;
    x.appendRow(sheet, [t('${f.label} per employee, tax year $taxYear')]);
    for (final g in Emp201Group.values) {
      final ls = people[g]!;
      x.appendRow(sheet, [t('')]);
      x.appendRow(sheet, [t(g.label)]);
      x.appendRow(sheet, [t('Employee'), t('Farm'), t('ID/passport'), for (final c in cols) t(c), t('Year')]);
      for (final y in ls) {
        // Not declared that month: no UIF, SDL or PAYE unless some was taken off.
        double? v(Emp201EmployeeMonth? l) => l == null || (f != _Figure.salary && f.of(l).abs() < 0.005) ? null : f.of(l);
        final vs = [for (final m in months) v(y.months[m.month])];
        x.appendRow(sheet, [
          t(y.name), t(farm(y.employee)), t(y.employee?.idOrPassport ?? ''), //
          for (final v in vs) n(v),
          n(vs.fold<double>(0, (s, v) => s + (v ?? 0))),
        ]);
      }
      final totals = [for (final m in months) ls.fold<double>(0, (s, y) => s + (y.months[m.month] == null ? 0 : f.of(y.months[m.month]!)))];
      x.appendRow(sheet, [t('Total'), null, null, for (final v in totals) n(v), n(totals.fold<double>(0, (s, v) => s + v))]);
    }
  }

  const per = 'Per month';
  x.appendRow(per, [t('Month'), t('Employee'), t('Farm'), t('Group'), t('Salary'), t('UIF'), t('SDL'), t('PAYE')]);
  for (final m in months) {
    for (final l in m.lines) {
      x.appendRow(per, [t(month(m.month)), t(l.name), t(farm(l.employee)), t(emp201GroupOf(l.employee).label), n(l.salary), n(l.uif), n(l.sdl), n(l.paye)]);
    }
  }
  x.setDefaultSheet(sum);
  return x.encode()!;
}

/// Which figure the per-employee tables show per month.
enum _Figure {
  salary('Salary'),
  uif('UIF'),
  sdl('SDL'),
  paye('PAYE');

  const _Figure(this.label);
  final String label;
  double of(Emp201EmployeeMonth l) => switch (this) {
        _Figure.salary => l.salary,
        _Figure.uif => l.uif,
        _Figure.sdl => l.sdl,
        _Figure.paye => l.paye,
      };
}
