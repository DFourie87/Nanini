import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'hours_models.dart';
import 'hours_repository.dart';
import 'hours_payslip_preview.dart';

/// Hours > Reports (admins): the SARS PAYE/UIF report and payslip history.
/// Pay per worker is checked in Work and paid from Summary.
class HoursReportsScreen extends StatefulWidget {
  const HoursReportsScreen({super.key, required this.repo});
  final HoursRepository repo;
  @override
  State<HoursReportsScreen> createState() => _HoursReportsScreenState();
}

class _HoursReportsScreenState extends State<HoursReportsScreen> {
  final employeesRepo = EmployeesRepository();
  late final _employees = employeesRepo.watchEmployees();
  late final _payslips = widget.repo.watchPayslips();

  DateTime sarsFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime sarsTo = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Employee>>(
      stream: _employees,
      builder: (context, empSnap) {
        return StreamBuilder<List<Payslip>>(
          stream: _payslips,
          builder: (context, paySnap) {
            final employees = empSnap.data ?? [];
            final payslips = paySnap.data ?? [];
            // Payslip history, grouped into runs by paid_date + period.
            final runs = <(String paidDate, String periodStart, String periodEnd), List<Payslip>>{};
            for (final p in payslips) {
              final key = (p.paidDate, p.periodStart, p.periodEnd);
              runs.putIfAbsent(key, () => []).add(p);
            }
            final sortedRunKeys = runs.keys.toList()..sort((a, b) => b.$1.compareTo(a.$1));

            // SARS PAYE/UIF totals -- based on what was actually paid (paidDate),
            // not draft hours, matching what EMP201/EMP501 reconcile against.
            final sarsPayslips = payslips.where((p) {
              final d = parseDateStr(p.paidDate);
              return d != null && !d.isBefore(sarsFrom) && !d.isAfter(sarsTo);
            }).toList();
            final sarsPaye = sarsPayslips.fold<double>(0, (s, p) => s + p.paye);
            final sarsUifEmployee = sarsPayslips.fold<double>(0, (s, p) => s + p.uif);
            final sarsUifEmployer = sarsUifEmployee;
            final sarsUifTotal = sarsUifEmployee + sarsUifEmployer;
            final sarsTotalDue = sarsPaye + sarsUifTotal;
            final sarsByEmployee = <String, (double paye, double uif)>{};
            for (final p in sarsPayslips) {
              final cur = sarsByEmployee[p.employeeId] ?? (0.0, 0.0);
              sarsByEmployee[p.employeeId] = (cur.$1 + p.paye, cur.$2 + p.uif);
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('SARS PAYE/UIF report', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text(
                  'Totals from paid payslips only, by the date they were paid — use the matching '
                  'range for your EMP201 (monthly) or EMP501 (bi-annual reconciliation) filing. '
                  'UIF assumes no earnings ceiling; confirm against SARS\'s current ceiling before filing.',
                  style: TextStyle(color: NaniniColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(context: context, initialDate: sarsFrom, firstDate: DateTime(2020), lastDate: DateTime(2100));
                          if (picked != null) setState(() => sarsFrom = picked);
                        },
                        child: Text('From ${fmtDateDisplay(toDateStr(sarsFrom))}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(context: context, initialDate: sarsTo, firstDate: DateTime(2020), lastDate: DateTime(2100));
                          if (picked != null) setState(() => sarsTo = picked);
                        },
                        child: Text('To ${fmtDateDisplay(toDateStr(sarsTo))}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row('PAYE', sarsPaye),
                        _row('UIF — employee (1%)', sarsUifEmployee),
                        _row('UIF — employer (1%)', sarsUifEmployer),
                        _row('Total UIF', sarsUifTotal),
                        const Divider(),
                        _row('Total due to SARS', sarsTotalDue, bold: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: sarsPayslips.isEmpty ? null : () => _exportSarsCsv(sarsByEmployee, employees, sarsPaye, sarsUifTotal, sarsTotalDue),
                    icon: const Icon(Icons.download),
                    label: const Text('Export SARS CSV'),
                  ),
                ),
                if (sarsByEmployee.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('By employee', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final entry in sarsByEmployee.entries)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        title: Text(employees.where((e) => e.id == entry.key).firstOrNull?.displayName ?? 'Unknown'),
                        subtitle: Text('PAYE ${fmtR(entry.value.$1)} · UIF (employee) ${fmtR(entry.value.$2)}'),
                      ),
                    ),
                ],
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 12),
                Text('Payslip history', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (sortedRunKeys.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No payroll runs yet.'))
                else
                  for (final key in sortedRunKeys)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        title: Text('${fmtDateDisplay(key.$2)} – ${fmtDateDisplay(key.$3)}'),
                        subtitle: Text(
                          'Paid ${fmtDateDisplay(key.$1)} · ${runs[key]!.length} employees · '
                          '${fmtR(runs[key]!.fold<double>(0, (s, p) => s + p.nett))} nett',
                        ),
                        children: [
                          for (final p in runs[key]!)
                            ListTile(
                              dense: true,
                              title: Text(employees.where((e) => e.id == p.employeeId).firstOrNull?.displayName ?? 'Unknown'),
                              subtitle: Text('Nett ${fmtR(p.nett)}'),
                              trailing: const Icon(Icons.picture_as_pdf_outlined),
                              onTap: () {
                                final emp = employees.where((e) => e.id == p.employeeId).firstOrNull;
                                if (emp != null) showPayslipPreview(context, p, emp);
                              },
                            ),
                        ],
                      ),
                    ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _row(String label, double value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(fmtR(value), style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      ],
    ),
  );

  Future<void> _exportSarsCsv(
    Map<String, (double, double)> sarsByEmployee,
    List<Employee> employees,
    double totalPaye,
    double totalUif,
    double totalDue,
  ) async {
    final data = <List<dynamic>>[
      ['SARS PAYE/UIF report', '${fmtDateDisplay(toDateStr(sarsFrom))} to ${fmtDateDisplay(toDateStr(sarsTo))}'],
      [],
      ['Employee', 'ID/Passport', 'PAYE', 'UIF (employee)'],
      for (final entry in sarsByEmployee.entries)
        [
          employees.where((e) => e.id == entry.key).firstOrNull?.displayName ?? 'Unknown',
          employees.where((e) => e.id == entry.key).firstOrNull?.idOrPassport ?? '',
          entry.value.$1,
          entry.value.$2,
        ],
      [],
      ['Total PAYE', totalPaye],
      ['Total UIF (employee + employer)', totalUif],
      ['Total due to SARS', totalDue],
    ];
    final csv = const ListToCsvConverter().convert(data);
    await Share.share(csv, subject: 'sars-paye-uif-${todayStr()}.csv');
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
