import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../employees/employees_models.dart';
import 'hours_data.dart';
import 'hours_models.dart';
import 'hours_payslip_preview.dart';
import 'pay_widgets.dart';
import 'payroll_month.dart';

/// The members' group in the payroll history (their own runs, never mixed in
/// with a farm's workers).
const kMembersRunGroup = '__members__';

/// The payroll runs done, newest first: each with its summary + payslips
/// (full page on screen, 4 a page printed), its calendar and each payslip.
/// Shown in Reports (Payslip history) and in Summary (Previous payroll).
class PayrollHistory extends StatelessWidget {
  const PayrollHistory({super.key, required this.runs, required this.employees, required this.hours, required this.farmName});
  final List<PayRun> runs;
  final List<Employee> employees;
  final List<HoursEntry> hours;
  final String Function(String? group) farmName;

  /// Payslips with their employee (one since removed shows as "Unknown").
  List<(Payslip, Employee)> _withEmployees(List<Payslip> slips) => [
        for (final p in slips) (p, employees.where((e) => e.id == p.employeeId).firstOrNull ?? Employee(id: p.employeeId, firstName: 'Unknown', lastName: '')),
      ];

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No payroll runs yet.'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final run in runs)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              title: Text('${farmName(run.farmId)} · ${fmtDateDisplay(run.periodStart)} – ${fmtDateDisplay(run.periodEnd)}'),
              subtitle: Text('Paid ${fmtDateDisplay(run.paidDate)} · ${run.slips.length} workers · ${fmtR(run.totals.nett)} nett'),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => runOnce('payroll_history.print', () => showPdfPreview(
                              context,
                              () => buildRunPdf(farmName: farmName(run.farmId), slips: _withEmployees(run.slips)),
                              title: 'Payslips: ${farmName(run.farmId)}',
                              print: () => buildRunPdf(farmName: farmName(run.farmId), slips: _withEmployees(run.slips), fourPerPage: true),
                            )),
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Print summary + payslips'),
                      ),
                      // The hours of the run's workers over the days it paid.
                      OutlinedButton.icon(
                        onPressed: () => runOnce('payroll_history.calendar', () => showPdfPreview(
                              context,
                              () => buildCalendarPdf(
                                farmName: farmName(run.farmId),
                                from: DateTime.parse(run.periodStart),
                                to: DateTime.parse(run.periodEnd),
                                employees: [for (final (_, e) in _withEmployees(run.slips)) e],
                                entries: hours,
                              ),
                              landscape: true,
                              title: 'Calendar: ${farmName(run.farmId)}',
                            )),
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Calendar'),
                      ),
                    ],
                  ),
                ),
                for (final p in run.slips)
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
  }
}

/// Summary > Previous payroll: the runs done for the farm(s) on the Summary
/// tab ([groups]: farm ids, or [kMembersRunGroup]; null = all), as in Reports.
class PreviousPayrollScreen extends StatelessWidget {
  const PreviousPayrollScreen({super.key, required this.data, this.groups});
  final HoursData data;
  final Set<String?>? groups;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Previous payroll'),
      body: ListenableBuilder(
        listenable: data,
        builder: (context, _) {
          final employees = data.employees ?? const <Employee>[];
          final members = {for (final e in employees) if (e.isMember) e.id};
          String? groupOf(Payslip p) => members.contains(p.employeeId) ? kMembersRunGroup : p.farmId;
          String farmName(String? id) => id == kMembersRunGroup ? 'Members' : farmShort(data.farms.where((f) => f.id == id).firstOrNull);
          final runs = groupRuns(data.payslips ?? const [], groupOf: groupOf).where((r) => groups == null || groups!.contains(r.farmId)).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PayrollHistory(runs: runs, employees: employees, hours: data.entries ?? const [], farmName: farmName),
            ],
          );
        },
      ),
    );
  }
}
