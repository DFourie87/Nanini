import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'tuckshop_models.dart';
import 'tuckshop_repository.dart';

class TuckshopPurchasesScreen extends StatefulWidget {
  const TuckshopPurchasesScreen({super.key, required this.repo, required this.farmId});
  final TuckshopRepository repo;
  final String? farmId;
  @override
  State<TuckshopPurchasesScreen> createState() => _TuckshopPurchasesScreenState();
}

class _TuckshopPurchasesScreenState extends State<TuckshopPurchasesScreen> {
  final employeesRepo = EmployeesRepository();
  DateTime? from;
  DateTime? to;
  String? employeeFilter;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TuckshopPurchase>>(
      stream: widget.repo.watchPurchases(),
      builder: (context, purSnap) {
        return StreamBuilder<List<Employee>>(
          stream: employeesRepo.watchEmployees(),
          builder: (context, empSnap) {
            return StreamBuilder<List<TuckshopItem>>(
              stream: widget.repo.watchItems(),
              builder: (context, itemSnap) {
                final employees = {for (final e in empSnap.data ?? <Employee>[]) e.id: e};
                final items = {for (final i in itemSnap.data ?? <TuckshopItem>[]) i.id: i};
                var purchases = (purSnap.data ?? []).where((p) => p.farmId == widget.farmId || p.farmId == null).toList();
                if (from != null) purchases = purchases.where((p) => !(parseDateStr(p.date)?.isBefore(from!) ?? true)).toList();
                if (to != null) purchases = purchases.where((p) => !(parseDateStr(p.date)?.isAfter(to!) ?? true)).toList();
                if (employeeFilter != null) purchases = purchases.where((p) => p.employeeId == employeeFilter).toList();
                final sortedEmployees = employees.values.toList()..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

                final byEmployee = <String, double>{};
                final deductedByEmployee = <String, double>{};
                final purchasesByEmployee = <String, List<TuckshopPurchase>>{};
                for (final p in purchases) {
                  byEmployee[p.employeeId] = (byEmployee[p.employeeId] ?? 0) + p.revenue;
                  if (p.payslipId != null) {
                    deductedByEmployee[p.employeeId] = (deductedByEmployee[p.employeeId] ?? 0) + p.revenue;
                  }
                  (purchasesByEmployee[p.employeeId] ??= []).add(p);
                }
                final employeeIds = byEmployee.keys.toList()
                  ..sort((a, b) =>
                      (employees[a]?.displayName ?? 'Unknown').toLowerCase().compareTo((employees[b]?.displayName ?? 'Unknown').toLowerCase()));

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(context: context, initialDate: from ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                              if (picked != null) setState(() => from = picked);
                            },
                            child: Text(from == null ? 'From' : fmtDateDisplay(toDateStr(from!))),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(context: context, initialDate: to ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                              if (picked != null) setState(() => to = picked);
                            },
                            child: Text(to == null ? 'To' : fmtDateDisplay(toDateStr(to!))),
                          ),
                          DropdownButton<String?>(
                            value: employeeFilter,
                            hint: const Text('All employees'),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All employees')),
                              ...sortedEmployees.map((e) => DropdownMenuItem(value: e.id, child: Text(e.displayName))),
                            ],
                            onChanged: (v) => setState(() => employeeFilter = v),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: employeeIds.isEmpty
                          ? const Center(child: Text('No purchases logged yet.'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: employeeIds.length,
                              itemBuilder: (context, i) {
                                final empId = employeeIds[i];
                                final total = byEmployee[empId] ?? 0;
                                final deducted = deductedByEmployee[empId] ?? 0;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ExpansionTile(
                                    title: Text(employees[empId]?.displayName ?? 'Unknown employee'),
                                    subtitle: Text(
                                      'Total ${fmtR(total)} · Deducted ${fmtR(deducted)} · Outstanding ${fmtR(total - deducted)}',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    children: [
                                      for (final row in _itemRows(purchasesByEmployee[empId] ?? [], items))
                                        ListTile(
                                          dense: true,
                                          title: Text(row.label),
                                          trailing: Text(fmtR(row.revenue)),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// Groups an employee's purchases by item (manual/bulk entries with no
  /// item id are grouped separately under their note), summing qty and
  /// revenue for each -- so someone who bought bread three times in the
  /// selected range sees one "Bread" row, not three.
  List<_ItemRow> _itemRows(List<TuckshopPurchase> purchases, Map<String, TuckshopItem> items) {
    final byLabel = <String, _ItemRow>{};
    for (final p in purchases) {
      final item = p.itemId != null ? items[p.itemId] : null;
      final label = item?.name ?? (p.note ?? 'Manual purchase');
      final existing = byLabel[label];
      final qty = (existing?.qty ?? 0) + (p.qty ?? 0);
      final revenue = (existing?.revenue ?? 0) + p.revenue;
      byLabel[label] = _ItemRow(label: item != null ? '$label (${qty.toStringAsFixed(0)})' : label, qty: qty, revenue: revenue);
    }
    final rows = byLabel.values.toList()..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return rows;
  }
}

class _ItemRow {
  _ItemRow({required this.label, required this.qty, required this.revenue});
  final String label;
  final double qty;
  final double revenue;
}
