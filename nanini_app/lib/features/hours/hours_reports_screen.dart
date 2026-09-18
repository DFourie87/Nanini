import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/formatters.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'hours_models.dart';
import 'hours_repository.dart';

class HoursReportsScreen extends StatefulWidget {
  const HoursReportsScreen({super.key, required this.repo});
  final HoursRepository repo;
  @override
  State<HoursReportsScreen> createState() => _HoursReportsScreenState();
}

class _HoursReportsScreenState extends State<HoursReportsScreen> {
  final employeesRepo = EmployeesRepository();
  DateTime from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime to = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HoursEntry>>(
      stream: widget.repo.watchEntries(),
      builder: (context, entrySnap) {
        return StreamBuilder<List<KgEntry>>(
          stream: widget.repo.watchKgEntries(),
          builder: (context, kgSnap) {
            return StreamBuilder<List<Employee>>(
              stream: employeesRepo.watchEmployees(),
              builder: (context, empSnap) {
                final employees = empSnap.data ?? [];

                bool inRange(String dateStr) {
                  final d = parseDateStr(dateStr);
                  return d != null && !d.isBefore(from) && !d.isAfter(to);
                }

                final entries = (entrySnap.data ?? []).where((e) => inRange(e.date)).toList();
                final kgEntries = (kgSnap.data ?? []).where((k) => inRange(k.date)).toList();

                final rows = <_PayrollRow>[];
                for (final emp in employees) {
                  final hoursGross = entries.where((e) => e.employeeId == emp.id).fold<double>(0, (s, e) => s + e.gross);
                  final kgGross = kgEntries.where((k) => k.employeeId == emp.id).fold<double>(0, (s, k) => s + k.gross);
                  final gross = hoursGross + kgGross;
                  if (gross <= 0) continue;
                  final hasId = (emp.idOrPassport ?? '').isNotEmpty;
                  final paye = hasId ? calcMonthlyPAYE(gross) : 0.0;
                  final uif = hasId ? calcUIF(gross) : 0.0;
                  final rent = emp.rentDeduction ?? 0;
                  final loan = emp.loanDeduction ?? 0;
                  final nett = gross - paye - uif - rent - loan;
                  rows.add(_PayrollRow(emp, gross, paye, uif, rent, loan, nett));
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => _exportCsv(rows),
                          icon: const Icon(Icons.download),
                          label: const Text('Export CSV'),
                        ),
                      ),
                    ),
                    Expanded(
                      child: rows.isEmpty
                          ? const Center(child: Text('No pay to report in this range.'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              itemCount: rows.length,
                              itemBuilder: (context, i) {
                                final r = rows[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ExpansionTile(
                                    title: Text(r.employee.displayName),
                                    subtitle: Text('Gross ${fmtR(r.gross)} · Nett ${fmtR(r.nett)}'),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                        child: Column(
                                          children: [
                                            _row('Gross', r.gross),
                                            _row('PAYE', -r.paye),
                                            _row('UIF', -r.uif),
                                            _row('Rent', -r.rent),
                                            _row('Loan', -r.loan),
                                            const Divider(),
                                            _row('Nett pay', r.nett, bold: true),
                                          ],
                                        ),
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

  Widget _row(String label, double value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(fmtR(value), style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400))],
        ),
      );

  Future<void> _exportCsv(List<_PayrollRow> rows) async {
    final data = <List<dynamic>>[
      ['Employee', 'Gross', 'PAYE', 'UIF', 'Rent', 'Loan', 'Nett'],
      for (final r in rows) [r.employee.displayName, r.gross, r.paye, r.uif, r.rent, r.loan, r.nett],
    ];
    final csv = const ListToCsvConverter().convert(data);
    await Share.share(csv, subject: 'hours-payroll-${todayStr()}.csv');
  }
}

class _PayrollRow {
  _PayrollRow(this.employee, this.gross, this.paye, this.uif, this.rent, this.loan, this.nett);
  final Employee employee;
  final double gross, paye, uif, rent, loan, nett;
}
