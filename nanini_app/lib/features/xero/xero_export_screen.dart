import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session.dart';
import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../delivery/delivery_repository.dart';
import '../sales/sales_models.dart';
import '../sales/sales_repository.dart';
import '../suppliers/suppliers_repository.dart';
import 'xero_export.dart';

/// Financials > Xero export: the account sales as Xero sales invoices (at
/// nett, a period from Xero's conversion date on), and the customers and
/// suppliers as Xero contacts -- each saved as the CSV Xero imports.
class XeroExportScreen extends StatefulWidget {
  const XeroExportScreen({super.key, this.save});

  /// Saves a file (name, bytes); null: asks where (tests pass their own).
  final Future<bool> Function(String name, Uint8List bytes)? save;

  @override
  State<XeroExportScreen> createState() => _XeroExportScreenState();
}

class _XeroExportScreenState extends State<XeroExportScreen> {
  late DateTime from;
  late DateTime to;

  @override
  void initState() {
    super.initState();
    // Last month (not before the conversion date).
    final now = DateTime.now();
    final first = DateTime.parse(kXeroFrom);
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    from = lastMonth.isBefore(first) ? first : lastMonth;
    final end = DateTime(now.year, now.month, 0);
    to = end.isBefore(from) ? now : end;
  }

  Future<void> _pick(bool isFrom) async {
    final first = DateTime.parse(kXeroFrom);
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? from : to,
      firstDate: first,
      lastDate: DateTime(2100),
      helpText: isFrom ? 'From' : 'To',
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        from = picked;
        if (to.isBefore(from)) to = from;
      } else {
        to = picked;
        if (from.isAfter(to)) from = to;
      }
    });
  }

  String get _period => '${toDateStr(from)} to ${toDateStr(to)}';

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final text = Theme.of(context).textTheme;
    Widget card({required String title, required String body, required String button, required Future<void> Function() onSave, required String key}) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: text.titleMedium),
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(color: NaniniColors.muted)),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: Key(key),
                onPressed: () => runOnce(key, onSave),
                icon: const Icon(Icons.download),
                label: Text(button),
              ),
            ]),
          ),
        );
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      appBar: const NaniniAppBar(title: 'Xero export'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (session.hasModule('sales')) ...[
            card(
              key: 'xero_invoices',
              title: 'Sales invoices',
              body: 'Every account sale from ${fmtDateDisplay(toDateStr(from))} to ${fmtDateDisplay(toDateStr(to))}, one invoice each at the nett '
                  'the agent pays: the produce (gross), less the commission, market fees, levies and bank charges with their VAT '
                  '(each to its expense), plus pallets paid for. In Xero: Business > Invoices > Import -- no address update, Tax Exclusive.',
              button: 'Save invoices CSV',
              onSave: _saveInvoices,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Period:', style: TextStyle(color: NaniniColors.muted)),
                OutlinedButton(key: const Key('xero_from'), onPressed: () => _pick(true), child: Text('From ${fmtDateDisplay(toDateStr(from))}')),
                OutlinedButton(key: const Key('xero_to'), onPressed: () => _pick(false), child: Text('To ${fmtDateDisplay(toDateStr(to))}')),
              ]),
            ),
            card(
              key: 'xero_customers',
              title: 'Customers',
              body: 'Sales > Customers as Xero contacts (name, account number, contact person). In Xero: Contacts > Import.',
              button: 'Save customers CSV',
              onSave: _saveCustomers,
            ),
          ],
          if (session.hasModule('suppliers'))
            card(
              key: 'xero_suppliers',
              title: 'Suppliers',
              body: 'The suppliers as Xero contacts, with address, VAT number, bank details and payment terms. In Xero: Contacts > Import. '
                  'The file holds bank details: keep it private and delete it once imported.',
              button: 'Save suppliers CSV',
              onSave: _saveSuppliers,
            ),
          if (!session.hasModule('sales') && !session.hasModule('suppliers'))
            const Padding(padding: EdgeInsets.all(24), child: Text('Sales or Suppliers must be enabled for your account.', style: TextStyle(color: NaniniColors.muted))),
        ],
      ),
    );
  }

  Future<void> _saveInvoices() async {
    try {
      final reports = await _reports(toDateStr(from), toDateStr(to));
      if (reports.isEmpty) {
        if (mounted) showToast(context, 'No account sales from ${fmtDateDisplay(toDateStr(from))} to ${fmtDateDisplay(toDateStr(to))}.');
        return;
      }
      final ids = [for (final r in reports) r.id!];
      final lines = <String, List<SalesLineItem>>{};
      final deductions = <String, List<XeroDeduction>>{};
      for (var i = 0; i < ids.length; i += 100) {
        final part = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
        for (final li in await SalesRepository().fetchLineItemsForReports(part)) {
          lines.putIfAbsent(li.reportId ?? '', () => []).add(li);
        }
        try {
          final rows = await sb.from('sales_deductions').select().inFilter('report_id', part);
          for (final r in rows as List) {
            final d = XeroDeduction.fromJson(r as Map<String, dynamic>);
            deductions.putIfAbsent(d.reportId, () => []).add(d);
          }
        } catch (_) {
          // No sales_deductions table yet: one "Commission and charges" line each.
        }
      }
      final invoices = xeroInvoices(reports: reports, lineItems: lines, deductions: deductions, customers: await SalesRepository().fetchCustomers());
      final saved = await _save('Xero sales invoices $_period.csv', xeroInvoiceRows(invoices));
      if (!saved || !mounted) return;
      final nett = invoices.fold(0.0, (s, i) => s + i.total);
      final oneLine = invoices.where((i) => !i.deductionsByLine).length;
      showToast(context, 'Saved ${invoices.length} invoices, nett ${fmtRCents(nett)}'
          '${oneLine == 0 ? '' : ' -- $oneLine with the deductions as one line (not read line by line yet)'}');
    } catch (e) {
      if (mounted) await showProblem(context, friendlyDbError(e), title: 'Could not export');
    }
  }

  Future<void> _saveCustomers() async {
    try {
      final customers = await SalesRepository().fetchCustomers();
      final recipients = await DeliveryRepository().fetchMarketAgents();
      if (await _save('Xero customers.csv', xeroCustomerRows(customers, recipients)) && mounted) {
        showToast(context, 'Saved ${customers.length} customers');
      }
    } catch (e) {
      if (mounted) await showProblem(context, friendlyDbError(e), title: 'Could not export');
    }
  }

  Future<void> _saveSuppliers() async {
    try {
      final suppliers = await SuppliersRepository().fetchSuppliers();
      if (await _save('Xero suppliers.csv', xeroSupplierRows(suppliers)) && mounted) {
        showToast(context, 'Saved ${suppliers.length} suppliers');
      }
    } catch (e) {
      if (mounted) await showProblem(context, friendlyDbError(e), title: 'Could not export');
    }
  }

  /// The account sales dated [from] to [to] (yyyy-MM-dd), all pages.
  Future<List<SalesReport>> _reports(String from, String to) async {
    final out = <SalesReport>[];
    for (var at = 0;; at += 1000) {
      final rows = await sb.from('sales_reports').select().gte('report_date', from).lte('report_date', to).order('report_date').order('id').range(at, at + 999);
      out.addAll((rows as List).map((r) => SalesReport.fromJson(r as Map<String, dynamic>)));
      if (rows.length < 1000) return out;
    }
  }

  /// Saves [rows] as a CSV called [name]. True when saved.
  Future<bool> _save(String name, List<List<String>> rows) async {
    final bytes = Uint8List.fromList(utf8.encode(const ListToCsvConverter().convert(rows)));
    if (widget.save != null) return widget.save!(name, bytes);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save $name',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      bytes: bytes,
    );
    if (path == null) return false;
    // Windows and the desktop only give the path: write it here.
    if (!Platform.isAndroid && !Platform.isIOS) await File(path).writeAsBytes(bytes);
    return true;
  }
}
