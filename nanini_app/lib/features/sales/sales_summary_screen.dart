import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import '../delivery/delivery_models.dart';
import 'sales_models.dart';
import 'sales_data.dart';

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

// Maps a packaging pallet size to the same (subcategory, class) pairing the
// Sales module uses, so bags logged per field in Packaging can be broken
// down by class/size here without any linkage from the Sales side.
const _palletSizeSubcatClass = {
  'baby10': ('Baby', 'Class 1'),
  'small10': ('Small', 'Class 1'),
  'smallmed7': ('Small/Medium', 'Class 1'),
  'med7': ('Medium', 'Class 1'),
  'largemed10': ('Large/Medium', 'Class 1'),
  'large10': ('Large', 'Class 1'),
  'med10g2': ('Medium', 'Class 2'),
  'largemed10g2': ('Large/Medium', 'Class 2'),
  'large10g2': ('Large', 'Class 2'),
};

class SalesSummaryScreen extends StatefulWidget {
  const SalesSummaryScreen({super.key, required this.data});
  final SalesData data;
  @override
  State<SalesSummaryScreen> createState() => _SalesSummaryScreenState();
}

class _SalesSummaryScreenState extends State<SalesSummaryScreen> {
  SalesCategory category = kSalesCategories.first;
  DateTime from = DateTime(DateTime.now().year, 1, 1);
  DateTime to = DateTime.now();
  String? classFilter;

  /// Peppers: grouped by colour, by box size, or by both.
  _PepperView pepperView = _PepperView.colour;
  @override
  Widget build(BuildContext context) {
    // Loaded once when Sales opens (see SalesData); nothing reloads by itself.
    return ListenableBuilder(
      listenable: widget.data,
      builder: (context, _) {
        final reports = (widget.data.reports ?? []).where((r) {
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
            if (category.key == 'peppers') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<_PepperView>(
                initialValue: pepperView,
                decoration: const InputDecoration(labelText: 'Show'),
                items: const [
                  DropdownMenuItem(value: _PepperView.colour, child: Text('Per colour')),
                  DropdownMenuItem(value: _PepperView.size, child: Text('Per packaging size')),
                  DropdownMenuItem(value: _PepperView.both, child: Text('Per colour and packaging size')),
                ],
                onChanged: (v) => setState(() => pepperView = v ?? pepperView),
              ),
            ] else if (category.hasClass) ...[
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
            Builder(
              builder: (context) {
                final loaded = widget.data.itemsFor(reportIds);
                final lineItems = (loaded ?? []).where((li) => classFilter == null || li.effectiveClass == classFilter).toList();
                if (category.key == 'peppers') {
                  if (loaded == null) {
                    return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
                  }
                  return _pepperBreakdown(context, lineItems, reportsById);
                }
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
                      ? _combinedKey(li.subcategory ?? 'Other', li.effectiveClass)
                      : (li.subcategory ?? 'Other');
                  bySubcat[key] = (bySubcat[key] ?? 0) + nettShare;
                }
                final entries = _orderedEntries(bySubcat);

                final qtyBySubcat = <String, double>{};
                final nettBySubcat = <String, double>{};
                for (final li in lineItems) {
                  final units = li.units;
                  if (units == null || units <= 0) continue;
                  final report = reportsById[li.reportId];
                  final nettExclVat = report != null ? report.grossTotal - report.commissionBeforeVat : 0.0;
                  final nettShare = (report != null && report.grossTotal > 0) ? li.grossAmount / report.grossTotal * nettExclVat : 0.0;
                  final key = category.hasClass
                      ? _combinedKey(li.subcategory ?? 'Other', li.effectiveClass)
                      : (li.subcategory ?? 'Other');
                  qtyBySubcat[key] = (qtyBySubcat[key] ?? 0) + units;
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

                if (loaded == null) {
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
                                      _pct(entries, i),
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
                                title: _pct(entries, i),
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
                                        _pct(qtyEntries, i),
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
            _fieldBreakdownSection(context),
          ],
        );
      },
    );
  }

  int _fieldOrder(String a, String b) {
    final ai = kFieldNames.indexOf(a);
    final bi = kFieldNames.indexOf(b);
    if (ai != bi) {
      if (ai == -1) return 1;
      if (bi == -1) return -1;
      return ai.compareTo(bi);
    }
    return a.compareTo(b);
  }

  /// Field is only collected on approved potato/butternut delivery notes
  /// (peppers and tobacco don't ask for it), so this section quietly shows
  /// nothing outside those two categories or when there's no data yet.
  /// Everything here comes straight from the packaging module's delivery
  /// notes -- sales invoices are uploaded automatically with no field
  /// picked at entry, so there's no way to link a sales report to a field
  /// directly. This is an allocation by bag count, not exact nett sales.
  Widget _fieldBreakdownSection(BuildContext context) {
    final produceType = switch (category.key) {
      'potatoes' => 'potato',
      'butternut' => 'butternut',
      _ => null,
    };
    if (produceType == null) return const SizedBox.shrink();

    return Builder(
      builder: (context) {
        final notes = (widget.data.notes ?? []).where((n) {
          if (n.produceType != produceType) return false;
          if ((n.field ?? '').isEmpty) return false;
          final d = parseDateStr(n.noteDate);
          return d != null && !d.isBefore(from) && !d.isAfter(to);
        }).toList();

        final byField = <String, int>{};
        // Field -> combinedKey(subcategory, class) [potato] or weight
        // [butternut] -> bags, broken down the same way Sales itself
        // breaks potatoes into Class + Size and butternut into weight.
        final byFieldSubcat = <String, Map<String, double>>{};
        for (final n in notes) {
          final subcatMap = byFieldSubcat.putIfAbsent(n.field!, () => {});
          if (produceType == 'potato') {
            var noteBags = 0;
            for (final sz in kPalletSizes) {
              final count = (n.pallets[sz.key] as num?)?.toInt() ?? 0;
              if (count <= 0) continue;
              noteBags += count * sz.bagsPerPallet;
              final mapping = _palletSizeSubcatClass[sz.key];
              if (mapping == null) continue;
              final key = _combinedKey(mapping.$1, mapping.$2);
              subcatMap[key] = (subcatMap[key] ?? 0) + count * sz.bagsPerPallet;
            }
            byField[n.field!] = (byField[n.field!] ?? 0) + noteBags;
          } else {
            byField[n.field!] = (byField[n.field!] ?? 0) + n.total;
            for (final e in (n.produceDetail ?? {}).entries) {
              final qty = (e.value as num?)?.toDouble() ?? 0;
              if (qty <= 0) continue;
              subcatMap[e.key] = (subcatMap[e.key] ?? 0) + qty;
            }
          }
        }
        if (byField.isEmpty) return const SizedBox.shrink();

        final entries = byField.entries.toList()..sort((a, b) => _fieldOrder(a.key, b.key));

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
                              _pct(entries, i),
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
                        title: _pct(entries, i),
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
            if (byFieldSubcat.values.any((m) => m.isNotEmpty)) ...[
              const SizedBox(height: 24),
              Text(
                produceType == 'potato' ? 'Bags by field, class & size' : 'Bags by field & size',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              for (final entry in entries)
                if ((byFieldSubcat[entry.key] ?? {}).isNotEmpty) _fieldSubcatCard(context, entry.key, byFieldSubcat[entry.key]!),
            ],
          ],
        );
      },
    );
  }

  Widget _fieldSubcatCard(BuildContext context, String fieldName, Map<String, double> subcatMap) {
    final ordered = _orderedEntries(subcatMap);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fieldName, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Table(
                columnWidths: const {0: FlexColumnWidth(1.6), 1: FlexColumnWidth(1), 2: FlexColumnWidth(0.6)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  const TableRow(
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: NaniniColors.line))),
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text('Subcategory', style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text('Bags', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text('%', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
                      ),
                    ],
                  ),
                  for (var i = 0; i < ordered.length; i++)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(_displayLabel(ordered[i].key),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _subcatColor(i, ordered[i].key), fontWeight: FontWeight.w600)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(_fmtQty(ordered[i].value), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            _pct(ordered, i),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
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

  /// Peppers, one grouping at a time (colour, box size, or both): a table of
  /// boxes and nett sales per group, and a chart of each.
  Widget _pepperBreakdown(BuildContext context, List<SalesLineItem> lineItems, Map<String, SalesReport> reportsById) {
    final nett = <String, double>{};
    final boxes = <String, double>{};
    final colourOf = <String, String>{};
    final sizeOf = <String, String>{};
    // The lines behind each row (tap a row to see them).
    final detail = <String, List<(SalesLineItem, SalesReport?, double)>>{};
    // Nett of the lines that have a box count, for the average per box.
    final countedNett = <String, double>{};
    var noCountNett = 0.0;
    // Nett the same as the total above (after commission and VAT on it),
    // shared over each report's lines by their gross.
    final lineGross = <String?, double>{};
    for (final li in lineItems) {
      lineGross[li.reportId] = (lineGross[li.reportId] ?? 0) + li.grossAmount;
    }
    for (final li in lineItems) {
      final report = reportsById[li.reportId];
      final g = lineGross[li.reportId] ?? 0;
      final share = (report != null && g > 0) ? li.grossAmount / g * report.nettAmount : 0.0;
      if (li.units == null) noCountNett += share;
      final colour = li.subcategory ?? 'Other';
      final size = li.effectiveClass ?? 'Size unknown';
      final key = switch (pepperView) {
        _PepperView.colour => colour,
        _PepperView.size => size,
        _PepperView.both => '$colour $size',
      };
      colourOf[key] = colour;
      sizeOf[key] = size;
      nett[key] = (nett[key] ?? 0) + share;
      boxes[key] = (boxes[key] ?? 0) + (li.units ?? 0);
      detail.putIfAbsent(key, () => []).add((li, report, share));
      if ((li.units ?? 0) > 0) countedNett[key] = (countedNett[key] ?? 0) + share;
    }
    if (nett.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No line items for this selection.', style: TextStyle(color: NaniniColors.muted)));
    }
    const colours = ['Red', 'Yellow', 'Green'];
    int rank(String k) {
      final c = colours.indexOf(colourOf[k]!);
      final s = kPepperWeights.indexOf(sizeOf[k]!);
      return switch (pepperView) {
        _PepperView.colour => c < 0 ? 99 : c,
        _PepperView.size => s < 0 ? 99 : s,
        _PepperView.both => (c < 0 ? 99 : c) * 10 + (s < 0 ? 9 : s),
      };
    }

    final keys = nett.keys.toList()..sort((a, b) => rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : a.compareTo(b));
    Color colorOf(String k) {
      final base = pepperView == _PepperView.size
          ? (sizeOf[k] == '5kg' ? NaniniColors.rust : sizeOf[k] == '4kg' ? NaniniColors.amber : NaniniColors.muted)
          : (_pepperColors[colourOf[k]] ?? NaniniColors.muted);
      // Colour and size: the 4kg box a darker shade of its colour.
      return pepperView == _PepperView.both && sizeOf[k] == '4kg' ? Color.lerp(base, Colors.black, 0.4)! : base;
    }

    final nettPct = wholePercents([for (final k in keys) nett[k]!]);
    final boxPct = wholePercents([for (final k in keys) boxes[k]!]);
    final totalNett = nett.values.fold<double>(0, (a, b) => a + b);
    final totalBoxes = boxes.values.fold<double>(0, (a, b) => a + b);
    // Average nett price per box: only lines with a box count.
    String perBox(double counted, double n) => n > 0 ? fmtR(counted / n) : '-';
    final totalCounted = countedNett.values.fold<double>(0, (a, b) => a + b);
    final title = switch (pepperView) {
      _PepperView.colour => 'Per colour',
      _PepperView.size => 'Per packaging size',
      _PepperView.both => 'Per colour and packaging size',
    };
    const head = TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12);
    Widget cell(String t, {bool right = true, TextStyle? style}) =>
        // Five columns on a phone: a little smaller, and shrunk to fit rather
        // than cut off.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: right ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(t, maxLines: 1, style: (style ?? const TextStyle()).copyWith(fontSize: style?.fontSize ?? 13)),
          ),
        );

    Widget pie(String label, List<double> values, List<int> pct) => Expanded(
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                child: values.every((v) => v <= 0)
                    ? const Center(child: Text('None', style: TextStyle(color: NaniniColors.muted)))
                    : PieChart(PieChartData(
                        sectionsSpace: 1,
                        centerSpaceRadius: 0,
                        sections: [
                          for (var i = 0; i < keys.length; i++)
                            if (values[i] > 0)
                              PieChartSectionData(
                                value: values[i],
                                color: colorOf(keys[i]),
                                title: '${pct[i]}%',
                                radius: 70,
                                titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                        ],
                      )),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Table(
              columnWidths: const {0: FlexColumnWidth(1.3), 1: FlexColumnWidth(0.8), 2: FlexColumnWidth(1.4), 3: FlexColumnWidth(0.9), 4: FlexColumnWidth(0.55)},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: NaniniColors.line))),
                  children: [cell('', right: false), cell('Boxes', style: head), cell('Nett', style: head), cell('Avg/box', style: head), cell('%', style: head)],
                ),
                for (var i = 0; i < keys.length; i++)
                  TableRow(children: [
                    for (final c in [
                      cell('${keys[i]} ›', right: false, style: TextStyle(color: colorOf(keys[i]), fontWeight: FontWeight.w700)),
                      cell(_fmtQty(boxes[keys[i]]!)),
                      cell(fmtR(nett[keys[i]]!)),
                      cell(perBox(countedNett[keys[i]] ?? 0, boxes[keys[i]]!)),
                      cell('${nettPct[i]}%'),
                    ])
                      TableRowInkWell(onTap: () => _showPepperLines(context, keys[i], detail[keys[i]]!), child: c),
                  ]),
                TableRow(
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: NaniniColors.line))),
                  children: [
                    cell('Total', right: false, style: const TextStyle(fontWeight: FontWeight.w700)),
                    cell(_fmtQty(totalBoxes), style: const TextStyle(fontWeight: FontWeight.w700)),
                    cell(fmtR(totalNett), style: const TextStyle(fontWeight: FontWeight.w700)),
                    cell(perBox(totalCounted, totalBoxes), style: const TextStyle(fontWeight: FontWeight.w700)),
                    cell('100%', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (totalBoxes <= 0)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('No box counts on these reports yet.', style: TextStyle(color: NaniniColors.red, fontSize: 12)),
          )
        else if (noCountNett > 0.5)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${fmtR(noCountNett)} of the nett is on lines without a box count -- tap a row to see which reports.',
                style: const TextStyle(color: NaniniColors.red, fontSize: 12)),
          ),
        const SizedBox(height: 16),
        Row(children: [
          pie('Nett sales', [for (final k in keys) nett[k]!], nettPct),
          const SizedBox(width: 8),
          pie('Boxes', [for (final k in keys) boxes[k]!], boxPct),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 14, runSpacing: 6, children: [
          for (final k in keys)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: colorOf(k), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(k),
            ]),
        ]),
        const SizedBox(height: 8),
        const Text('Nett after commission and VAT (the same as the total above), shared over each report\'s lines by their gross. '
            'Avg/box: nett per box, from the lines that have a box count. Tap a row to see its reports.',
            style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
      ],
    );
  }

  /// The market report lines behind one row: boxes, nett and rand per box,
  /// so an odd box count stands out.
  void _showPepperLines(BuildContext context, String title, List<(SalesLineItem, SalesReport?, double)> lines) {
    final sorted = [...lines]..sort((a, b) => (b.$2?.reportDate ?? '').compareTo(a.$2?.reportDate ?? ''));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${sorted.length} report lines, newest first', style: const TextStyle(color: NaniniColors.muted)),
            const SizedBox(height: 8),
            for (final (li, r, share) in sorted)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  title: Text('${fmtDateDisplay(r?.reportDate ?? '')} · ${r?.agent ?? ''} #${r?.reportNumber ?? ''}'),
                  subtitle: Text(li.description ?? ''),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(li.units == null ? 'no box count' : '${_fmtQty(li.units!)} boxes',
                          style: TextStyle(fontWeight: FontWeight.w700, color: li.units == null ? NaniniColors.red : NaniniColors.ink)),
                      Text(fmtR(share)),
                      if ((li.units ?? 0) > 0) Text('${fmtR(share / li.units!)}/box', style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Combines subcategory + class/weight into one grouping key so e.g.
  /// potato 1st/2nd grade or pepper 4kg/5kg of the same subcategory get
  /// separate pie slices instead of merging.
  static const _noClass = '-';
  String _combinedKey(String main, String? sub) => '$main||${sub ?? _noClass}';

  (String, String) _splitCombinedKey(String key) {
    final parts = key.split('||');
    return (parts[0], parts.length > 1 ? parts[1] : _noClass);
  }

  String _displayLabel(String key) {
    if (!category.hasClass) return key;
    final (main, sub) = _splitCombinedKey(key);
    // No class/size on the line: just the subcategory, e.g. "RED".
    return sub == _noClass ? main : '$main ($sub)';
  }

  /// Share of row [i] as a whole percentage; a table's shares add up to 100.
  String _pct(List<MapEntry<String, num>> rows, int i) => '${wholePercents([for (final r in rows) r.value.toDouble()])[i]}%';

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

enum _PepperView { colour, size, both }
