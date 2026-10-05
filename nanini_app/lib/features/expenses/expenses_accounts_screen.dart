import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import '../suppliers/suppliers_data.dart';
import '../suppliers/suppliers_models.dart';
import '../suppliers/suppliers_period.dart';
import 'expenses_models.dart';
import 'expenses_purchases_screen.dart';

/// All purchases for the period, from every supplier, against their contra
/// account (the expense): [from]..[to].
List<PurchaseLine> expenseLines(SuppliersData data, String from, String to) =>
    purchasesFor(data.accounts, data.docLines, data.glRules, from, to, chart: data.glAccounts);

/// Expenses: each contra account's total for the period, its share and the
/// same period a year earlier. Tap one for its detail.
class ExpensesAccountsScreen extends StatelessWidget {
  const ExpensesAccountsScreen({super.key, required this.data, required this.period, required this.onPeriod});
  final SuppliersData data;
  final SupplierPeriod period;
  final ValueChanged<SupplierPeriod> onPeriod;

  @override
  Widget build(BuildContext context) {
    if (!data.loaded) return const Center(child: CircularProgressIndicator());
    final lines = expenseLines(data, period.from, period.to);
    final accounts = ExpenseTotals.byAccount(lines, period.from, period.to);
    final lastYear = ExpenseTotals.byAccount(expenseLines(data, yearEarlier(period.from), yearEarlier(period.to)), period.from, period.to);
    final lastYearOf = {for (final t in lastYear) t.account: t.excl};
    final total = accounts.fold<double>(0, (t, a) => t + a.excl);
    final totalLastYear = lastYear.fold<double>(0, (t, a) => t + a.excl);
    final biggest = accounts.where((a) => a.account != null).fold<double>(0, (m, a) => a.excl > m ? a.excl : m);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        PeriodBar(period: period, onChanged: onPeriod),
        if (data.purchasesMissing)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('Run docs/sql/suppliers_purchases.sql in Supabase to keep invoice lines and contra accounts.',
                  style: TextStyle(color: NaniniColors.red)),
            ),
          ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TOTAL EXPENSES (EXCL. VAT)', style: TextStyle(color: NaniniColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(fmtR(total), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('${accounts.where((a) => a.account != null).length} accounts · ${lines.length} lines',
                    style: const TextStyle(color: NaniniColors.muted, fontSize: 13)),
                _Change(now: total, before: totalLastYear),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Per expense', style: Theme.of(context).textTheme.titleMedium),
        const Text('Tap one for its months, suppliers and lines.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
        const SizedBox(height: 6),
        if (accounts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No purchases in this period.', style: TextStyle(color: NaniniColors.muted)),
          ),
        for (final a in accounts)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ExpenseAccountScreen(data: data, account: a.account, period: period))),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text('${data.accountLabel(a.account)} ›',
                            style: TextStyle(fontWeight: FontWeight.w700, color: a.account == null ? NaniniColors.amber : NaniniColors.ink)),
                      ),
                      Text(fmtR(a.excl), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 6),
                    if (a.account != null && biggest > 0) _Bar(fraction: a.excl / biggest),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(
                        child: Text(
                            '${total > 0 ? (a.excl / total * 100).toStringAsFixed(1) : '0'}% · ${a.lines.length} lines · '
                            '${a.bySupplier.length} supplier${a.bySupplier.length == 1 ? '' : 's'}',
                            style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                      ),
                      _Change(now: a.excl, before: lastYearOf[a.account] ?? 0, small: true),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        const Text('Excl. VAT. The change is against the same dates a year earlier.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
      ],
    );
  }
}

/// One expense (contra account): its totals, month by month against a year
/// earlier, per supplier, and every line (tap to put it against another
/// account; hold to open the document).
class ExpenseAccountScreen extends StatefulWidget {
  const ExpenseAccountScreen({super.key, required this.data, required this.account, required this.period});
  final SuppliersData data;
  final String? account;
  final SupplierPeriod period;

  @override
  State<ExpenseAccountScreen> createState() => _ExpenseAccountScreenState();
}

class _ExpenseAccountScreenState extends State<ExpenseAccountScreen> {
  late SupplierPeriod period = widget.period;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return Scaffold(
      appBar: NaniniAppBar(title: data.accountLabel(widget.account)),
      body: ListenableBuilder(
        listenable: data,
        builder: (context, _) {
          final all = expenseLines(data, period.from, period.to);
          final allExcl = all.fold<double>(0, (t, l) => t + l.excl);
          final t = ExpenseTotals(widget.account, all.where((l) => l.account == widget.account).toList(), period.from, period.to);
          final ly = ExpenseTotals(
              widget.account,
              expenseLines(data, yearEarlier(period.from), yearEarlier(period.to)).where((l) => l.account == widget.account).toList(),
              yearEarlier(period.from),
              yearEarlier(period.to));
          final lyByMonth = ly.byMonth.values.toList();
          final months = t.byMonth.keys.toList();
          final top = [...t.byMonth.values, ...lyByMonth].fold<double>(0, (m, v) => v > m ? v : m);
          const head = TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              PeriodBar(period: period, onChanged: (p) => setState(() => period = p)),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _kv('Excl. VAT', fmtRCents(t.excl), bold: true),
                      _kv('VAT', fmtRCents(t.vat)),
                      _kv('Incl. VAT', fmtRCents(t.incl)),
                      const Divider(),
                      _kv('Average a month', fmtR(t.perMonth)),
                      _kv('Share of all expenses', allExcl > 0 ? '${(t.excl / allExcl * 100).toStringAsFixed(1)}%' : '-'),
                      _kv('Lines · suppliers', '${t.lines.length} · ${t.bySupplier.length}'),
                      _kv('Same dates a year earlier', fmtR(ly.excl)),
                      Align(alignment: Alignment.centerRight, child: _Change(now: t.excl, before: ly.excl)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Per month', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      const Row(children: [
                        SizedBox(width: 64, child: Text('Month', style: head)),
                        Expanded(child: SizedBox()),
                        SizedBox(width: 90, child: Text('This year', textAlign: TextAlign.right, style: head)),
                        SizedBox(width: 90, child: Text('Year before', textAlign: TextAlign.right, style: head)),
                      ]),
                      const Divider(height: 12),
                      for (var i = 0; i < months.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            SizedBox(width: 64, child: Text(_monthLabel(months[i]), style: const TextStyle(fontSize: 13))),
                            Expanded(child: _Bar(fraction: top > 0 ? t.byMonth[months[i]]! / top : 0)),
                            SizedBox(
                              width: 90,
                              child: Text(t.byMonth[months[i]]! == 0 ? '-' : fmtR(t.byMonth[months[i]]),
                                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                            SizedBox(
                              width: 90,
                              child: Text(i < lyByMonth.length && lyByMonth[i] != 0 ? fmtR(lyByMonth[i]) : '-',
                                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: NaniniColors.muted)),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ),
              ),
              if (t.bySupplier.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Per supplier', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        for (final s in t.suppliers)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Expanded(child: Text(s, style: const TextStyle(fontWeight: FontWeight.w600))),
                              Text('${t.bySupplier[s]!.$2} lines  ', style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                              SizedBox(width: 90, child: Text(fmtR(t.bySupplier[s]!.$1), textAlign: TextAlign.right)),
                              SizedBox(
                                width: 50,
                                child: Text(t.excl != 0 ? '${(t.bySupplier[s]!.$1 / t.excl * 100).round()}%' : '-',
                                    textAlign: TextAlign.right, style: const TextStyle(color: NaniniColors.muted)),
                              ),
                            ]),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text('Lines (${t.lines.length})', style: Theme.of(context).textTheme.titleMedium),
              const Text('Newest first. Tap a line to put it against another contra account; hold it to open the document.',
                  style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
              const SizedBox(height: 4),
              for (final l in t.lines) PurchaseTile(line: l, data: data, all: all),
            ],
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k)),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ]),
      );

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _monthLabel(String ym) => '${_months[int.parse(ym.substring(5, 7)) - 1]} ${ym.substring(2, 4)}';
}

/// A share as a bar in the brand colour.
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: fraction.clamp(0, 1).toDouble(),
          minHeight: 8,
          backgroundColor: NaniniColors.line,
          color: NaniniColors.rust,
        ),
      );
}

/// Up or down against a year earlier: more spent in red, less in green.
class _Change extends StatelessWidget {
  const _Change({required this.now, required this.before, this.small = false});
  final double now;
  final double before;
  final bool small;

  @override
  Widget build(BuildContext context) {
    if (before <= 0) {
      return small ? const SizedBox.shrink() : const Text('Nothing the year before', style: TextStyle(color: NaniniColors.muted, fontSize: 12));
    }
    final pct = (now - before) / before * 100;
    final up = pct >= 0;
    return Text(
      small ? '${up ? '▲' : '▼'} ${pct.abs().toStringAsFixed(0)}%' : '${up ? '▲' : '▼'} ${pct.abs().toStringAsFixed(1)}% on a year earlier (${fmtR(before)})',
      style: TextStyle(color: up ? NaniniColors.red : NaniniColors.green, fontSize: 12, fontWeight: FontWeight.w600),
    );
  }
}
