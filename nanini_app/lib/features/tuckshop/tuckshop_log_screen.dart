import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'tuckshop_models.dart';
import 'tuckshop_repository.dart';
import '../../core/run_once.dart';

class TuckshopLogScreen extends StatefulWidget {
  const TuckshopLogScreen({super.key, required this.repo, required this.farmId});
  final TuckshopRepository repo;
  final String? farmId;
  @override
  State<TuckshopLogScreen> createState() => _TuckshopLogScreenState();
}

class _TuckshopLogScreenState extends State<TuckshopLogScreen> {
  final employeesRepo = EmployeesRepository();
  String? employeeId;
  String? itemId;
  int qty = 1;
  DateTime date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Employee>>(
      stream: employeesRepo.watchEmployees(),
      builder: (context, empSnap) {
        final employees = empSnap.data ?? [];
        // Every shop (Limpopodraai and Haaskraal) sells per item from its stock.
        return StreamBuilder<List<TuckshopItem>>(
          stream: widget.repo.watchItems(),
          builder: (context, itemSnap) {
            final items = (itemSnap.data ?? []).where((i) => i.farmId == widget.farmId && !i.archived).toList();
            return _buildItemMode(context, employees, items);
          },
        );
      },
    );
  }

  Widget _buildItemMode(BuildContext context, List<Employee> employees, List<TuckshopItem> items) {
    final selectedItem = items.where((i) => i.id == itemId).firstOrNull;
    final total = selectedItem != null ? selectedItem.sellPrice * qty : 0.0;
    final sortedEmployees = [...employees]..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    final sortedItems = [...items]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: employeeId,
          decoration: const InputDecoration(labelText: 'Employee'),
          items: sortedEmployees.map((e) => DropdownMenuItem(value: e.id, child: Text(e.displayName))).toList(),
          onChanged: (v) => setState(() => employeeId = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: itemId,
          decoration: const InputDecoration(labelText: 'Item'),
          items: sortedItems.map((i) => DropdownMenuItem(value: i.id, child: Text('${i.name} (${i.totalStock.toStringAsFixed(0)} in stock)'))).toList(),
          onChanged: (v) => setState(() => itemId = v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => qty = qty == 1 ? -1 : qty - 1),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$qty', style: Theme.of(context).textTheme.titleLarge),
            IconButton(
              onPressed: () => setState(() => qty = qty == -1 ? 1 : qty + 1),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        if (qty < 0)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('Credit -- returns stock and reduces this employee\'s total', style: TextStyle(color: NaniniColors.muted)),
          ),
        const SizedBox(height: 12),
        _DateField(date: date, onChanged: (d) => setState(() => date = d)),
        const SizedBox(height: 20),
        Text('Total: ${fmtR(total)}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => runOnce('tuckshop_log_screen.1', () async {
            if (employeeId == null || selectedItem == null) {
              showToast(context, 'Select employee and item', isError: true);
              return;
            }
            if (qty > 0 && qty > selectedItem.totalStock) {
              showToast(context, 'Only ${selectedItem.totalStock.toStringAsFixed(0)} in stock', isError: true);
            }
            final emp = employees.firstWhere((e) => e.id == employeeId);
            await widget.repo.logItemPurchase(item: selectedItem, employee: emp, qty: qty.toDouble(), date: toDateStr(date));
            if (!context.mounted) return;
            showToast(context, qty < 0 ? 'Credit logged' : 'Purchase logged');
            setState(() => qty = 1);
          }),
          child: Text(qty < 0 ? 'Log credit' : 'Log purchase'),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onChanged});
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => runOnce('tuckshop_log_screen.3', () async {
        final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
        if (picked != null) onChanged(picked);
      }),
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Date'),
        child: Text(fmtDateDisplay(toDateStr(date))),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
