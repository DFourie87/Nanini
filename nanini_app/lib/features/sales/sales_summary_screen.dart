import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/formatters.dart';
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

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<SalesCategory>(
              segments: kSalesCategories
                  .map((c) => ButtonSegment(
                        value: c,
                        label: Text(c.label, textAlign: TextAlign.center, softWrap: true, maxLines: 2),
                      ))
                  .toList(),
              selected: {category},
              onSelectionChanged: (s) => setState(() => category = s.first),
              showSelectedIcon: false,
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
                  final key = li.subcategory ?? 'Other';
                  bySubcat[key] = (bySubcat[key] ?? 0) + li.grossAmount;
                }
                final subcatTotal = bySubcat.values.fold<double>(0, (a, b) => a + b);
                final entries = bySubcat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

                if (lineSnap.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
                }
                if (entries.isEmpty) {
                  return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No line items for this selection.', style: TextStyle(color: Colors.grey)));
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sales by subcategory', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Card(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Subcategory')),
                            DataColumn(label: Text('Gross'), numeric: true),
                            DataColumn(label: Text('%'), numeric: true),
                          ],
                          rows: [
                            for (final e in entries)
                              DataRow(cells: [
                                DataCell(Text(e.key)),
                                DataCell(Text(fmtR(e.value))),
                                DataCell(Text(subcatTotal > 0 ? '${(e.value / subcatTotal * 100).toStringAsFixed(0)}%' : '0%')),
                              ]),
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
                                color: _subcategoryPalette[i % _subcategoryPalette.length],
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
                            Container(width: 12, height: 12, color: _subcategoryPalette[i % _subcategoryPalette.length]),
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

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500))]),
      );
}
