import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session.dart';
import '../../core/formatters.dart';
import '../../core/live_rows.dart';
import '../../core/run_once.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../delivery/delivery_repository.dart';
import '../sales/sales_models.dart';
import '../sales/sales_repository.dart';
import '../suppliers/suppliers_models.dart';
import '../suppliers/suppliers_repository.dart';
import 'xero_export.dart';

/// Financials > Xero export: the account sales as Xero sales invoices (at
/// nett) and the supplier invoices as Xero bills (a line per item), for a
/// period from Xero's conversion date on, and the customers and suppliers as
/// Xero contacts -- each saved as the CSV Xero imports.
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
          if (session.hasModule('sales') || session.hasModule('suppliers'))
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Period:', style: TextStyle(color: NaniniColors.muted)),
                OutlinedButton(key: const Key('xero_from'), onPressed: () => _pick(true), child: Text('From ${fmtDateDisplay(toDateStr(from))}')),
                OutlinedButton(key: const Key('xero_to'), onPressed: () => _pick(false), child: Text('To ${fmtDateDisplay(toDateStr(to))}')),
              ]),
            ),
          if (session.hasModule('sales'))
            card(
              key: 'xero_invoices',
              title: 'Sales invoices',
              body: 'Every account sale in the period, one invoice each at the nett '
                  'the agent pays: the produce (gross), less the commission, market fees, levies and bank charges with their VAT '
                  '(each to its expense), plus pallets paid for. In Xero: Business > Invoices > Import -- no address update, Tax Exclusive.',
              button: 'Save invoices CSV',
              onSave: _saveInvoices,
            ),
          if (session.hasModule('suppliers'))
            card(
              key: 'xero_bills',
              title: 'Supplier invoices',
              body: 'Every confirmed supplier invoice, credit note and bill in the period, one bill each with a line per item against '
                  'its account (as in Expenses > Purchases) and its VAT. In Xero: Business > Bills to pay > Import -- no address update, '
                  'Tax Exclusive.',
              button: 'Save supplier invoices CSV',
              onSave: _saveBills,
            ),
          if (session.hasModule('sales'))
            card(
              key: 'xero_customers',
              title: 'Customers',
              body: 'Sales > Customers as Xero contacts (name, account number, contact person). In Xero: Contacts > Import.',
              button: 'Save customers CSV',
              onSave: _saveCustomers,
            ),
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

  Future<void> _saveBills() async {
    try {
      final repo = SuppliersRepository();
      final suppliers = await repo.fetchSuppliers();
      final docs = await repo.fetchDocs();
      final payments = await repo.fetchPayments();
      Future<List<Map<String, dynamic>>> rows(String table, String orderBy, [String key = 'id']) async {
        try {
          return await fetchAllRows(table, orderBy: orderBy, key: key);
        } catch (_) {
          return const []; // the purchases tables not there yet: each document as one line
        }
      }

      final chart = (await rows('gl_accounts', 'code', 'code')).map(GlAccount.fromJson).toList();
      final docLines = (await rows('supplier_doc_lines', 'doc_id')).map(DocLine.fromJson).toList();
      final rules = (await rows('supplier_gl_rules', 'item')).map(GlRule.fromJson).toList();
      final accounts = [for (final s in suppliers) SupplierAccount(s, docs, payments)];
      final bills = xeroBills(purchasesFor(accounts, docLines, rules, toDateStr(from), toDateStr(to), chart: chart));
      if (!mounted) return;
      if (bills.isEmpty) {
        showToast(context, 'No supplier invoices from ${fmtDateDisplay(toDateStr(from))} to ${fmtDateDisplay(toDateStr(to))}.');
        return;
      }
      final unallocated = [for (final b in bills) for (final l in b.lines) if ((l.account ?? '').isEmpty) (b, l)];
      if (unallocated.isNotEmpty) {
        // Per supplier, most first: setting a supplier's "Supplier of" account allocates all its lines at once.
        final per = <String, int>{};
        for (final (b, _) in unallocated) {
          per[b.supplier.name] = (per[b.supplier.name] ?? 0) + 1;
        }
        final list = per.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final go = await confirmDialog(
          context,
          title: '${unallocated.length} line(s) without an account',
          message: '${list.take(10).map((e) => '${e.key}: ${e.value}').join('\n')}${list.length > 10 ? '\n...' : ''}\n\n'
              'Save them on $kXeroSuspense (Suspense) and put them against the right account in Xero later -- or Cancel, '
              "and give the supplier a \"Supplier of\" account in Suppliers (all its lines go there), or put lines against an "
              'account in Expenses > Purchases (tap the line), then save again.',
          confirmLabel: 'Save, on Suspense',
        );
        if (!go || !mounted) return;
      }
      if (!await _save('Xero supplier invoices $_period.csv', xeroBillRows(bills, fallbackAccount: kXeroSuspense)) || !mounted) return;
      final total = bills.fold(0.0, (s, b) => s + b.total);
      final noVat = [for (final b in bills) for (final l in b.lines) if (l.vat == null) l].length;
      showToast(context, 'Saved ${bills.length} supplier invoices, ${fmtRCents(total)}'
          '${unallocated.isEmpty ? '' : ' -- ${unallocated.length} line(s) on Suspense'}'
          '${noVat == 0 ? '' : ' -- $noVat line(s) with no VAT read: No VAT in Xero, check them'}');
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
