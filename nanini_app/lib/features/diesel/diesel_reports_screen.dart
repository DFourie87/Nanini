import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/auth/session.dart';
import '../../core/formatters.dart';
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
  Widget build(BuildContext context) {
    final isAdmin = context.watch<Session>().isAdmin;
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

                    // Per-tank and per-asset breakdowns always cover every tank/asset in
                    // the selected period -- the tank dropdown above is for the CSV export,
                    // not these comparison tables.
                    final periodUsage = usage.where((u) {
                      final d = parseDateStr(u.date);
                      if (d == null) return false;
                      return !d.isBefore(periodStart) && !d.isAfter(periodEnd);
                    }).toList();

                    final usedByTank = <String, double>{};
                    for (final u in periodUsage) {
                      usedByTank[u.tankId] = (usedByTank[u.tankId] ?? 0) + u.litres;
                    }

                    final assetStats = <String, _AssetUsage>{};
                    for (final u in periodUsage) {
                      final key = (u.equipment?.trim().isNotEmpty ?? false)
                          ? u.equipment!.trim()
                          : ((u.asset?.trim().isNotEmpty ?? false) ? u.asset!.trim() : '—');
                      final stat = assetStats.putIfAbsent(key, () => _AssetUsage());
                      stat.totalLitres += u.litres;
                      final reading = double.tryParse((u.hours ?? '').trim());
                      if (reading != null) stat.readings.add(reading);
                    }
                    final assetRows = assetStats.entries.toList()..sort((a, b) => b.value.totalLitres.compareTo(a.value.totalLitres));

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
                        _tankUsageCard(context, tanks, usedByTank),
                        const SizedBox(height: 16),
                        _assetUsageCard(context, assetRows),
                        if (isAdmin) ...[
                          const SizedBox(height: 16),
                          _sarsRebateReportCard(context, filteredPurchases, filteredUsage, tanks),
                        ],
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

  Widget _tankUsageCard(BuildContext context, List<DieselTank> tanks, Map<String, double> usedByTank) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Use per tank', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (tanks.isEmpty)
              const Text('No tanks yet.', style: TextStyle(color: NaniniColors.muted))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Tank')),
                    DataColumn(label: Text('Used'), numeric: true),
                  ],
                  rows: [
                    for (final tank in tanks)
                      DataRow(cells: [
                        DataCell(Text(tank.name)),
                        DataCell(Text(fmtL(usedByTank[tank.id] ?? 0))),
                      ]),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _assetUsageCard(BuildContext context, List<MapEntry<String, _AssetUsage>> assetRows) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Use per asset', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (assetRows.isEmpty)
              const Text('No usage in this period.', style: TextStyle(color: NaniniColors.muted))
            else ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Asset')),
                    DataColumn(label: Text('Used'), numeric: true),
                    DataColumn(label: Text('Avg L/km or hr'), numeric: true),
                  ],
                  rows: [
                    for (final entry in assetRows)
                      DataRow(cells: [
                        DataCell(Text(entry.key)),
                        DataCell(Text(fmtL(entry.value.totalLitres))),
                        DataCell(Text(entry.value.avgPerUnit == null ? '–' : entry.value.avgPerUnit!.toStringAsFixed(2))),
                      ]),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Avg = litres used ÷ km or hours covered (from the hour meter/odometer reading logged with each fill) -- blank where an asset has fewer than two readings in the period.',
                style: TextStyle(color: NaniniColors.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sarsRebateReportCard(
    BuildContext context,
    List<DieselPurchase> purchases,
    List<DieselUsage> usage,
    List<DieselTank> tanks,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SARS Diesel Rebate Report', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Admin only', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _exportCsv(context, purchases, usage, tanks),
                icon: const Icon(Icons.download),
                label: const Text('Download'),
              ),
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
    await Share.share(csv, subject: 'sars-diesel-rebate-report-${todayStr()}.csv');
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

class _AssetUsage {
  double totalLitres = 0;
  final List<double> readings = [];

  /// Litres per km/hour covered (span of logged readings); null with fewer than two readings.
  double? get avgPerUnit {
    if (readings.length < 2) return null;
    final span = readings.reduce(math.max) - readings.reduce(math.min);
    if (span <= 0) return null;
    return totalLitres / span;
  }
}
