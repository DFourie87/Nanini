import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import 'sales_entry_screen.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

class SalesReportsScreen extends StatefulWidget {
  const SalesReportsScreen({super.key, required this.repo});
  final SalesRepository repo;
  @override
  State<SalesReportsScreen> createState() => _SalesReportsScreenState();
}

class _SalesReportsScreenState extends State<SalesReportsScreen> {
  String? categoryFilter;
  String? expandedId;
  final Map<String, List<SalesLineItem>> lineItemsCache = {};

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SalesReport>>(
      stream: widget.repo.watchReports(),
      builder: (context, snap) {
        final reports = (snap.data ?? []).where((r) => categoryFilter == null || r.category == categoryFilter).toList()
          ..sort((a, b) => b.reportDate.compareTo(a.reportDate));
        final sortedCategories = [...kSalesCategories]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SalesEntryScreen(repo: widget.repo),
                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text('Reports', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: categoryFilter,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All categories')),
                        ...sortedCategories.map((c) => DropdownMenuItem(value: c.key, child: Text(c.label))),
                      ],
                      onChanged: (v) => setState(() => categoryFilter = v),
                    ),
                    const SizedBox(height: 8),
                    if (reports.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No reports yet.')),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _reportCard(context, reports[i]),
                  childCount: reports.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _reportCard(BuildContext context, SalesReport r) {
    final expanded = expandedId == r.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            title: Text('${r.agent ?? 'Unknown agent'} · #${r.reportNumber}'),
            subtitle: Text('${fmtDateDisplay(r.reportDate)} · ${r.category}'),
            trailing: Text(fmtR(r.nettAmount)),
            onTap: () async {
              if (!expanded && !lineItemsCache.containsKey(r.id)) {
                final items = await widget.repo.fetchLineItems(r.id!);
                lineItemsCache[r.id!] = items;
              }
              setState(() => expandedId = expanded ? null : r.id);
            },
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('Gross', fmtR(r.grossTotal)),
                  _row('Deductions', fmtR(-r.commissionBeforeVat)),
                  _row('VAT', fmtR(-r.vat)),
                  _row('Nett', fmtR(r.nettAmount), bold: true),
                  const Divider(),
                  for (final li in lineItemsCache[r.id] ?? [])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${li.subcategory ?? ''} ${li.klass ?? ''}: ${fmtR(li.grossAmount)}'
                        '${(li.description?.isNotEmpty ?? false) ? '  (${li.description})' : ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  TextButton(
                    onPressed: () async {
                      final controller = TextEditingController(text: r.agent);
                      final newAgent = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Edit agent'),
                          content: TextField(controller: controller),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
                          ],
                        ),
                      );
                      if (newAgent != null && newAgent.isNotEmpty) {
                        await widget.repo.updateAgent(r.id!, newAgent);
                      }
                    },
                    child: const Text('Edit agent'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400))]),
      );
}
