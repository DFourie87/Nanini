import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/toast.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

class SalesEntryScreen extends StatefulWidget {
  const SalesEntryScreen({super.key, required this.repo});
  final SalesRepository repo;
  @override
  State<SalesEntryScreen> createState() => _SalesEntryScreenState();
}

class _LineDraft {
  String? subcategory;
  String? klass;
  final grossCtrl = TextEditingController();
}

class _SalesEntryScreenState extends State<SalesEntryScreen> {
  SalesCategory category = kSalesCategories.first;
  final agentCtrl = TextEditingController();
  final reportNumberCtrl = TextEditingController();
  DateTime reportDate = DateTime.now();
  final grossTotalCtrl = TextEditingController();
  final vatOnSalesCtrl = TextEditingController();
  final commissionCtrl = TextEditingController();
  final vatOnCommissionCtrl = TextEditingController();
  final nettCtrl = TextEditingController();
  List<_LineDraft> lines = [_LineDraft()];

  bool get isTobacco => category.key == 'tobacco';

  @override
  Widget build(BuildContext context) {
    final sortedCategories = [...kSalesCategories]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<SalesCategory>(
          initialValue: category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: sortedCategories.map((c) => DropdownMenuItem(value: c, child: Text(c.label))).toList(),
          onChanged: (v) => setState(() { category = v!; lines = [_LineDraft()]; }),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(context: context, initialDate: reportDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (picked != null) setState(() => reportDate = picked);
          },
          child: InputDecorator(decoration: const InputDecoration(labelText: 'Report date'), child: Text(fmtDateDisplay(toDateStr(reportDate)))),
        ),
        const SizedBox(height: 12),
        TextField(controller: reportNumberCtrl, decoration: const InputDecoration(labelText: 'Report number *')),
        const SizedBox(height: 12),
        TextField(controller: agentCtrl, decoration: const InputDecoration(labelText: 'Market agent')),
        const SizedBox(height: 20),
        Text('Line items', style: Theme.of(context).textTheme.titleMedium),
        for (var i = 0; i < lines.length; i++) _lineRow(i),
        OutlinedButton.icon(
          onPressed: () => setState(() => lines.add(_LineDraft())),
          icon: const Icon(Icons.add),
          label: const Text('Add line item'),
        ),
        const SizedBox(height: 20),
        TextField(controller: grossTotalCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Gross sales total (R)')),
        if (isTobacco) ...[
          const SizedBox(height: 12),
          TextField(controller: vatOnSalesCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'VAT on sales (R)')),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: commissionCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: isTobacco ? 'Deductions — packaging (before VAT)' : 'Commission/Deductions before VAT (R)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: vatOnCommissionCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: isTobacco ? 'VAT on deductions (R)' : 'VAT on commission/deductions (R)'),
        ),
        const SizedBox(height: 12),
        TextField(controller: nettCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Nett amount received (R)')),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: const Text('Save report')),
      ],
    );
  }

  Widget _lineRow(int i) {
    final line = lines[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: isTobacco
                ? TextField(
                    decoration: const InputDecoration(labelText: 'Grade (e.g. F2F)', isDense: true),
                    onChanged: (v) => line.subcategory = v.toUpperCase(),
                  )
                : DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Subcategory', isDense: true),
                    items: category.subcats.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => line.subcategory = v,
                  ),
          ),
          if (category.hasClass) ...[
            const SizedBox(width: 6),
            Expanded(
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Class', isDense: true),
                items: kPotatoClasses.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => line.klass = v,
              ),
            ),
          ],
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: line.grossCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'R', isDense: true),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: lines.length > 1 ? () => setState(() => lines.removeAt(i)) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final reportNumber = reportNumberCtrl.text.trim();
    if (reportNumber.isEmpty) {
      showToast(context, 'Report number is required', isError: true);
      return;
    }
    if (isTobacco && lines.any((l) => (l.subcategory ?? '').isEmpty)) {
      showToast(context, 'Every tobacco line needs a grade', isError: true);
      return;
    }
    final exists = await widget.repo.reportNumberExists(reportNumber);
    if (!mounted) return;
    if (exists) {
      showToast(context, 'Report number already saved', isError: true);
      return;
    }

    final lineItems = lines
        .where((l) => double.tryParse(l.grossCtrl.text) != null)
        .map((l) => SalesLineItem(category: category.key, subcategory: l.subcategory, klass: l.klass, grossAmount: double.parse(l.grossCtrl.text)))
        .toList();

    final grossTotal = double.tryParse(grossTotalCtrl.text) ?? lineItems.fold<double>(0, (s, l) => s + l.grossAmount);

    final report = SalesReport(
      category: category.key,
      agent: agentCtrl.text.trim().isEmpty ? null : agentCtrl.text.trim(),
      reportNumber: reportNumber,
      reportDate: toDateStr(reportDate),
      grossTotal: grossTotal,
      commissionBeforeVat: double.tryParse(commissionCtrl.text) ?? 0,
      vat: double.tryParse(vatOnCommissionCtrl.text) ?? 0,
      vatOnSales: isTobacco ? double.tryParse(vatOnSalesCtrl.text) : null,
      nettAmount: double.tryParse(nettCtrl.text) ?? 0,
    );

    await widget.repo.saveReport(report, lineItems);
    if (!mounted) return;
    showToast(context, 'Report saved');
    setState(() {
      agentCtrl.clear();
      reportNumberCtrl.clear();
      grossTotalCtrl.clear();
      vatOnSalesCtrl.clear();
      commissionCtrl.clear();
      vatOnCommissionCtrl.clear();
      nettCtrl.clear();
      lines = [_LineDraft()];
    });
  }
}
