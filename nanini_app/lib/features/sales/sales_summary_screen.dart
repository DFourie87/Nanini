import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

const _subcategoryPalette = [
  Color(0xFFEC1F24),
  Color(0xFFC41A1E),
  Color(0xFF2E7D32),
  Color(0xFFE07B00),
  Color(0xFF5B8FB9),
  Color(0xFF8E44AD),
  Color(0xFF16A085),
  Color(0xFFE67E22),
  Color(0xFF34495E),
  Color(0xFFB71C7B),
];

// Matches the pepper colors used when logging boxes in the packaging module.
const _pepperColors = {
  'Red': NaniniColors.red,
  'Yellow': Color(0xFFF9A825),
  'Green': NaniniColors.green,
};

class SalesSummaryScreen extends StatefulWidget {
  const SalesSummaryScreen({super.key, required this.repo});
  final SalesRepository repo;
  @override
  State<SalesSummaryScreen> createState() => _SalesSummaryScreenState();
}

class _SalesSummaryScreenState extends State<SalesSummaryScreen> {
  SalesCategory category = kSalesCategories.first;
  DateTime from = DateTime(DateTime.now().year, 1, 1);
  DateTime to = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SalesReport>>(
      stream: widget.repo.watchReports(),
      builder: (context, snap) {
        final reports = (snap.data ?? []).where((r) {
          if (r.category != category.key) return false;
          final d = parseDateStr(r.reportDate);
          return d != null && !d.isBefore(from) && !d.isAfter(to);
        }).toList();

        final gross = reports.fold<double>(0, (s, r) => s + r.grossTotal);
        final commission = reports.fold<double>(0, (s, r) => s + r.commissionBeforeVat);
        final nett = reports.fold<double>(0, (s, r) => s + r.nettAmount);
        final vat = category.key == 'tobacco'
            ? reports.fold<double>(0, (s, r) => s + (r.vatOnSales ?? 0)) - reports.fold<double>(0, (s, r) => s + r.vat)
            : reports.fold<double>(0, (s, r) => s + r.vat);

        final reportIds = reports.map((r) => r.id).whereType<String>().toList();
        final reportsById = {for (final r in reports) if (r.id != null) r.id!: r};

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<SalesCategory>(
              segments: kSalesCategories
                  .map((c) => ButtonSegment(
                        value: c,
                        label: Text(c.label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              selected: {category},
              onSelectionChanged: (s) => setState(() => category = s.first),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: NaniniColors.rust,
                selectedForegroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(context: context, initialDate: from, firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (picked != null) setState(() => from = picked);
                    },
                    child: Text('From ${fmtDateDisplay(toDateStr(from))}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(context: context, initialDate: to, firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (picked != null) setState(() => to = picked);
                    },
                    child: Text('To ${fmtDateDisplay(toDateStr(to))}'),
                  ),
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
                    _row('Gross sales', fmtR(gross)),
                    _row('Commission/deductions', fmtR(commission)),
                    _row('VAT', fmtR(vat)),
                    const Divider(),
                    _row('Nett', fmtR(nett), bold: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Reports: ${reports.length}', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            FutureBuilder<List<SalesLineItem>>(
              future: widget.repo.fetchLineItemsForReports(reportIds),
              builder: (context, lineSnap) {
                final lineItems = lineSnap.data ?? [];
                final bySubcat = <String, double>{};
                for (final li in lineItems) {
                  final report = reportsById[li.reportId];
                  final nettShare = (report != null && report.grossTotal > 0)
                      ? li.grossAmount / report.grossTotal * report.nettAmount
                      : 0.0;
                  final key = li.subcategory ?? 'Other';
                  bySubcat[key] = (bySubcat[key] ?? 0) + nettShare;
                }
                final subcatTotal = bySubcat.values.fold<double>(0, (a, b) => a + b);
                final entries = _orderedEntries(bySubcat);

                if (lineSnap.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
                }
                if (entries.isEmpty) {
                  return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No line items for this selection.', style: TextStyle(color: Colors.grey)));
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nett sales by subcategory', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Table(
                          columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
                          children: [
                            const TableRow(
                              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: NaniniColors.line))),
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('Subcategory', style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('Nett',
                                      textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('%', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                                ),
                              ],
                            ),
                            for (final e in entries)
                              TableRow(
                                children: [
                                  Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(e.key)),
                                  Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(fmtR(e.value), textAlign: TextAlign.right)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Text(subcatTotal > 0 ? '${(e.value / subcatTotal * 100).toStringAsFixed(0)}%' : '0%', textAlign: TextAlign.right),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 200,
                      child: PieChart(
                        PieChartData(
                          sections: [
                            for (var i = 0; i < entries.length; i++)
                              PieChartSectionData(
                                value: entries[i].value,
                                color: _subcatColor(i, entries[i].key),
                                title: subcatTotal > 0 ? '${(entries[i].value / subcatTotal * 100).toStringAsFixed(0)}%' : '0%',
                                radius: 70,
                                titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < entries.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Container(width: 12, height: 12, color: _subcatColor(i, entries[i].key)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(entries[i].key, style: const TextStyle(fontSize: 13))),
                            Text(fmtR(entries[i].value)),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// Peppers and tobacco list alphabetically; potatoes follow the same
  /// size order as the packaging module's pallet log; everything else
  /// (e.g. butternut) stays sorted by nett sales, highest first.
  List<MapEntry<String, double>> _orderedEntries(Map<String, double> bySubcat) {
    final entries = bySubcat.entries.toList();
    if (category.key == 'peppers' || category.key == 'tobacco') {
      entries.sort((a, b) => a.key.compareTo(b.key));
    } else if (category.key == 'potatoes') {
      entries.sort((a, b) {
        final ai = category.subcats.indexOf(a.key);
        final bi = category.subcats.indexOf(b.key);
        if (ai == -1 && bi == -1) return a.key.compareTo(b.key);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });
    } else {
      entries.sort((a, b) => b.value.compareTo(a.value));
    }
    return entries;
  }

  Color _subcatColor(int index, String subcat) {
    if (category.key == 'peppers' && _pepperColors.containsKey(subcat)) {
      return _pepperColors[subcat]!;
    }
    return _subcategoryPalette[index % _subcategoryPalette.length];
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500))]),
      );
}
