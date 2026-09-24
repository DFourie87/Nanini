import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import 'tuckshop_models.dart';
import 'tuckshop_repository.dart';

class TuckshopReportsScreen extends StatefulWidget {
  const TuckshopReportsScreen({super.key, required this.repo, required this.farmId});
  final TuckshopRepository repo;
  final String? farmId;
  @override
  State<TuckshopReportsScreen> createState() => _TuckshopReportsScreenState();
}

class _TuckshopReportsScreenState extends State<TuckshopReportsScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TuckshopPurchase>>(
      stream: widget.repo.watchPurchases(),
      builder: (context, purSnap) {
        return StreamBuilder<List<TuckshopWriteoff>>(
          stream: widget.repo.watchWriteoffs(),
          builder: (context, woSnap) {
            final monthStart = DateTime(month.year, month.month, 1);
            final monthEnd = DateTime(month.year, month.month + 1, 0);

            bool inMonth(String dateStr) {
              final d = parseDateStr(dateStr);
              return d != null && !d.isBefore(monthStart) && !d.isAfter(monthEnd);
            }

            final purchases = (purSnap.data ?? [])
                .where((p) => (p.farmId == widget.farmId || p.farmId == null) && inMonth(p.date))
                .toList();
            final writeoffs = (woSnap.data ?? []).where((w) => inMonth(w.date)).toList();

            final totalSales = purchases.fold<double>(0, (s, p) => s + p.revenue);
            final totalCogs = purchases.fold<double>(0, (s, p) => s + p.cogs);
            final profit = totalSales - totalCogs;
            final itemsSold = purchases.fold<double>(0, (s, p) => s + (p.qty ?? 0));
            final totalDeducted = purchases.where((p) => p.payslipId != null).fold<double>(0, (s, p) => s + p.revenue);
            final totalOutstanding = totalSales - totalDeducted;
            final woTotal = writeoffs.fold<double>(0, (s, w) => s + w.cogs);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: month,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDatePickerMode: DatePickerMode.year,
                    );
                    if (picked != null) setState(() => month = DateTime(picked.year, picked.month));
                  },
                  child: Text('${_monthName(month.month)} ${month.year}'),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Monthly summary', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _row('Total sales', fmtR(totalSales)),
                        _row('FIFO profit', fmtR(profit)),
                        _row('Items sold', itemsSold.toStringAsFixed(0)),
                        _row('Write-offs (cost)', fmtR(woTotal)),
                        const Divider(),
                        _row('Deducted from pay', fmtR(totalDeducted)),
                        _row('Outstanding (not yet deducted)', fmtR(totalOutstanding)),
                      ],
                    ),
                  ),
                ),
                if (writeoffs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Write-offs', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final w in writeoffs)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        title: Text('${w.qty.toStringAsFixed(0)} units — ${fmtR(w.cogs)}'),
                        subtitle: Text(w.reason ?? ''),
                      ),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );

  String _monthName(int m) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];
}
