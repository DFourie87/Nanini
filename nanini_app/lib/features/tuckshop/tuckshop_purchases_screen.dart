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
            final employees = {for (final e in empSnap.data ?? <Employee>[]) e.id: e};
            var purchases = (purSnap.data ?? []).where((p) => p.farmId == widget.farmId || p.farmId == null).toList();
            if (from != null) purchases = purchases.where((p) => !(parseDateStr(p.date)?.isBefore(from!) ?? true)).toList();
            if (to != null) purchases = purchases.where((p) => !(parseDateStr(p.date)?.isAfter(to!) ?? true)).toList();
            if (employeeFilter != null) purchases = purchases.where((p) => p.employeeId == employeeFilter).toList();
            purchases.sort((a, b) => b.date.compareTo(a.date));

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
                          ...employees.values.map((e) => DropdownMenuItem(value: e.id, child: Text(e.displayName))),
                        ],
                        onChanged: (v) => setState(() => employeeFilter = v),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: purchases.isEmpty
                      ? const Center(child: Text('No purchases logged yet.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: purchases.length,
                          itemBuilder: (context, i) {
                            final p = purchases[i];
                            final emp = employees[p.employeeId];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(emp?.displayName ?? 'Unknown employee'),
                                subtitle: Text('${fmtDateDisplay(p.date)}${p.note != null && p.note!.isNotEmpty ? ' · ${p.note}' : p.qty != null ? ' · qty ${p.qty!.toStringAsFixed(0)}' : ''}'),
                                trailing: Text(fmtR(p.revenue)),
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
  }
}
