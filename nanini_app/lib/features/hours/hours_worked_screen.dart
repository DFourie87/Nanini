import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'hours_models.dart';
import 'hours_repository.dart';

/// Open to everyone (no manager login needed) — a simple date-range summary
/// of hours worked per employee.
class HoursWorkedScreen extends StatefulWidget {
  const HoursWorkedScreen({super.key, required this.repo});
  final HoursRepository repo;
  @override
  State<HoursWorkedScreen> createState() => _HoursWorkedScreenState();
}

class _HoursWorkedScreenState extends State<HoursWorkedScreen> {
  final employeesRepo = EmployeesRepository();
  DateTime from = DateTime.now().subtract(const Duration(days: 7));
  DateTime to = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HoursEntry>>(
      stream: widget.repo.watchEntries(),
      builder: (context, entrySnap) {
        return StreamBuilder<List<Employee>>(
          stream: employeesRepo.watchEmployees(),
          builder: (context, empSnap) {
            final employees = empSnap.data ?? [];
            final entries = (entrySnap.data ?? []).where((e) {
              final d = parseDateStr(e.date);
              return d != null && !d.isBefore(from) && !d.isAfter(to);
            }).toList();

            final totals = <String, double>{};
            for (final e in entries) {
              totals[e.employeeId] = (totals[e.employeeId] ?? 0) + e.hours;
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
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
                ),
                Expanded(
                  child: totals.isEmpty
                      ? const Center(child: Text('No hours logged in this range.'))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: totals.entries.map((entry) {
                            final emp = employees.where((e) => e.id == entry.key).firstOrNull;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(emp?.displayName ?? 'Unknown'),
                                trailing: Text(fmtHours(entry.value)),
                              ),
                            );
                          }).toList(),
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
