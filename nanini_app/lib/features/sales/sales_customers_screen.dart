import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import 'sales_customers_models.dart';
import 'sales_data.dart';

/// Sales > Customers: what each market agent owes -- its account sales not
/// yet on a payment summary (afrekeningstaat) -- and its payments.
class SalesCustomersScreen extends StatelessWidget {
  const SalesCustomersScreen({super.key, required this.data});
  final SalesData data;

  @override
  Widget build(BuildContext context) {
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
        final accounts = data.customerAccounts;
        final total = accounts.fold<double>(0, (t, a) => t + a.owed);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('OWED BY THE MARKET AGENTS', style: TextStyle(fontWeight: FontWeight.w700, color: NaniniColors.ink)),
                    const SizedBox(height: 4),
                    Text(fmtRCents(total), style: Theme.of(context).textTheme.headlineMedium),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final a in accounts) _AccountTile(account: a),
          ],
        );
      },
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account});
  final CustomerAccount account;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final last = a.payments.firstOrNull;
    final oldest = a.open.firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(a.customer.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            if (a.countsFrom == null) 'No payment summaries yet',
            if (a.open.isNotEmpty) '${a.open.length} account sale${a.open.length == 1 ? '' : 's'} unpaid${oldest == null ? '' : ', oldest ${oldest.daysOutstanding} days'}',
            if (last != null) 'Last paid ${fmtDateDisplay(last.date)}: ${fmtRCents(last.amount)}',
            if (a.queries.isNotEmpty) '${a.queries.length} to check',
          ].join('\n'),
          style: TextStyle(color: a.queries.isNotEmpty ? NaniniColors.amber : NaniniColors.muted),
        ),
        trailing: Text(fmtRCents(a.owed), style: const TextStyle(fontWeight: FontWeight.w700)),
        isThreeLine: a.open.isNotEmpty && last != null,
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CustomerAccountScreen(account: a))),
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
                        ? 'No payment summaries read for this agent yet, so nothing is counted as owed.'
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
                  '${p.lines.length} account sale${p.lines.length == 1 ? '' : 's'}'
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
