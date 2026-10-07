import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
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
import 'emp201_year_pdf.dart';
import 'hours_models.dart';
import 'payroll_month.dart';
import 'pay_widgets.dart';
import 'pdf_view_page.dart';

final _monthFmt = DateFormat('MMM yyyy');

/// Employees > Reports > EMP201 tax year (admins): a preview of the summary
/// sheet -- every month's EMP201 worked out against what was submitted to
/// SARS on eFiling ("Ingedien"), and everyone paid in the tax year per
/// month in three groups -- and the same as an Excel to download and edit.
/// Months before the app's payroll come from the old salary summary.
class Emp201YearScreen extends StatefulWidget {
  const Emp201YearScreen({super.key, required this.payslips, required this.employees, required this.includeSdl, this.farms = const [], this.raster});
  final List<Payslip> payslips;
  final List<Employee> employees;
  final List<Farm> farms;

  /// Draws the preview's pages (a stand-in in tests; else the printing one).
  final Stream<PdfRaster> Function(Uint8List pdf, List<int>? pages, double dpi)? raster;
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

  /// Bumped after a submission is saved: the preview is drawn again.
  int version = 0;

  List<Emp201YearMonth> get _months => emp201Year(
        taxYear: taxYear,
        payslips: widget.payslips,
        history: history,
        employees: widget.employees,
        submitted: submitted,
        includeSdl: widget.includeSdl,
      );

  /// Opens on a preview of the sheet (like the Calendar): zoom, print or
  /// share it; the bottom has the tax year, Submitted (each month's EMP201
  /// worked out -- tap one to enter what went to SARS) and the Excel.
  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Scaffold(appBar: NaniniAppBar(title: 'EMP201 tax year'), body: Center(child: CircularProgressIndicator()));
    }
    final months = _months;
    return PdfViewPage(
      key: ValueKey('$taxYear-$version'),
      title: 'EMP201 tax year $taxYear',
      landscape: true,
      fileName: 'emp201-$taxYear.pdf',
      pdf: () async => (await buildEmp201YearPdf(taxYear, months, farms: widget.farms)).save(),
      raster: widget.raster ?? (pdf, pages, dpi) => Printing.raster(pdf, pages: pages, dpi: dpi),
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: Row(children: [
          IconButton(tooltip: 'Tax year before', onPressed: () => setState(() => taxYear--), icon: const Icon(Icons.chevron_left)),
          Text('$taxYear', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(tooltip: 'Next tax year', onPressed: () => setState(() => taxYear++), icon: const Icon(Icons.chevron_right)),
          if (error != null)
            Expanded(child: Text(error!, style: const TextStyle(color: NaniniColors.red, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis))
          else
            const Spacer(),
          OutlinedButton.icon(
            onPressed: () => runOnce('emp201_year.months', () => _pickMonth(months)),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Submitted'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => runOnce('emp201_year.xlsx', () => _download(months)),
            icon: const Icon(Icons.download),
            label: const Text('Excel'),
          ),
        ]),
      ),
    );
  }

  /// Each month's EMP201 worked out (only that); tap one to enter what was
  /// submitted on eFiling -- shown in the sheet with the difference.
  Future<void> _pickMonth(List<Emp201YearMonth> months) async {
    final m = await showDialog<Emp201YearMonth>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('EMP201 per month -- $taxYear'),
        content: SizedBox(
          width: 420,
          child: ListView(shrinkWrap: true, children: [
            for (final m in months)
              ListTile(
                dense: true,
                title: Text('${_monthFmt.format(DateTime.parse(m.month))}${m.fromHistory ? ' *' : ''}'),
                subtitle: Text('UIF ${fmtRCents(m.uif)} · SDL ${fmtRCents(m.sdl)} · PAYE ${fmtRCents(m.paye)}'),
                trailing: Text(fmtRCents(m.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, m),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Tap a month to enter what was submitted on eFiling. * From the old salary summary.',
                  style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
    if (m != null && mounted) await _editSubmitted(m);
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
    if (mounted) setState(() => version++);
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
      // A month not paid yet: blank.
      t(month(m.month)), m.lines.isEmpty ? null : IntCellValue(m.employees), //
      for (final v in [m.salary, m.uif, m.sdl, m.paye, m.total]) m.lines.isEmpty ? null : n(v),
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
