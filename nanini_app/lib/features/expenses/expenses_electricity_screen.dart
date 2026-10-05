import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import '../suppliers/suppliers_data.dart';
import '../suppliers/suppliers_models.dart';
import '../suppliers/suppliers_period.dart';
import '../suppliers/suppliers_recon_screen.dart';

/// Each Eskom account (point of supply), bill by bill: 1. usage -- the kWh,
/// the per-kWh tariffs and the total; 2. fixed costs -- the per-day tariffs,
/// the days and the total.
class ExpensesElectricityScreen extends StatefulWidget {
  const ExpensesElectricityScreen({super.key, required this.data, required this.period, required this.onPeriod});
  final SuppliersData data;
  final SupplierPeriod period;
  final ValueChanged<SupplierPeriod> onPeriod;

  @override
  State<ExpensesElectricityScreen> createState() => _ExpensesElectricityScreenState();
}

class _ExpensesElectricityScreenState extends State<ExpensesElectricityScreen> {
  String? supplierId;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (!data.loaded) return const Center(child: CircularProgressIndicator());
    final accounts = data.accounts.where((a) => a.supplier.name.toLowerCase().startsWith('eskom')).toList()
      ..sort((a, b) => a.supplier.name.compareTo(b.supplier.name));
    if (accounts.isEmpty) {
      return const Center(child: Text('No Eskom account yet.', style: TextStyle(color: NaniniColors.muted)));
    }
    final a = accounts.firstWhere((x) => x.supplier.id == supplierId, orElse: () => accounts.first);
    final p = widget.period;
    final bills = [...a.docs, ...a.toCheck].where((d) => d.billDetails != null && d.date.compareTo(p.from) >= 0 && d.date.compareTo(p.to) <= 0).toList()
      ..sort((x, y) => y.date.compareTo(x.date));
    final kwh = bills.fold<double>(0, (t, d) => t + (d.billDetails!.kwh ?? 0));
    final usage = bills.fold<double>(0, (t, d) => t + d.billDetails!.usageTotal);
    final fixed = bills.fold<double>(0, (t, d) => t + d.billDetails!.fixedTotal);
    final adjustments = bills.fold<double>(0, (t, d) => t + d.billDetails!.adjustmentsTotal);
    final estimated = bills.where((d) => d.billDetails!.estimated).length;
    // Estimates are put right on the next bill with an actual meter reading:
    // that bill's kWh is the actual use since the last reading less what the
    // estimated bills charged.
    final all = [...a.docs, ...a.toCheck].where((d) => d.billDetails != null).toList()..sort((x, y) => x.date.compareTo(y.date));
    final corrects = <String, List<SupplierDoc>>{};
    final correctedBy = <String, SupplierDoc>{};
    var run = <SupplierDoc>[];
    for (final d in all) {
      if (d.billDetails!.estimated) {
        run.add(d);
      } else if (d.billDetails!.reading == 'actual') {
        if (run.isNotEmpty) {
          corrects[d.id] = run;
          for (final e in run) {
            correctedBy[e.id] = d;
          }
        }
        run = [];
      }
    }
    // kWh on bills Eskom worked out from an estimated reading (not a meter reading).
    final estimatedKwh = bills.where((d) => d.billDetails!.estimated).fold<double>(0, (t, d) => t + (d.billDetails!.kwh ?? 0));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // One tab per Eskom account.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: [for (final x in accounts) ButtonSegment(value: x.supplier.id, label: Text(_short(x.supplier.name)))],
            selected: {a.supplier.id},
            onSelectionChanged: (v) => setState(() => supplierId = v.first),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        PeriodBar(period: p, onChanged: widget.onPeriod),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(a.supplier.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                _row('Bills', '${bills.length}${estimated == 0 ? '' : ' ($estimated on estimated readings)'}'),
                _row('Used', '${_n(kwh)} kWh'),
                if (estimatedKwh > 0) ...[
                  _row('  on meter readings', '${_n(kwh - estimatedKwh)} kWh'),
                  _row('  estimated by Eskom', '${_n(estimatedKwh)} kWh', color: NaniniColors.amber),
                ],
                _row('1. Usage', fmtRCents(usage)),
                _row('2. Fixed costs', fmtRCents(fixed)),
                if (adjustments != 0) _row('Rebills (earlier bills corrected)', fmtRCents(adjustments)),
                const Divider(),
                _row('Charges excl. VAT', fmtRCents(usage + fixed + adjustments), bold: true),
                if (kwh > 0) _row('Usage + fixed per kWh (excl. VAT)', 'R${((usage + fixed) / kwh).toStringAsFixed(4)}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (bills.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No bills read in this period. (Bills brought in before: py scripts\\fetch_supplier_docs.py --fill-details --reread "Eskom")',
                style: TextStyle(color: NaniniColors.muted)),
          ),
        for (final d in bills) _BillCard(doc: d, data: data, corrects: corrects[d.id] ?? const [], correctedBy: correctedBy[d.id]),
      ],
    );
  }

  String _short(String name) => name.replaceFirst(RegExp(r'^eskom\s*-\s*', caseSensitive: false), '');
}

class _BillCard extends StatelessWidget {
  const _BillCard({required this.doc, required this.data, this.corrects = const [], this.correctedBy});
  final SupplierDoc doc;
  final SuppliersData data;

  /// An actual reading after estimates: the estimated bills it puts right.
  final List<SupplierDoc> corrects;

  /// An estimated bill: the bill with the actual reading that put it right (null: not yet).
  final SupplierDoc? correctedBy;

  @override
  Widget build(BuildContext context) {
    final b = doc.billDetails!;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: doc.filePath == null ? null : () => openSupplierPdf(context, data, doc),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(doc.description ?? 'Bill ${fmtDateDisplay(doc.date)}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  if (b.reading != null)
                    Text(
                        switch (b.reading) {
                          'estimate' => 'ESTIMATED reading',
                          'reconstructed' => 'RECONSTRUCTED (no Eskom bill)',
                          _ => 'Actual reading',
                        },
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: b.reading == 'actual' ? NaniniColors.green : NaniniColors.amber)),
                ],
              ),
              Text(
                [
                  'Bill ${fmtDateDisplay(doc.date)}${(doc.reference ?? '').isEmpty ? '' : ' · ${doc.reference}'}',
                  if (b.from != null && b.to != null) 'read ${fmtDateDisplay(b.from)} – ${fmtDateDisplay(b.to)}',
                ].join(' · '),
                style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              // Each bill its own formula: its kWh, tariffs and days.
              Text('1. Usage', style: Theme.of(context).textTheme.titleSmall),
              if (b.kwh != null)
                _row(b.estimated ? 'Used -- estimated by Eskom' : 'Used', '${_n(b.kwh!)} kWh', color: b.estimated ? NaniniColors.amber : null),
              if (b.estimated)
                Text(
                  correctedBy == null
                      ? 'No meter reading: Eskom estimated it from earlier use. The next actual reading puts it right.'
                      : 'No meter reading: estimated from earlier use -- put right on the bill of ${fmtDateDisplay(correctedBy!.date)} (actual reading).',
                  style: const TextStyle(color: NaniniColors.amber, fontSize: 12),
                ),
              if (corrects.isNotEmpty) ...() {
                final kwh = [...corrects, doc].fold<double>(0, (t, d) => t + (d.billDetails!.kwh ?? 0));
                final start = corrects.first.billDetails!.from, end = b.to;
                final days = start == null || end == null ? null : DateTime.parse(end).difference(DateTime.parse(start)).inDays;
                return [
                  Text(
                    'Meter read again: this bill puts right the estimate${corrects.length == 1 ? '' : 's'} of '
                    '${corrects.map((d) => fmtDateDisplay(d.date)).join(', ')} (its kWh = actual use less what they charged).',
                    style: const TextStyle(color: NaniniColors.green, fontSize: 12),
                  ),
                  _row('Actual use since the last meter reading', '${_n(kwh)} kWh${days == null || days <= 0 ? '' : ' in $days days (${_n(kwh / days)} kWh/day)'}',
                      color: NaniniColors.green),
                ];
              }(),
              // One formula per tariff period: its kWh × its tariffs.
              for (final (kwh, cs) in b.kwhGroups.where((g) => g.$2.length > 1))
                _formula('${_n(kwh)} kWh × (${cs.map((c) => _rate(c.rate, 4)).join(' + ')})', _sum(cs),
                    note: '${_rate(cs.fold<double>(0, (t, c) => t + c.rate), 4)}/kWh'),
              for (final c in b.otherUsage) _formula('${c.description}: ${_n(c.quantity ?? 0)} ${c.unit} × ${_rate(c.rate)}', c.amount),
              _row('Usage total', fmtRCents(b.usageTotal), bold: true),
              const SizedBox(height: 8),
              Text('2. Fixed costs', style: Theme.of(context).textTheme.titleSmall),
              for (final (days, cs) in b.dayGroups)
                _formula('${days.round()} days × (${cs.map((c) => _rate(c.rate, 2)).join(' + ')})', _sum(cs),
                    note: '${_rate(cs.fold<double>(0, (t, c) => t + c.rate), 2)}/day'),
              for (final c in b.otherFixed) _formula('${c.description}: ${_n(c.quantity ?? 0)} ${c.unit} × ${_rate(c.rate)}', c.amount),
              _row('Fixed total', fmtRCents(b.fixedTotal), bold: true),
              for (final c in b.adjustments) ...[
                const SizedBox(height: 8),
                _row(c.description, fmtRCents(c.amount), bold: true),
              ],
              const Divider(),
              _row('Charges excl. VAT', fmtRCents(b.usageTotal + b.fixedTotal + b.adjustmentsTotal)),
              if (doc.vatAmount != null) _row('VAT', fmtRCents(doc.vatAmount!)),
              if (doc.purchasesAmount != null) _row('This bill incl. VAT', fmtRCents(doc.purchasesAmount!), bold: true),
            ],
          ),
        ),
      ),
    );
  }
}

double _sum(List<BillCharge> cs) => cs.fold<double>(0, (t, c) => t + c.amount);

/// "1 685 kWh × (R0.6166 + R0.0041 + R2.2493) = R4 835.95".
Widget _formula(String left, double total, {String? note}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$left = '),
          TextSpan(text: fmtRCents(total), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (note != null) TextSpan(text: '  ($note)', style: const TextStyle(color: NaniniColors.muted)),
        ]),
        style: const TextStyle(fontSize: 13),
      ),
    );

Widget _row(String label, String value, {bool bold = false, bool small = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null, fontSize: small ? 12 : null, color: color))),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Text(value,
                textAlign: TextAlign.right, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null, fontSize: small ? 12 : null, color: color)),
          ),
        ],
      ),
    );

/// R0.6166 (per kWh: 4 decimals) or R24.50 (per day: 2); others as needed.
String _rate(double r, [int? decimals]) =>
    'R${r.toStringAsFixed(decimals ?? ((r * 100 - (r * 100).roundToDouble()).abs() < 1e-6 ? 2 : 4))}';

/// 14 846 (whole) or 14 845.93.
String _n(double v) {
  final whole = v == v.roundToDouble();
  final s = whole ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  final parts = s.split('.');
  final digits = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ' ');
  return parts.length > 1 ? '$digits.${parts[1]}' : digits;
}
