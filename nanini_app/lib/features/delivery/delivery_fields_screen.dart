import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/formatters.dart';
import 'delivery_models.dart';
import 'delivery_repository.dart';

class DeliveryFieldsScreen extends StatefulWidget {
  const DeliveryFieldsScreen({super.key, required this.repo});
  final DeliveryRepository repo;
  @override
  State<DeliveryFieldsScreen> createState() => _DeliveryFieldsScreenState();
}

class _DeliveryFieldsScreenState extends State<DeliveryFieldsScreen> {
  String? fieldFilter;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DeliveryNote>>(
      stream: widget.repo.watchNotes(),
      builder: (context, snap) {
        final notes = (snap.data ?? []).where((n) => n.produceType == 'potato' && (fieldFilter == null || n.field == fieldFilter)).toList();

        final bagsBySize = <String, int>{};
        for (final n in notes) {
          for (final s in kPalletSizes) {
            final count = (n.pallets[s.key] as num?)?.toInt() ?? 0;
            bagsBySize[s.key] = (bagsBySize[s.key] ?? 0) + count * s.bagsPerPallet;
          }
        }
        final totalBags = bagsBySize.values.fold(0, (a, b) => a + b);

        final byDate = <String, int>{};
        for (final n in notes) {
          byDate[n.noteDate] = (byDate[n.noteDate] ?? 0) + n.total;
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String?>(
              initialValue: fieldFilter,
              decoration: const InputDecoration(labelText: 'Field'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All fields')),
                ...kFieldNames.map((f) => DropdownMenuItem(value: f, child: Text(f))),
              ],
              onChanged: (v) => setState(() => fieldFilter = v),
            ),
            const SizedBox(height: 20),
            if (totalBags > 0) ...[
              SizedBox(
                height: 200,
                child: PieChart(
                  PieChartData(
                    sections: [
                      for (final s in kPalletSizes)
                        if ((bagsBySize[s.key] ?? 0) > 0)
                          PieChartSectionData(
                            value: (bagsBySize[s.key] ?? 0).toDouble(),
                            color: Color(s.color),
                            title: '${(((bagsBySize[s.key] ?? 0) / totalBags) * 100).toStringAsFixed(0)}%',
                            radius: 70,
                            titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final s in kPalletSizes)
                if ((bagsBySize[s.key] ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(width: 12, height: 12, color: Color(s.color)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s.label, style: const TextStyle(fontSize: 13))),
                        Text('${bagsBySize[s.key]} bags'),
                      ],
                    ),
                  ),
            ] else
              const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('No potato deliveries for this field yet.'))),
            const SizedBox(height: 24),
            Text('Delivered by date', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final entry in byDate.entries)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(title: Text(fmtDateDisplay(entry.key)), trailing: Text('${entry.value} pallets')),
              ),
          ],
        );
      },
    );
  }
}
