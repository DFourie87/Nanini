import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/formatters.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'diesel_models.dart';
import 'diesel_repository.dart';

class DieselReportsScreen extends StatefulWidget {
  const DieselReportsScreen({super.key, required this.repo});
  final DieselRepository repo;
  @override
  State<DieselReportsScreen> createState() => _DieselReportsScreenState();
}

class _DieselReportsScreenState extends State<DieselReportsScreen> {
  DateTime periodStart = _defaultPeriodStart();
  DateTime periodEnd = _defaultPeriodEnd();
  String? tankFilter;
  double refundRate = 0;

  static DateTime _defaultPeriodEnd() {
    final now = DateTime.now();
    final endMonth = ((now.month + 1) ~/ 2) * 2;
    return DateTime(now.year, endMonth + 1, 0);
  }

  static DateTime _defaultPeriodStart() {
    final end = _defaultPeriodEnd();
    final startMonth = end.month - 1;
    return DateTime(end.year, startMonth, 1);
  }

  @override
  void initState() {
    super.initState();
    widget.repo.fetchRefundRate().then((r) => setState(() => refundRate = r));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DieselPriceForecast?>(
      stream: widget.repo.watchDieselPriceForecast(),
      builder: (context, forecastSnap) {
        final forecast = forecastSnap.data;
        return StreamBuilder<List<DieselTank>>(
          stream: widget.repo.watchTanks(),
          builder: (context, tankSnap) {
            final tanks = tankSnap.data ?? [];
            return StreamBuilder<List<DieselPurchase>>(
              stream: widget.repo.watchPurchases(),
              builder: (context, purSnap) {
                final purchases = purSnap.data ?? [];
                return StreamBuilder<List<DieselUsage>>(
                  stream: widget.repo.watchUsage(),
                  builder: (context, useSnap) {
                    final usage = useSnap.data ?? [];

                    final filteredPurchases = purchases.where((p) {
                      final d = parseDateStr(p.date);
                      if (d == null) return false;
                      if (tankFilter != null && p.tankId != tankFilter) return false;
                      return !d.isBefore(periodStart) && !d.isAfter(periodEnd);
                    }).toList();
                    final filteredUsage = usage.where((u) {
                      final d = parseDateStr(u.date);
                      if (d == null) return false;
                      if (tankFilter != null && u.tankId != tankFilter) return false;
                      return !d.isBefore(periodStart) && !d.isAfter(periodEnd);
                    }).toList();

                    final totalIn = filteredPurchases.fold<double>(0, (s, p) => s + p.litres);
                    final totalOut = filteredUsage.fold<double>(0, (s, u) => s + u.litres);
                    final eligibleOut = filteredUsage.where((u) => u.eligible).fold<double>(0, (s, u) => s + u.litres);
                    final eligiblePct = totalOut > 0 ? eligibleOut / totalOut * 100 : 0.0;
                    final estimatedRefund = eligibleOut * refundRate;

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (forecast != null) ...[
                          _forecastCard(context, forecast),
                          const SizedBox(height: 16),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  final picked = await showDateRangePicker(
                                    context: context,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                    initialDateRange: DateTimeRange(start: periodStart, end: periodEnd),
                                  );
                                  if (picked != null) setState(() { periodStart = picked.start; periodEnd = picked.end; });
                                },
                                child: Text('${fmtDateDisplay(toDateStr(periodStart))} – ${fmtDateDisplay(toDateStr(periodEnd))}'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            DropdownButton<String?>(
                              value: tankFilter,
                              hint: const Text('All tanks'),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('All tanks')),
                                ...tanks.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
                              ],
                              onChanged: (v) => setState(() => tankFilter = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('VAT period summary', style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 12),
                                _statRow('Total purchased', fmtL(totalIn)),
                                _statRow('Total used', fmtL(totalOut)),
                                _statRow('Eligible used', fmtL(eligibleOut)),
                                _statRow('Eligible %', '${eligiblePct.toStringAsFixed(1)}%'),
                                const Divider(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Refund rate (R/L)'),
                                    SizedBox(
                                      width: 100,
                                      child: TextFormField(
                                        initialValue: refundRate.toString(),
                                        textAlign: TextAlign.right,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(isDense: true),
                                        onFieldSubmitted: (v) async {
                                          final rate = double.tryParse(v) ?? 0;
                                          setState(() => refundRate = rate);
                                          await widget.repo.setRefundRate(rate);
                                          if (context.mounted) showToast(context, 'Refund rate saved');
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(),
                                _statRow('Estimated refund', fmtR(estimatedRefund), emphasize: true),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _exportCsv(context, filteredPurchases, filteredUsage, tanks),
                          icon: const Icon(Icons.download),
                          label: const Text('Export CSV for SARS review'),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _forecastCard(BuildContext context, DieselPriceForecast forecast) {
    final isIncrease = forecast.expectedChangeRand >= 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Diesel price forecast', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _statRow('Next price adjustment', fmtDateDisplay(forecast.nextAdjustmentDate)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isIncrease ? 'Expected increase' : 'Expected decrease'),
                  Row(
                    children: [
                      Icon(
                        isIncrease ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 16,
                        color: isIncrease ? NaniniColors.rust : NaniniColors.green,
                      ),
                      const SizedBox(width: 4),
                      Text(fmtR(forecast.expectedChangeRand.abs()), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Diesel 0.05% sulphur · from the CEF bulletin dated ${fmtDateDisplay(forecast.bulletinDate)}',
              style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context, List<DieselPurchase> purchases, List<DieselUsage> usage, List<DieselTank> tanks) async {
    final tankName = {for (final t in tanks) t.id: t.name};
    final rows = <List<dynamic>>[
      ['Date', 'Type', 'Tank', 'Litres', 'Equipment/Supplier', 'Activity/Notes', 'Eligible'],
      for (final p in purchases) [p.date, 'Purchase', tankName[p.tankId] ?? '', p.litres, p.supplier ?? '', p.notes ?? '', ''],
      for (final u in usage) [u.date, 'Usage', tankName[u.tankId] ?? '', u.litres, u.equipment ?? '', u.activity ?? '', u.eligible ? 'Yes' : 'No'],
    ];
    final csv = const ListToCsvConverter().convert(rows);
    await Share.share(csv, subject: 'diesel-logbook-${todayStr()}.csv');
  }

  Widget _statRow(String label, String value, {bool emphasize = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: TextStyle(fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      );
}
