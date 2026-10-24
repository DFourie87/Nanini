import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../hours/emp201_year_pdf.dart';
import '../hours/emp201_year_xlsx.dart';
import '../hours/pdf_view_page.dart';
import 'customer_ledger.dart';
import 'sales_customers_models.dart';
import 'sales_data.dart';
import 'sales_models.dart';

/// Sales > Customer ledger: every market agent's account for a period, as
/// a sheet (a summary, then a customer each) -- previewed, and saved as
/// Excel with a sheet per customer.
class CustomerLedgerScreen extends StatefulWidget {
  const CustomerLedgerScreen({super.key, required this.data, this.raster});
  final SalesData data;

  /// For tests: draws the preview's pages.
  final Stream<PdfRaster> Function(Uint8List pdf, List<int>? pages, double dpi)? raster;

  @override
  State<CustomerLedgerScreen> createState() => _CustomerLedgerScreenState();
}

class _CustomerLedgerScreenState extends State<CustomerLedgerScreen> {
  // This month so far.
  DateTime from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime to = DateTime.now();

  /// One customer only (its id); null: all.
  String? customerId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.data,
      builder: (context, _) {
        final data = widget.data;
        if (data.customersMissing) {
          return Scaffold(
            appBar: const NaniniAppBar(title: 'Customer ledger'),
            body: const Padding(
              padding: EdgeInsets.all(24),
              child: Text('The customers can\'t be read -- run customers.sql in Supabase first.', style: TextStyle(color: NaniniColors.red)),
            ),
          );
        }
        final customers = [...data.customers ?? const <Customer>[]]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        final reports = data.reports ?? const <SalesReport>[];
        // Line items of the period's account sales (the subcategory columns).
        final f = toDateStr(from), t = toDateStr(to);
        final ids = [for (final r in reports) if (r.id != null && r.reportDate.compareTo(f) >= 0 && r.reportDate.compareTo(t) <= 0) r.id!];
        final loaded = data.itemsFor(ids);
        if (data.reports == null || data.customers == null || loaded == null) {
          return const Scaffold(appBar: NaniniAppBar(title: 'Customer ledger'), body: Center(child: CircularProgressIndicator()));
        }
        final items = <String, List<SalesLineItem>>{};
        for (final li in loaded) {
          (items[li.reportId ?? ''] ??= []).add(li);
        }
        final one = customers.where((c) => c.id == customerId).firstOrNull;
        var sections = customerLedgerSheet(
          customers: one == null ? customers : [one],
          reports: one == null ? reports : reports.where((r) => r.agent == one.agent).toList(),
          items: items,
          payments: data.customerPayments ?? const [],
          from: f,
          to: t,
        );
        // One customer: just its ledger, no summary.
        if (one != null && sections.length > 1) sections = sections.sublist(1);
        final label = 'Customer ledger ${one?.name ?? 'all'} $f to $t';

        return PdfViewPage(
          key: ValueKey(label),
          title: 'Customer ledger -- ${fmtDateDisplay(f)} to ${fmtDateDisplay(t)}',
          landscape: true,
          fileName: '${label.replaceAll(RegExp(r'[^A-Za-z0-9-]+'), '-').toLowerCase()}.pdf',
          pdf: () async => (await buildSheetPdf(sections)).save(),
          raster: widget.raster ?? (pdf, pages, dpi) => Printing.raster(pdf, pages: pages, dpi: dpi),
          bottom: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => runOnce('customer_ledger.from', () async {
                    final d = await showDatePicker(context: context, initialDate: from, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setState(() => from = d);
                  }),
                  child: Text('From ${fmtDateDisplay(f)}'),
                ),
                OutlinedButton(
                  onPressed: () => runOnce('customer_ledger.to', () async {
                    final d = await showDatePicker(context: context, initialDate: to, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setState(() => to = d);
                  }),
                  child: Text('To ${fmtDateDisplay(t)}'),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String?>(
                    initialValue: customerId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Customer', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All customers')),
                      for (final c in customers) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => customerId = v),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => runOnce('customer_ledger.xlsx', () => _download(sheetXlsx('Ledger', sections, sheetPerSection: true), '$label.xlsx')),
                  icon: const Icon(Icons.download),
                  label: const Text('Excel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Saves the ledger's Excel ([bytes]) as [name].
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
