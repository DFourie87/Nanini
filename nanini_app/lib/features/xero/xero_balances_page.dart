import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../sales/sales_customers_models.dart';
import '../sales/sales_models.dart';
import '../sales/sales_repository.dart';
import '../suppliers/suppliers_models.dart';
import '../suppliers/suppliers_repository.dart';
import 'xero_api.dart';
import 'xero_export.dart';
import 'xero_sync.dart';

/// What the hub has: each supplier's balance and customer's, and the
/// suppliers with their payments (to take Xero's payments in).
class XeroHubSide {
  XeroHubSide({
    required this.suppliersDue,
    required this.customersOwed,
    required this.suppliers,
    required this.payments,
    this.customers = const [],
    this.reports = const [],
    this.received = const [],
  });
  final Map<String, double> suppliersDue;
  final Map<String, double> customersOwed;
  final List<Supplier> suppliers;
  final List<SupplierPayment> payments;

  /// The customers, their account sales and payments (to take Xero's in).
  final List<Customer> customers;
  final List<SalesReport> reports;
  final List<CustomerPayment> received;

  static Future<XeroHubSide> load() async {
    final repo = SuppliersRepository();
    final suppliers = await repo.fetchSuppliers();
    final docs = await repo.fetchDocs();
    final payments = await repo.fetchPayments();
    final sales = SalesRepository();
    final customers = await sales.fetchCustomers();
    final reports = await sales.fetchReports();
    final received = await sales.fetchCustomerPayments();
    return XeroHubSide(
      suppliersDue: {for (final s in suppliers) s.name: SupplierAccount(s, docs, payments).due},
      customersOwed: {for (final c in customers) c.name: CustomerAccount(c, reports, received).owed},
      suppliers: suppliers,
      payments: payments,
      customers: customers,
      reports: reports,
      received: received,
    );
  }
}

/// Financials > Xero export > Balances in Xero: every customer's and
/// supplier's balance in Xero beside the hub's, the differences first; and
/// the supplier payments made in Xero taken into the hub (instead of the
/// bank CSV), each only once.
class XeroBalancesPage extends StatefulWidget {
  const XeroBalancesPage({super.key, required this.api, this.loadHub = XeroHubSide.load, this.addPayment, this.addCustomerPayment});
  final XeroApi api;
  final Future<XeroHubSide> Function() loadHub;

  /// Saves a payment to a supplier; null: the database.
  final Future<void> Function(XeroPaymentToAdd p)? addPayment;

  /// Saves a customer's payment; null: the database.
  final Future<void> Function(XeroCustomerPaymentToAdd p)? addCustomerPayment;

  @override
  State<XeroBalancesPage> createState() => _XeroBalancesPageState();
}

class _XeroBalancesPageState extends State<XeroBalancesPage> {
  List<XeroBalanceRow>? rows;
  XeroHubSide? hub;
  String? problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => problem = null);
    try {
      final xero = await widget.api.contactBalances();
      final h = await widget.loadHub();
      if (!mounted) return;
      setState(() {
        hub = h;
        rows = xeroBalanceRows(xero: xero, suppliersDue: h.suppliersDue, customersOwed: h.customersOwed);
      });
    } catch (e) {
      if (mounted) setState(() => problem = e is XeroProblem ? e.message : friendlyDbError(e));
    }
  }

  Future<void> _takePayments() async {
    final h = hub;
    if (h == null) return;
    try {
      final r = xeroSupplierPaymentsToAdd(out: await widget.api.moneyOut(kXeroFrom), suppliers: h.suppliers, payments: h.payments);
      if (!mounted) return;
      if (r.add.isEmpty) {
        await showProblem(
          context,
          'The hub has every supplier payment Xero has from ${fmtDateDisplay(kXeroFrom)} (${r.alreadyIn} already in).'
          '${r.notSuppliers.isEmpty ? '' : '\n\nPaid in Xero to contacts that aren\'t hub suppliers (left alone): ${_names(r.notSuppliers)}'}',
          title: 'Nothing new from Xero',
        );
        return;
      }
      final total = r.add.fold(0.0, (t, p) => t + p.money.amount);
      final ok = await confirmDialog(
        context,
        title: 'Take ${r.add.length} payment(s) from Xero?',
        message:
            '${r.add.take(12).map((p) => '${fmtDateDisplay(p.money.date)}  ${p.supplier.name}  ${fmtRCents(p.money.amount)}  (${p.money.what})').join('\n')}'
            '${r.add.length > 12 ? '\n...' : ''}\n\nTogether ${fmtRCents(total)}. ${r.alreadyIn} already in the hub (from the bank or Xero) are left out.'
            '${r.notSuppliers.isEmpty ? '' : '\n\nNot hub suppliers (left alone): ${_names(r.notSuppliers)}'}',
        confirmLabel: 'Take them in',
      );
      if (!ok) return;
      final add =
          widget.addPayment ??
          (p) => SuppliersRepository().addPayment(supplierId: p.supplier.id, date: p.money.date, amount: p.money.amount, reference: 'Xero', notes: p.notes);
      for (final p in r.add) {
        await add(p);
      }
      if (!mounted) return;
      showToast(context, 'Took ${r.add.length} payment(s) from Xero, ${fmtRCents(total)}');
      await _load();
    } catch (e) {
      if (mounted) await showProblem(context, e is XeroProblem ? e.message : friendlyDbError(e), title: 'Could not take the payments');
    }
  }

  Future<void> _takeCustomerPayments() async {
    final h = hub;
    if (h == null) return;
    try {
      final r = xeroCustomerPaymentsToAdd(incoming: await widget.api.moneyIn(kXeroFrom), customers: h.customers, reports: h.reports, payments: h.received);
      if (!mounted) return;
      final others = [
        if (r.notSales.isNotEmpty) 'Invoices that aren\'t account sales (e.g. pallets; left alone): ${_names(r.notSales)}',
        if (r.notCustomers.isNotEmpty) 'Not hub customers (left alone): ${_names(r.notCustomers)}',
      ].join('\n\n');
      if (r.add.isEmpty) {
        await showProblem(
          context,
          'The hub has every customer payment Xero has from ${fmtDateDisplay(kXeroFrom)} (${r.alreadyIn} already in).${others.isEmpty ? '' : '\n\n$others'}',
          title: 'Nothing new from Xero',
        );
        return;
      }
      final total = r.add.fold(0.0, (t, p) => t + p.amount);
      final ok = await confirmDialog(
        context,
        title: 'Take ${r.add.length} customer payment(s) from Xero?',
        message:
            '${r.add.take(12).map((p) => '${fmtDateDisplay(p.date)}  ${p.customer.name}  ${fmtRCents(p.amount)}  (${p.lines.map((l) => l.reportNumber).join(', ')})').join('\n')}'
            '${r.add.length > 12 ? '\n...' : ''}\n\nTogether ${fmtRCents(total)}. ${r.alreadyIn} already in the hub (from a payment summary or Xero) are left out.'
            '${others.isEmpty ? '' : '\n\n$others'}',
        confirmLabel: 'Take them in',
      );
      if (!ok) return;
      final add = widget.addCustomerPayment ??
          (p) => SalesRepository().addCustomerPayment(
              customerId: p.customer.id, date: p.date, amount: p.amount, method: 'Xero', fileName: p.fileName, lines: p.lines);
      for (final p in r.add) {
        await add(p);
      }
      if (!mounted) return;
      showToast(context, 'Took ${r.add.length} customer payment(s) from Xero, ${fmtRCents(total)}');
      await _load();
    } catch (e) {
      if (mounted) await showProblem(context, e is XeroProblem ? e.message : friendlyDbError(e), title: 'Could not take the payments');
    }
  }

  static String _names(Map<String, double> m) {
    final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return '${e.take(8).map((x) => '${x.key} ${fmtRCents(x.value)}').join(', ')}${e.length > 8 ? ', ...' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final list = rows;
    final differ = list?.where((r) => r.differs).length ?? 0;
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      appBar: NaniniAppBar(
        title: 'Balances in Xero',
        actions: [
          IconButton(
            key: const Key('xero_balances_reload'),
            tooltip: 'Again from Xero',
            onPressed: () => runOnce('xero_balances_reload', _load),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: problem != null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(problem!, style: const TextStyle(color: NaniniColors.red)),
            )
          : list == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(differ == 0 ? 'Xero and the hub agree' : '$differ differ', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        const Text(
                          'What each supplier is owed (Xero: accounts payable) and each customer owes (accounts receivable), in Xero and in the hub. '
                          'Payments made in Xero come into the hub with the buttons -- each only once: supplier payments not already brought by the bank, '
                          'and customers\' payments of account sales not already on a payment summary.',
                          style: TextStyle(color: NaniniColors.muted),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              key: const Key('xero_take_payments'),
                              onPressed: () => runOnce('xero_take_payments', _takePayments),
                              icon: const Icon(Icons.download),
                              label: const Text('Supplier payments from Xero'),
                            ),
                            FilledButton.icon(
                              key: const Key('xero_take_customer_payments'),
                              onPressed: () => runOnce('xero_take_customer_payments', _takeCustomerPayments),
                              icon: const Icon(Icons.download),
                              label: const Text('Customer payments from Xero'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                for (final (kind, heading) in const [('Customer', 'Customers'), ('Supplier', 'Suppliers'), ('Only in Xero', 'Only in Xero')])
                  if (list.any((r) => r.kind == kind)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                      child: Text(
                        '$heading${list.where((r) => r.kind == kind && r.differs).isEmpty ? '' : ' -- ${list.where((r) => r.kind == kind && r.differs).length} differ'}',
                        key: Key('xero_heading_$kind'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    for (final r in list.where((r) => r.kind == kind)) _row(r),
                  ],
              ],
            ),
    );
  }

  Widget _row(XeroBalanceRow r) => Card(
    child: ListTile(
      key: Key('xero_balance_${r.name}'),
      title: Text(r.name),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('Xero ${r.xero == null ? '-' : fmtRCents(r.xero!)}'),
          Text('Hub ${r.hub == null ? '-' : fmtRCents(r.hub!)}', style: const TextStyle(color: NaniniColors.muted)),
          if (r.differs)
            Text(
              '${r.difference > 0 ? '+' : ''}${fmtRCents(r.difference)}',
              style: const TextStyle(color: NaniniColors.red, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    ),
  );
}
