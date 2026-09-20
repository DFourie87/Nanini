import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import '../delivery/delivery_models.dart';
import '../delivery/delivery_repository.dart';
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
  'Yellow': Color(0xFFFBC02D),
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
  final deliveryRepo = DeliveryRepository();

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

        final isTobacco = category.key == 'tobacco';
        final grossExclVat = reports.fold<double>(0, (s, r) => s + r.grossTotal);
        final commissionExclVat = reports.fold<double>(0, (s, r) => s + r.commissionBeforeVat);
        final vatOnCommission = reports.fold<double>(0, (s, r) => s + r.vat);
        final vatOnSales = reports.fold<double>(0, (s, r) => s + (r.vatOnSales ?? 0));
        final nett = reports.fold<double>(0, (s, r) => s + r.nettAmount);

        // Tobacco's gross/deductions are stored excl. VAT with VAT tracked
        // separately (vatOnSales, vat = VAT on the deduction); folding both
        // into "Gross sales" (incl. VAT) and "Deductions" (incl. VAT) here
        // keeps Gross - Deductions = Nett exactly, so Nett can never look
        // bigger than Gross the way it did when Gross excluded VAT on sales.
        final gross = isTobacco ? grossExclVat + vatOnSales : grossExclVat;
        final deductions = isTobacco ? commissionExclVat + vatOnCommission : commissionExclVat;

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
                    _row(isTobacco ? 'Deductions (incl. VAT)' : 'Commission/deductions', fmtR(-deductions)),
                    if (!isTobacco) _row('VAT', fmtR(-vatOnCommission)),
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
                  // Nett here is excl. VAT -- gross and commission are both
                  // stored excl. VAT already, so subtracting them directly
                  // (rather than using report.nettAmount, which adds VAT on
                  // sales back in) keeps this VAT-free.
                  final nettExclVat = report != null ? report.grossTotal - report.commissionBeforeVat : 0.0;
                  final nettShare = (report != null && report.grossTotal > 0) ? li.grossAmount / report.grossTotal * nettExclVat : 0.0;
                  final key = category.key == 'potatoes'
                      ? _potatoKey(li.subcategory ?? 'Other', li.klass)
                      : (li.subcategory ?? 'Other');
                  bySubcat[key] = (bySubcat[key] ?? 0) + nettShare;
                }
                final subcatTotal = bySubcat.values.fold<double>(0, (a, b) => a + b);
                final entries = _orderedEntries(bySubcat);

                final qtyBySubcat = <String, double>{};
                final nettBySubcat = <String, double>{};
                for (final li in lineItems) {
                  if (li.qty == null || li.qty! <= 0) continue;
                  final report = reportsById[li.reportId];
                  final nettExclVat = report != null ? report.grossTotal - report.commissionBeforeVat : 0.0;
                  final nettShare = (report != null && report.grossTotal > 0) ? li.grossAmount / report.grossTotal * nettExclVat : 0.0;
                  final key = category.key == 'potatoes'
                      ? _potatoKey(li.subcategory ?? 'Other', li.klass)
                      : (li.subcategory ?? 'Other');
                  qtyBySubcat[key] = (qtyBySubcat[key] ?? 0) + li.qty!;
                  nettBySubcat[key] = (nettBySubcat[key] ?? 0) + nettShare;
                }
                final qtyEntries = _orderedEntries(qtyBySubcat);
                final unitLabel = switch (category.key) {
                  'peppers' => 'Boxes',
                  'tobacco' => 'Kg',
                  _ => 'Bags',
                };
                final unitSingular = switch (category.key) {
                  'peppers' => 'box',
                  'tobacco' => 'kg',
                  _ => 'bag',
                };

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
                          columnWidths: const {0: FlexColumnWidth(1.4), 1: FlexColumnWidth(1.7), 2: FlexColumnWidth(0.7)},
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
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
                            for (var i = 0; i < entries.length; i++)
                              TableRow(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Text(
                                      _displayLabel(entries[i].key),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: _subcatColor(i, entries[i].key), fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child:
                                        Text(fmtR(entries[i].value), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Text(
                                      subcatTotal > 0 ? '${(entries[i].value / subcatTotal * 100).toStringAsFixed(0)}%' : '0%',
                                      textAlign: TextAlign.right,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
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
                            Expanded(child: Text(_displayLabel(entries[i].key), style: const TextStyle(fontSize: 13))),
                            Text(fmtR(entries[i].value)),
                          ],
                        ),
                      ),
                    if (qtyEntries.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('$unitLabel delivered by subcategory', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Table(
                            columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.4)},
                            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                            children: [
                              TableRow(
                                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: NaniniColors.line))),
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text('Subcategory', style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Text(unitLabel,
                                        textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text('Avg nett price',
                                        textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                                  ),
                                ],
                              ),
                              for (var i = 0; i < qtyEntries.length; i++)
                                TableRow(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Text(
                                        _displayLabel(qtyEntries[i].key),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: _subcatColor(i, qtyEntries[i].key), fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Text(_fmtQty(qtyEntries[i].value),
                                          textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Text(
                                        '${fmtR((nettBySubcat[qtyEntries[i].key] ?? 0) / qtyEntries[i].value)} / $unitSingular',
                                        textAlign: TextAlign.right,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            _fieldBreakdownSection(context),
          ],
        );
      },
    );
  }

  /// Field is only collected on approved potato/butternut delivery notes
  /// (peppers and tobacco don't ask for it), so this section quietly shows
  /// nothing outside those two categories or when there's no data yet.
  Widget _fieldBreakdownSection(BuildContext context) {
    final produceType = switch (category.key) {
      'potatoes' => 'potato',
      'butternut' => 'butternut',
      _ => null,
    };
    if (produceType == null) return const SizedBox.shrink();

    return StreamBuilder<List<DeliveryNote>>(
      stream: deliveryRepo.watchNotes(),
      builder: (context, noteSnap) {
        final notes = (noteSnap.data ?? []).where((n) {
          if (n.produceType != produceType) return false;
          if ((n.field ?? '').isEmpty) return false;
          final d = parseDateStr(n.noteDate);
          return d != null && !d.isBefore(from) && !d.isAfter(to);
        }).toList();

        final byField = <String, int>{};
        for (final n in notes) {
          final bags = produceType == 'potato'
              ? kPalletSizes.fold<int>(0, (s, sz) => s + (((n.pallets[sz.key] as num?)?.toInt() ?? 0) * sz.bagsPerPallet))
              : n.total;
          byField[n.field!] = (byField[n.field!] ?? 0) + bags;
        }
        if (byField.isEmpty) return const SizedBox.shrink();

        final fieldTotal = byField.values.fold(0, (a, b) => a + b);
        final entries = byField.entries.toList()
          ..sort((a, b) {
            final ai = kFieldNames.indexOf(a.key);
            final bi = kFieldNames.indexOf(b.key);
            if (ai != bi) {
              if (ai == -1) return 1;
              if (bi == -1) return -1;
              return ai.compareTo(bi);
            }
            return a.key.compareTo(b.key);
          });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text('Bags by field', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Table(
                  columnWidths: const {0: FlexColumnWidth(1.6), 1: FlexColumnWidth(1), 2: FlexColumnWidth(0.7)},
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: NaniniColors.line))),
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Field', style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Bags', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('%', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                        ),
                      ],
                    ),
                    for (var i = 0; i < entries.length; i++)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(entries[i].key,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _subcategoryPalette[i % _subcategoryPalette.length], fontWeight: FontWeight.w600)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text('${entries[i].value}', textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              fieldTotal > 0 ? '${(entries[i].value / fieldTotal * 100).toStringAsFixed(0)}%' : '0%',
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
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
                        value: entries[i].value.toDouble(),
                        color: _subcategoryPalette[i % _subcategoryPalette.length],
                        title: fieldTotal > 0 ? '${(entries[i].value / fieldTotal * 100).toStringAsFixed(0)}%' : '0%',
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
                    Text('${entries[i].value} bags'),
                  ],
                ),
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
        final (aSize, aKlass) = _splitPotatoKey(a.key);
        final (bSize, bKlass) = _splitPotatoKey(b.key);
        final ai = category.subcats.indexOf(aSize);
        final bi = category.subcats.indexOf(bSize);
        if (ai != bi) {
          if (ai == -1) return 1;
          if (bi == -1) return -1;
          return ai.compareTo(bi);
        }
        return aKlass.compareTo(bKlass);
      });
    } else {
      entries.sort((a, b) => b.value.compareTo(a.value));
    }
    return entries;
  }

  /// Combines potato size + class into one grouping key so 1st and 2nd
  /// grade of the same size get separate pie slices instead of merging.
  String _potatoKey(String size, String? klass) => '$size||${klass ?? 'Ungraded'}';

  (String, String) _splitPotatoKey(String key) {
    final parts = key.split('||');
    return (parts[0], parts.length > 1 ? parts[1] : 'Ungraded');
  }

  String _displayLabel(String key) {
    if (category.key != 'potatoes') return key;
    final (size, klass) = _splitPotatoKey(key);
    return '$size ($klass)';
  }

  Color _subcatColor(int index, String subcat) {
    if (category.key == 'peppers' && _pepperColors.containsKey(subcat)) {
      return _pepperColors[subcat]!;
    }
    if (category.key == 'potatoes') {
      final (size, klass) = _splitPotatoKey(subcat);
      final sizeIndex = category.subcats.indexOf(size);
      final base = _subcategoryPalette[(sizeIndex == -1 ? index : sizeIndex) % _subcategoryPalette.length];
      // 2nd grade is a clearly darker shade of the same size's color, not
      // just a subtly different tint, so the two grades read apart at a glance.
      return klass == 'Class 2' ? Color.lerp(base, Colors.black, 0.4)! : base;
    }
    return _subcategoryPalette[index % _subcategoryPalette.length];
  }

  /// Whole number for boxes/bags; tobacco's kg keeps one decimal when it
  /// isn't a round number instead of rounding away fractional weight.
  String _fmtQty(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500))]),
      );
}
