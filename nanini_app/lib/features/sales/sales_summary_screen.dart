import 'package:flutter/foundation.dart' show listEquals;
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
  String? classFilter;
  final deliveryRepo = DeliveryRepository();

  // Created once and reused for the widget's lifetime -- building these
  // inline in `build()` would open a brand-new Supabase realtime
  // subscription (and lose all cached data) on every setState, which is
  // why switching produce tabs used to flash back to a loading state and
  // feel slow. Same reasoning for `_notesStream` below.
  late final Stream<List<SalesReport>> _reportsStream = widget.repo.watchReports();
  late final Stream<List<DeliveryNote>> _notesStream = deliveryRepo.watchNotes();

  List<String>? _cachedReportIds;
  Future<List<SalesLineItem>>? _cachedLineItemsFuture;

  /// Only re-fetches when the report id set actually changed (e.g. a
  /// different category or date range) -- keeps unrelated rebuilds, like
  /// toggling the class filter, from re-hitting the network for data
  /// that's already loaded.
  Future<List<SalesLineItem>> _lineItemsFuture(List<String> reportIds) {
    if (_cachedReportIds == null || !listEquals(_cachedReportIds, reportIds)) {
      _cachedReportIds = reportIds;
      _cachedLineItemsFuture = widget.repo.fetchLineItemsForReports(reportIds);
    }
    return _cachedLineItemsFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SalesReport>>(
      stream: _reportsStream,
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
              onSelectionChanged: (s) => setState(() { category = s.first; classFilter = null; }),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: NaniniColors.rust,
                selectedForegroundColor: Colors.white,
              ),
            ),
            if (category.hasClass) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: classFilter,
                decoration: InputDecoration(labelText: category.classLabel),
                items: [
                  DropdownMenuItem(value: null, child: Text('All ${category.classLabel!.toLowerCase()}s')),
                  ...category.classOptions!.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                ],
                onChanged: (v) => setState(() => classFilter = v),
              ),
            ],
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
              future: _lineItemsFuture(reportIds),
              builder: (context, lineSnap) {
                final lineItems = (lineSnap.data ?? []).where((li) => classFilter == null || li.klass == classFilter).toList();
                final bySubcat = <String, double>{};
                for (final li in lineItems) {
                  final report = reportsById[li.reportId];
                  // Nett here is excl. VAT -- gross and commission are both
                  // stored excl. VAT already, so subtracting them directly
                  // (rather than using report.nettAmount, which adds VAT on
                  // sales back in) keeps this VAT-free.
                  final nettExclVat = report != null ? report.grossTotal - report.commissionBeforeVat : 0.0;
                  final nettShare = (report != null && report.grossTotal > 0) ? li.grossAmount / report.grossTotal * nettExclVat : 0.0;
                  final key = category.hasClass
                      ? _combinedKey(li.subcategory ?? 'Other', li.klass)
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
                  final key = category.hasClass
                      ? _combinedKey(li.subcategory ?? 'Other', li.klass)
                      : (li.subcategory ?? 'Other');
                  qtyBySubcat[key] = (qtyBySubcat[key] ?? 0) + li.qty!;
                  nettBySubcat[key] = (nettBySubcat[key] ?? 0) + nettShare;
                }
                final qtyEntries = _orderedEntries(qtyBySubcat);
                final qtyTotal = qtyBySubcat.values.fold<double>(0, (a, b) => a + b);
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

                // Peppers get a Qty column on this table too, on top of the
                // existing Nett/% -- the other categories keep this table
                // exactly as it was.
                final showQtyHere = category.key == 'peppers';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nett sales by subcategory', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Table(
                          columnWidths: {
                            0: const FlexColumnWidth(1.3),
                            1: const FlexColumnWidth(1.4),
                            2: const FlexColumnWidth(0.6),
                            if (showQtyHere) 3: const FlexColumnWidth(0.9),
                          },
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                          children: [
                            TableRow(
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: NaniniColors.line))),
                              children: [
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('Subcategory', style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('Nett',
                                      textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('%', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                                ),
                                if (showQtyHere)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text('Boxes', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
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
                                  if (showQtyHere)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Text(
                                        _fmtQty(qtyBySubcat[entries[i].key] ?? 0),
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
                            columnWidths: const {0: FlexColumnWidth(1.8), 1: FlexColumnWidth(0.9), 2: FlexColumnWidth(0.6), 3: FlexColumnWidth(1.3)},
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
                                    child: Text('%', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
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
                                        qtyTotal > 0 ? '${(qtyEntries[i].value / qtyTotal * 100).toStringAsFixed(0)}%' : '0%',
                                        textAlign: TextAlign.right,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
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
            _fieldBreakdownSection(context, reports),
          ],
        );
      },
    );
  }

  /// Field is only collected on approved potato/butternut delivery notes
  /// (peppers and tobacco don't ask for it), so this section quietly shows
  /// nothing outside those two categories or when there's no data yet.
  Widget _fieldBreakdownSection(BuildContext context, List<SalesReport> reports) {
    final produceType = switch (category.key) {
      'potatoes' => 'potato',
      'butternut' => 'butternut',
      _ => null,
    };
    if (produceType == null) return const SizedBox.shrink();

    // Exact, not estimated -- field is picked directly on the sales report
    // at entry time (potato/butternut only), so this sums real sales, not
    // an allocation from delivery bag counts the way "Bags by field" is.
    final salesByField = <String, double>{};
    for (final r in reports) {
      if ((r.field ?? '').isEmpty) continue;
      salesByField[r.field!] = (salesByField[r.field!] ?? 0) + r.nettAmount;
    }

    return StreamBuilder<List<DeliveryNote>>(
      stream: _notesStream,
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
        if (byField.isEmpty && salesByField.isEmpty) return const SizedBox.shrink();

        int fieldOrder(String a, String b) {
          final ai = kFieldNames.indexOf(a);
          final bi = kFieldNames.indexOf(b);
          if (ai != bi) {
            if (ai == -1) return 1;
            if (bi == -1) return -1;
            return ai.compareTo(bi);
          }
          return a.compareTo(b);
        }

        final fieldTotal = byField.values.fold(0, (a, b) => a + b);
        final entries = byField.entries.toList()..sort((a, b) => fieldOrder(a.key, b.key));
        final salesFieldTotal = salesByField.values.fold<double>(0, (a, b) => a + b);
        final salesEntries = salesByField.entries.toList()..sort((a, b) => fieldOrder(a.key, b.key));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entries.isNotEmpty) ...[
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
            if (salesEntries.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Total nett sales by field', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Table(
                    columnWidths: const {0: FlexColumnWidth(1.6), 1: FlexColumnWidth(1.3), 2: FlexColumnWidth(0.7)},
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
                            child: Text('Nett', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('%', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                          ),
                        ],
                      ),
                      for (var i = 0; i < salesEntries.length; i++)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(salesEntries[i].key,
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _subcategoryPalette[i % _subcategoryPalette.length], fontWeight: FontWeight.w600)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(fmtR(salesEntries[i].value), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                salesFieldTotal > 0 ? '${(salesEntries[i].value / salesFieldTotal * 100).toStringAsFixed(0)}%' : '0%',
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
    );
  }

  /// Categories with a second dimension (potato Class, pepper Weight)
  /// follow the same subcategory order as the packaging module, then by
  /// that second dimension; tobacco lists alphabetically; everything else
  /// (e.g. butternut) stays sorted by nett sales, highest first.
  List<MapEntry<String, double>> _orderedEntries(Map<String, double> bySubcat) {
    final entries = bySubcat.entries.toList();
    if (category.hasClass) {
      entries.sort((a, b) {
        final (aMain, aSub) = _splitCombinedKey(a.key);
        final (bMain, bSub) = _splitCombinedKey(b.key);
        final ai = category.subcats.indexOf(aMain);
        final bi = category.subcats.indexOf(bMain);
        if (ai != bi) {
          if (ai == -1) return 1;
          if (bi == -1) return -1;
          return ai.compareTo(bi);
        }
        return aSub.compareTo(bSub);
      });
    } else if (category.key == 'tobacco') {
      entries.sort((a, b) => a.key.compareTo(b.key));
    } else {
      entries.sort((a, b) => b.value.compareTo(a.value));
    }
    return entries;
  }

  /// Combines subcategory + class/weight into one grouping key so e.g.
  /// potato 1st/2nd grade or pepper 4kg/5kg of the same subcategory get
  /// separate pie slices instead of merging.
  String _combinedKey(String main, String? sub) => '$main||${sub ?? 'Ungraded'}';

  (String, String) _splitCombinedKey(String key) {
    final parts = key.split('||');
    return (parts[0], parts.length > 1 ? parts[1] : 'Ungraded');
  }

  String _displayLabel(String key) {
    if (!category.hasClass) return key;
    final (main, sub) = _splitCombinedKey(key);
    return '$main ($sub)';
  }

  Color _subcatColor(int index, String subcat) {
    if (category.hasClass) {
      final (main, sub) = _splitCombinedKey(subcat);
      final Color base;
      if (category.key == 'peppers' && _pepperColors.containsKey(main)) {
        base = _pepperColors[main]!;
      } else {
        final mainIndex = category.subcats.indexOf(main);
        base = _subcategoryPalette[(mainIndex == -1 ? index : mainIndex) % _subcategoryPalette.length];
      }
      // The second class/weight option (e.g. potato Class 2, pepper 4kg)
      // renders as a clearly darker shade of the same base color, not just
      // a subtly different tint, so the two read apart at a glance.
      final isSecondary = (category.classOptions?.length ?? 0) > 1 && sub == category.classOptions![1];
      return isSecondary ? Color.lerp(base, Colors.black, 0.4)! : base;
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
