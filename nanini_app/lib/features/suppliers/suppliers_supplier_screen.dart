import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import 'suppliers_data.dart';
import 'suppliers_models.dart';
import 'suppliers_overview_screen.dart';
import 'suppliers_period.dart';
import 'suppliers_recon_screen.dart';
import '../../core/run_once.dart';

/// One supplier, each thing once: the recon for the period (opening balance
/// + invoices - credit notes - payments = amount due), when it's payable and
/// whether the latest statement agrees; then (documents from email wait in
/// the inbox) the lines with the running balance (statements checked).
/// "Details" at the top: banking, terms, contact. "+" adds an invoice,
/// credit note, statement or payment.
class SupplierScreen extends StatefulWidget {
  const SupplierScreen({super.key, required this.data, required this.supplierId});
  final SuppliersData data;
  final String supplierId;

  @override
  State<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  SupplierPeriod period = SupplierPeriod.taxYearToDate(DateTime.now());

  /// Details (banking, terms, contact) instead of the account.
  bool details = false;

  SuppliersData get data => widget.data;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final a = data.accounts.where((x) => x.supplier.id == widget.supplierId).firstOrNull;
        return Scaffold(
          appBar: NaniniAppBar(
            title: a?.supplier.name ?? 'Supplier',
            actions: [
              if (a != null) ...[
                IconButton(tooltip: 'Share as CSV', icon: const Icon(Icons.ios_share), onPressed: () => runOnce('suppliers_supplier_screen.1', () => _share(a, a.period(period.from, period.to)))),
                PopupMenuButton<String>(
                  tooltip: 'Add',
                  icon: const Icon(Icons.add_circle_outline),
                  onSelected: (v) => switch (v) {
                    'payment' => addSupplierPayment(context, data, a.supplier),
                    'statement' => addSupplierDoc(context, data, a.supplier, SupplierDocKind.statement),
                    'credit' => addSupplierDoc(context, data, a.supplier, SupplierDocKind.creditNote),
                    _ => addSupplierDoc(context, data, a.supplier, SupplierDocKind.invoice),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'invoice', child: Text('Invoice')),
                    PopupMenuItem(value: 'credit', child: Text('Credit note')),
                    PopupMenuItem(value: 'statement', child: Text('Statement')),
                    PopupMenuItem(value: 'payment', child: Text('Payment')),
                  ],
                ),
              ],
            ],
          ),
          body: a == null ? const Center(child: CircularProgressIndicator()) : _body(context, a),
        );
      },
    );
  }

  Widget _body(BuildContext context, SupplierAccount a) {
    final p = a.period(period.from, period.to);
    final toDate = period.to.compareTo(toDateStr(DateTime.now())) >= 0;
    final today = toDateStr(DateTime.now());
    final statement = p.lines.where((l) => l.check).lastOrNull;
    final picker = SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: false, label: Text('Account'), icon: Icon(Icons.menu_book_outlined)),
        ButtonSegment(value: true, label: Text('Details'), icon: Icon(Icons.info_outline)),
      ],
      selected: {details},
      onSelectionChanged: (v) => setState(() => details = v.first),
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
    );
    if (details) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [picker, const SizedBox(height: 12), ...supplierDetailsSection(context, data, a)],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        picker,
        const SizedBox(height: 12),
        PeriodBar(period: period, onChanged: (v) => setState(() => period = v)),
        const SizedBox(height: 10),
        if (a.hiddenByOpening > 0) _openingWarning(context, a),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _row('Opening balance ${fmtDateDisplay(p.from)}', p.opening),
                _row('+ Invoices', p.invoices),
                if (p.creditNotes != 0) _row('- Credit notes', -p.creditNotes),
                _row('- Payments', -p.payments),
                if (p.statementCharges != 0) _row('± Per statements (charges, interest)', p.statementCharges),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        toDate ? (p.closing < -0.005 ? '= In credit' : '= Amount due') : '= Owed on ${fmtDateDisplay(p.to)}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                      ),
                    ),
                    Text(_amount(p.closing), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: _colour(p.closing))),
                  ],
                ),
                // When it's payable (only for what's owed now).
                if (toDate && a.due > 0.005)
                  for (final x in a.payable)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        x.dueDate.compareTo(today) < 0
                            ? '${fmtRCents(x.amount)} due now (was due ${fmtDateDisplay(x.dueDate)})'
                            : '${fmtRCents(x.amount)} by ${fmtDateDisplay(x.dueDate)}',
                        style: TextStyle(color: x.dueDate.compareTo(today) < 0 ? NaniniColors.red : NaniniColors.muted),
                      ),
                    ),
                // The latest statement in the period against the account.
                if (statement != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    statement.amount.abs() < 0.01
                        ? '✓ Statement ${fmtDateDisplay(statement.date)}: ${_amount(statement.doc!.amount)} -- matches'
                        : 'Statement ${fmtDateDisplay(statement.date)}: ${_amount(statement.doc!.amount)} -- '
                            '${statement.amount > 0 ? '${fmtRCents(statement.amount)} more' : '${fmtRCents(-statement.amount)} less'} than ours, to follow up',
                    style: TextStyle(color: statement.amount.abs() < 0.01 ? NaniniColors.green : NaniniColors.amber, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Lines', style: Theme.of(context).textTheme.titleMedium),
        const Text('Newest first. Tap a line to open its PDF; hold it to remove it.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
        const SizedBox(height: 4),
        if (p.lines.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nothing in this period. Add an invoice, statement or payment with + at the top.', style: TextStyle(color: NaniniColors.muted)),
          )
        else
          // Newest at the top.
          Card(child: Column(children: [for (final l in p.lines.reversed) LedgerTile(line: l, data: data)])),
      ],
    );
  }

  Widget _openingWarning(BuildContext context, SupplierAccount a) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: NaniniColors.amber)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'The opening balance (${fmtRCents(a.supplier.openingBalance)}) is dated ${fmtDateDisplay(a.supplier.openingDate)}: '
                '${a.hiddenByOpening} invoice(s) and payment(s) before that date are left out. '
                'Most suppliers start on 1 March (the tax year) -- change its date.',
                style: const TextStyle(color: NaniniColors.amber, fontWeight: FontWeight.w600),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => runOnce('suppliers_supplier_screen.2', () => editSupplier(context, data, s: a.supplier)), child: const Text('Change details')),
              ),
            ],
          ),
        ),
      );

  static String _amount(double v) => v < -0.005 ? '-${fmtRCents(-v)}' : fmtRCents(v);
  static Color _colour(double v) => v > 0.005 ? NaniniColors.red : v < -0.005 ? NaniniColors.green : NaniniColors.muted;

  Widget _row(String label, double v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(_amount(v), maxLines: 1, softWrap: false),
          ],
        ),
      );

  Future<void> _share(SupplierAccount a, PeriodAccount p) async {
    String n(double v) => v.toStringAsFixed(2);
    final rows = <List<Object?>>[
      ['Date', 'Description', 'Debit', 'Credit', 'Balance'],
      [p.from, 'Opening balance', '', '', n(p.opening)],
      for (final l in p.lines)
        l.check
            ? [l.date, 'Statement ${n(l.doc!.amount)}${l.amount.abs() < 0.01 ? ' -- matches' : ' -- differs by ${n(l.amount)}'}', '', '', n(l.balance)]
            : [l.date, l.label, l.amount > 0 ? n(l.amount) : '', l.amount < 0 ? n(-l.amount) : '', n(l.balance)],
      [p.to, 'Amount due', '', '', n(p.closing)],
    ];
    await Share.share(const ListToCsvConverter().convert(rows), subject: '${a.supplier.name} account ${p.from} to ${p.to}.csv');
  }
}
