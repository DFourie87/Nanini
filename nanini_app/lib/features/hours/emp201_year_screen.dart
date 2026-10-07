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
import 'emp201_year_sheet.dart';
import 'emp201_year_xlsx.dart';
import 'hours_models.dart';
import 'pdf_view_page.dart';

final _monthFmt = DateFormat('MMM yyyy');

/// The two SARS reports in Employees > Reports (admins).
enum TaxReport { emp201, emp501 }

/// A SARS report as a preview (zoom, print, share) and an Excel to download
/// and edit:
/// - [TaxReport.emp201]: one month's EMP201 -- employer and references,
///   PAYE, UIF (employees' and employer's), total and due date, what was
///   submitted on eFiling, and the month's pay per employee in the three
///   groups. Bottom: the month, Submitted (enter what went to SARS), Excel.
/// - [TaxReport.emp501]: the EMP501 reconciliation, interim (March to
///   August) or annual -- the certificates' totals against the EMP201s
///   declared, then each employee's IRP5/IT3(a). Bottom: the tax year,
///   Interim/Annual, Excel.
/// Months before the app's payroll come from the old salary summary.
class TaxReportScreen extends StatefulWidget {
  const TaxReportScreen({
    super.key,
    required this.report,
    required this.payslips,
    required this.employees,
    required this.includeSdl,
    this.farms = const [],
    this.month,
    this.raster,
  });
  final TaxReport report;
  final List<Payslip> payslips;
  final List<Employee> employees;
  final List<Farm> farms;
  final bool includeSdl;

  /// EMP201: the month to open on (else last month until the 7th, then this one).
  final DateTime? month;

  /// Draws the preview's pages (a stand-in in tests; else the printing one).
  final Stream<PdfRaster> Function(Uint8List pdf, List<int>? pages, double dpi)? raster;
  @override
  State<TaxReportScreen> createState() => _TaxReportScreenState();
}

class _TaxReportScreenState extends State<TaxReportScreen> {
  late DateTime month = widget.month ??
      DateTime(DateTime.now().year, DateTime.now().month - (DateTime.now().day <= 7 ? 1 : 0));
  // EMP501: the tax year just ended until the end of May, else this one; interim from September to February.
  late int taxYear = taxYearOf(DateTime.now()) - (DateTime.now().month >= 3 && DateTime.now().month <= 5 ? 1 : 0);
  late bool interim = DateTime.now().month >= 9 || DateTime.now().month <= 2;
  List<Emp201HistoryLine> history = [];
  List<Emp201Submitted> submitted = [];
  bool loaded = false;
  String? error;

  /// Bumped after a submission is saved: the preview is drawn again.
  int version = 0;

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

  List<Emp201YearMonth> _year(int y) => emp201Year(
        taxYear: y,
        payslips: widget.payslips,
        history: history,
        employees: widget.employees,
        submitted: submitted,
        includeSdl: widget.includeSdl,
      );

  Emp201YearMonth get _month => _year(taxYearOf(month)).firstWhere((m) => m.month == toDateStr(DateTime(month.year, month.month)));

  @override
  Widget build(BuildContext context) {
    final emp201 = widget.report == TaxReport.emp201;
    if (!loaded) {
      return Scaffold(appBar: NaniniAppBar(title: emp201 ? 'EMP201' : 'EMP501'), body: const Center(child: CircularProgressIndicator()));
    }
    final m = emp201 ? _month : null;
    final sections = emp201 ? emp201MonthSheet(m!, farms: widget.farms) : emp501Sheet(taxYear, _year(taxYear), interim: interim, farms: widget.farms);
    final label = emp201 ? 'EMP201 ${DateFormat('yyyy-MM').format(month)}' : 'EMP501 $taxYear ${interim ? 'interim' : 'annual'}';
    Widget errorOrSpace() => error != null
        ? Expanded(child: Text(error!, style: const TextStyle(color: NaniniColors.red, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis))
        : const Spacer();
    return PdfViewPage(
      key: ValueKey('$label-$version'),
      title: emp201 ? 'EMP201 -- ${DateFormat('MMMM yyyy').format(month)}' : 'EMP501 $taxYear -- ${interim ? 'interim' : 'annual'}',
      landscape: !emp201,
      fileName: '${label.replaceAll(' ', '-').toLowerCase()}.pdf',
      pdf: () async => (await buildSheetPdf(sections, landscape: !emp201)).save(),
      raster: widget.raster ?? (pdf, pages, dpi) => Printing.raster(pdf, pages: pages, dpi: dpi),
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: Row(children: [
          if (emp201) ...[
            IconButton(tooltip: 'Month before', onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left)),
            Text(_monthFmt.format(month), style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(tooltip: 'Next month', onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right)),
            errorOrSpace(),
            OutlinedButton.icon(
              onPressed: () => runOnce('tax_report.submitted', () => _editSubmitted(m!)),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Submitted'),
            ),
          ] else ...[
            IconButton(tooltip: 'Tax year before', onPressed: () => setState(() => taxYear--), icon: const Icon(Icons.chevron_left)),
            Text('$taxYear', style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(tooltip: 'Next tax year', onPressed: () => setState(() => taxYear++), icon: const Icon(Icons.chevron_right)),
            errorOrSpace(),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('Interim')), ButtonSegment(value: false, label: Text('Annual'))],
              selected: {interim},
              onSelectionChanged: (v) => setState(() => interim = v.first),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
            ),
          ],
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => runOnce('tax_report.xlsx', () => _download(sheetXlsx(emp201 ? 'EMP201' : 'EMP501', sections), '$label.xlsx')),
            icon: const Icon(Icons.download),
            label: const Text('Excel'),
          ),
        ]),
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
                Text('Worked out: PAYE ${fmtRCents(m.paye)} · UIF ${fmtRCents(m.uif)} · total ${fmtRCents(m.paye + m.uif)}',
                    style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                const SizedBox(height: 8),
                for (final (label, c) in [('PAYE', paye), ('UIF', uif)]) ...[
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

  /// Saves the report's Excel ([bytes]) as [name].
  Future<void> _download(List<int> bytes, String name) async {
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
