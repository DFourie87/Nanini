import 'dart:io';
import 'dart:typed_data';
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
import 'emp201_year_xlsx.dart';
import 'hours_models.dart';
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
