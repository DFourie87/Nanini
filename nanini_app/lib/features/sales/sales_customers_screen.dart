import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import 'sales_customers_models.dart';
import 'sales_data.dart';

/// Sales > Customers: per market agent, for a tax year (March to February),
/// the nett of its account sales and what it paid, and what it owes now --
/// its account sales not yet on a payment summary (afrekeningstaat).
class SalesCustomersScreen extends StatefulWidget {
  const SalesCustomersScreen({super.key, required this.data, this.today});
  final SalesData data;

  /// For tests: the day it is.
  final DateTime? today;

  @override
  State<SalesCustomersScreen> createState() => _SalesCustomersScreenState();
}

/// The tax year a day falls in, named for the year it ends in (March 2026 - February 2027: 2027).
int taxYearOf(DateTime d) => d.month >= 3 ? d.year + 1 : d.year;

class _SalesCustomersScreenState extends State<SalesCustomersScreen> {
  late int year = taxYearOf(widget.today ?? DateTime.now());

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    // Loaded once when Sales opens (see SalesData); nothing reloads by itself.
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        if (data.customersMissing) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('The customers aren\'t set up yet: run docs/sql/customers.sql in Supabase, then tap refresh.',
                style: TextStyle(color: NaniniColors.muted)),
          );
        }
        if (data.customers == null) return const Center(child: CircularProgressIndicator());
        final from = '${year - 1}-03-01';
        final to = '$year-02-${DateTime(year, 3, 0).day}';
        final accounts = data.customerAccounts;
        final rows = [
          for (final a in accounts) (a, a.salesIn(from, to), a.paidIn(from, to)),
        ]..sort((x, y) => y.$2.$1 != x.$2.$1 ? y.$2.$1.compareTo(x.$2.$1) : y.$1.owed.compareTo(x.$1.owed));
        final sales = rows.fold<double>(0, (t, r) => t + r.$2.$1);
        final paid = rows.fold<double>(0, (t, r) => t + r.$3);
        final owed = accounts.fold<double>(0, (t, a) => t + a.owed);
        final firstYear = taxYearOf(DateTime.parse([
          for (final r in data.reports ?? const []) r.reportDate,
          '${year - 1}-03-01',
        ].reduce((a, b) => a.compareTo(b) < 0 ? a : b)));
        final lastYear = taxYearOf(widget.today ?? DateTime.now());
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<int>(
              initialValue: year,
              decoration: const InputDecoration(labelText: 'Tax year'),
              items: [
                for (var y = lastYear; y >= firstYear; y--)
                  DropdownMenuItem(value: y, child: Text('${y - 1}/${(y % 100).toString().padLeft(2, '0')} (Mar ${y - 1} - Feb $y)')),
              ],
              onChanged: (v) => setState(() => year = v ?? year),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ALL MARKET AGENTS', style: TextStyle(fontWeight: FontWeight.w700, color: NaniniColors.ink)),
                    const SizedBox(height: 4),
                    _total('Account sales (nett)', sales),
                    _total('Paid', paid),
                    const Divider(),
                    _total('Owed now', owed, bold: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final (a, (s, n), p) in rows) _AccountTile(account: a, sales: s, count: n, paid: p),
          ],
        );
      },
    );
  }
}

Widget _total(String label, double amount, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
          Text(fmtRCents(amount), style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account, required this.sales, required this.count, required this.paid});
  final CustomerAccount account;

  /// In the tax year chosen: the account sales' nett and how many, and what was paid.
  final double sales;
  final int count;
  final double paid;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final oldest = a.open.firstOrNull;
    final next = a.nextPayments.firstOrNull;
    final notes = [
      if (next != null) 'Next payment ${fmtDateDisplay(next.date)}: ${fmtRCents(next.amount)}',
      if (a.countsFrom == null && a.payments.isEmpty) 'No payment summaries yet',
      if (a.open.isNotEmpty) '${a.open.length} account sale${a.open.length == 1 ? '' : 's'} unpaid${oldest == null ? '' : ', oldest ${oldest.daysOutstanding} days'}',
      if (a.queries.isNotEmpty) '${a.queries.length} to check',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CustomerAccountScreen(account: a))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(a.customer.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              _total('Account sales${count == 0 ? '' : ' ($count)'}', sales),
              _total('Paid', paid),
              _total('Owed now', a.owed, bold: true),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(notes.join(' · '),
                    style: TextStyle(fontSize: 12, color: a.queries.isNotEmpty ? NaniniColors.amber : NaniniColors.muted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One agent: the unpaid account sales, what doesn't agree, and the payments.
class CustomerAccountScreen extends StatelessWidget {
  const CustomerAccountScreen({super.key, required this.account});
  final CustomerAccount account;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final heading = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: NaniniAppBar(title: a.customer.name),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('OWED', style: TextStyle(fontWeight: FontWeight.w700, color: NaniniColors.ink)),
                  Text(fmtRCents(a.owed), style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(
                    a.countsFrom == null
                        ? a.payments.isNotEmpty
                            ? 'Paid straight into the bank; its sales aren\'t in the app, so nothing is counted as owed.'
                            : 'No payment summaries read for this agent yet, so nothing is counted as owed.'
                        : 'The nett paid (after commission and its VAT) of each account sale from ${fmtDateDisplay(a.countsFrom)} '
                            'not yet on a payment summary'
                            '${a.customer.openingBalance != 0 ? ', plus the opening balance ${fmtRCents(a.customer.openingBalance)}' : ''}.',
                    style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
                  ),
                  if ((a.customer.accountNo ?? '').isNotEmpty || (a.customer.emails ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      [if ((a.customer.accountNo ?? '').isNotEmpty) 'Account ${a.customer.accountNo}', if ((a.customer.emails ?? '').isNotEmpty) a.customer.emails!].join(' · '),
                      style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (a.nextPayments.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Next payments', style: heading),
            const Text('Deliveries up to the 15th are paid at the end of that month, from the 16th at the end of the next. '
                'Before deductions (seedlings, bins...).', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
            const SizedBox(height: 8),
            for (final n in a.nextPayments)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  title: Text('End of ${_monthName(n.date)} (${fmtDateDisplay(n.date)})'),
                  subtitle: Text('${n.sales.length} deliver${n.sales.length == 1 ? 'y' : 'ies'}: '
                      '${fmtDateDisplay(n.sales.first.report.reportDate)} - ${fmtDateDisplay(n.sales.last.report.reportDate)}'),
                  trailing: Text(fmtRCents(n.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
          ],
          if (a.queries.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('To check', style: heading),
            const SizedBox(height: 8),
            for (final q in a.queries)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.warning_amber_rounded, color: NaniniColors.amber),
                  title: Text(q.message),
                  subtitle: Text('Payment of ${fmtDateDisplay(q.payment.date)}'),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Text('Unpaid account sales', style: heading),
          const SizedBox(height: 8),
          if (a.open.isEmpty) const Text('None.', style: TextStyle(color: NaniniColors.muted)),
          for (final s in a.open)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text('#${s.report.reportNumber} · ${s.report.category}'),
                subtitle: Text('${fmtDateDisplay(s.report.reportDate)} · ${s.daysOutstanding} days'),
                trailing: Text(fmtRCents(s.report.nettAmount), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          const SizedBox(height: 16),
          Text('Payments', style: heading),
          const SizedBox(height: 8),
          if (a.payments.isEmpty) const Text('None read yet.', style: TextStyle(color: NaniniColors.muted)),
          for (final p in a.payments)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ExpansionTile(
                title: Text('${fmtDateDisplay(p.date)}${(p.method ?? '').isEmpty ? '' : ' · ${p.method}'}'),
                subtitle: Text(
                  '${p.lines.isEmpty ? 'From the bank' : '${p.lines.length} account sale${p.lines.length == 1 ? '' : 's'}'}'
                  '${p.bankDate != null ? ' · in the bank ${fmtDateDisplay(p.bankDate)}' : _notInBank(p) ? ' · not found in the bank' : ''}',
                  style: TextStyle(color: p.bankDate == null && _notInBank(p) ? NaniniColors.amber : NaniniColors.muted),
                ),
                trailing: Text(fmtRCents(p.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  for (final l in p.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '#${l.reportNumber}'
                              '${l.sales == null ? '' : ' · sales ${fmtRCents(l.sales)}'}'
                              '${l.deductions == null ? '' : ' − ${fmtRCents(l.deductions)}'}'
                              '${l.loans == 0 ? '' : ' − loans ${fmtRCents(l.loans)}'}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(fmtRCents(l.nett), style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Paid more than 10 days ago and no deposit for it in the bank CSVs (the
/// bank import looks up to 10 days after the payment's date).
bool _notInBank(CustomerPayment p) => p.bankDate == null && DateTime.now().difference(DateTime.parse(p.date)).inDays > 10;

String _monthName(String date) {
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  final d = DateTime.parse(date);
  return '${months[d.month - 1]} ${d.year}';
}
