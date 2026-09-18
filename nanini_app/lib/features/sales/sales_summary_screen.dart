import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

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

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<SalesCategory>(
              segments: kSalesCategories.map((c) => ButtonSegment(value: c, label: Text(c.label))).toList(),
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
