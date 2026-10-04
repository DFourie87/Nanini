import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/widgets/dialog_error.dart';
import '../../theme/nanini_theme.dart';
import 'suppliers_data.dart';

/// What we owe suppliers and when: the total, then who to pay by which day
/// and how much (what's already due first), and who owes us (in credit).
class SuppliersDueScreen extends StatelessWidget {
  const SuppliersDueScreen({super.key, required this.data, required this.onOpen});
  final SuppliersData data;

  /// Open this supplier's page.
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (data.error != null && !data.loaded) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendlyDbError(data.error!), textAlign: TextAlign.center)));
    }
    if (!data.loaded) return const Center(child: CircularProgressIndicator());
    final today = toDateStr(DateTime.now());
    final accounts = data.accounts;
    // By when: '' = due now (overdue or due today), else the day it's due.
    final byDay = <String, List<(String id, String name, double amount)>>{};
    for (final a in accounts.where((a) => a.due > 0.005)) {
      final perDay = <String, double>{};
      for (final p in a.payable) {
        final day = p.dueDate.compareTo(today) <= 0 ? '' : p.dueDate;
        perDay[day] = (perDay[day] ?? 0) + p.amount;
      }
      perDay.forEach((day, amount) => (byDay[day] ??= []).add((a.supplier.id, a.supplier.name, amount)));
    }
    final days = byDay.keys.toList()..sort();
    final owed = accounts.where((a) => a.due > 0.005).fold<double>(0, (s, a) => s + a.due);
    final credit = accounts.where((a) => a.due < -0.005).toList()..sort((a, b) => a.due.compareTo(b.due));
    final inCredit = credit.fold<double>(0, (s, a) => s - a.due);
    // Net: what we owe less what suppliers owe us.
    final total = (((owed - inCredit) * 100).roundToDouble()) / 100;
    // As at the last day the bank statements cover (payments after it aren't known yet).
    final latestPaid = (data.payments ?? const []).map((p) => p.date).fold<String?>(null, (m, d) => m == null || d.compareTo(m) > 0 ? d : m);
    final asAt = data.bankDate ?? latestPaid;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (asAt != null)
                  Text(
                    'As at ${fmtDateDisplay(asAt)}'.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: NaniniColors.ink),
                  ),
                Row(
                  children: [
                    Expanded(child: Text('Total due to suppliers', style: Theme.of(context).textTheme.titleMedium)),
                    Text(
                      total < -0.005 ? '-${fmtRCents(-total)}' : fmtRCents(total),
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: total > 0.005 ? NaniniColors.red : (total < -0.005 ? NaniniColors.green : NaniniColors.muted)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (days.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nothing due.', textAlign: TextAlign.center, style: TextStyle(color: NaniniColors.green, fontWeight: FontWeight.w700)),
          ),
        for (final day in days) ...[
          const SizedBox(height: 12),
          _heading(
            day.isEmpty ? 'Due now' : 'By ${fmtDateDisplay(day)}',
            byDay[day]!.fold<double>(0, (s, x) => s + x.$3),
            day.isEmpty ? NaniniColors.red : NaniniColors.ink,
          ),
          Card(
            child: Column(
              children: [
                for (final (id, name, amount) in byDay[day]!..sort((a, b) => b.$3.compareTo(a.$3)))
                  ListTile(
                    dense: true,
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: Text(fmtRCents(amount), style: TextStyle(fontWeight: FontWeight.w700, color: day.isEmpty ? NaniniColors.red : NaniniColors.ink)),
                    onTap: () => onOpen(id),
                  ),
              ],
            ),
          ),
        ],
        if (credit.isNotEmpty) ...[
          const SizedBox(height: 12),
          _heading('In credit -- they owe us', credit.fold<double>(0, (s, a) => s + a.due), NaniniColors.green),
          Card(
            child: Column(
              children: [
                for (final a in credit)
                  ListTile(
                    dense: true,
                    title: Text(a.supplier.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: Text('-${fmtRCents(-a.due)}', style: const TextStyle(fontWeight: FontWeight.w700, color: NaniniColors.green)),
                    onTap: () => onOpen(a.supplier.id),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _heading(String label, double total, Color color) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 16, 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color))),
            Text(total < 0 ? '-${fmtRCents(-total)}' : fmtRCents(total), style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      );
}
