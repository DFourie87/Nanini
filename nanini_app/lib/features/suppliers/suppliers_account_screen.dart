import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import 'suppliers_data.dart';
import 'suppliers_models.dart';
import 'suppliers_period.dart';
import 'suppliers_recon_screen.dart';

/// A supplier's account (its GL account) for a period: the opening balance,
/// invoices, credit notes, payments and statements line by line with the
/// running balance, and the closing balance -- what was due at the end.
class SuppliersAccountScreen extends StatelessWidget {
  const SuppliersAccountScreen({super.key, required this.data, required this.supplierId, required this.onSupplier, required this.period, required this.onPeriod});
  final SuppliersData data;
  final String? supplierId;
  final ValueChanged<String> onSupplier;
  final SupplierPeriod period;
  final ValueChanged<SupplierPeriod> onPeriod;

  @override
  Widget build(BuildContext context) {
    if (!data.loaded) return const Center(child: CircularProgressIndicator());
    final accounts = data.accounts..sort((a, b) => a.supplier.name.toLowerCase().compareTo(b.supplier.name.toLowerCase()));
    final a = accounts.where((x) => x.supplier.id == supplierId).firstOrNull;
    final p = a?.period(period.from, period.to);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        DropdownButtonFormField<String>(
          initialValue: a?.supplier.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Supplier'),
          items: [for (final x in accounts) DropdownMenuItem(value: x.supplier.id, child: Text(x.supplier.name))],
          onChanged: (id) {
            if (id != null) onSupplier(id);
          },
        ),
        const SizedBox(height: 10),
        PeriodBar(period: period, onChanged: onPeriod),
        const SizedBox(height: 10),
        if (a == null || p == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Choose a supplier to see its account.', textAlign: TextAlign.center, style: TextStyle(color: NaniniColors.muted)),
          )
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(a.supplier.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                      IconButton(tooltip: 'Share as CSV', icon: const Icon(Icons.ios_share), onPressed: () => _share(a, p)),
                    ],
                  ),
                  _row('Opening balance ${fmtDateDisplay(p.from)}', p.opening),
                  _row('+ Invoices', p.invoices),
                  if (p.creditNotes != 0) _row('- Credit notes', -p.creditNotes),
                  _row('- Payments', -p.payments),
                  if (p.statementCharges != 0) _row('± Per statements (charges, interest)', p.statementCharges),
                  const Divider(),
                  _row('= Amount due ${fmtDateDisplay(p.to)}', p.closing, bold: true),
                  // The supplier's latest statement in the period, checked against it.
                  if (p.lines.where((l) => l.check).lastOrNull case final st?) ...[
                    _row('Per statement ${fmtDateDisplay(st.date)}', st.doc!.amount),
                    if (st.amount.abs() >= 0.01) _row('Statement less ours on that day (to follow up)', st.amount),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Lines (oldest first)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (p.lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nothing in this period.', style: TextStyle(color: NaniniColors.muted)),
            )
          else
            Card(child: Column(children: [for (final l in p.lines) LedgerTile(line: l, data: data)])),
        ],
      ],
    );
  }

  Widget _row(String label, double v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null))),
            Text(v < 0 ? '-${fmtRCents(-v)}' : fmtRCents(v), style: TextStyle(fontWeight: bold ? FontWeight.w700 : null)),
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
