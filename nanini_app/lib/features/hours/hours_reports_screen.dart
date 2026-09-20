import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/formatters.dart';
import '../../core/widgets/toast.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import '../tuckshop/tuckshop_models.dart';
import '../tuckshop/tuckshop_repository.dart';
import 'hours_excel_import.dart';
import 'hours_models.dart';
import 'hours_repository.dart';
import 'hours_payslip_preview.dart';

class HoursReportsScreen extends StatefulWidget {
  const HoursReportsScreen({super.key, required this.repo});
  final HoursRepository repo;
  @override
  State<HoursReportsScreen> createState() => _HoursReportsScreenState();
}

class _HoursReportsScreenState extends State<HoursReportsScreen> {
  final employeesRepo = EmployeesRepository();
  final tuckshopRepo = TuckshopRepository();
  DateTime from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime to = DateTime.now();

  DateTime sarsFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime sarsTo = DateTime.now();

  List<Farm> farms = [];

  /// Employee id -> that employee's fully pre-computed payroll row, from an
  /// uploaded Haaskraal sheet. Cleared whenever the period changes since
  /// it's a one-off input for that specific payroll run, not a stored log.
  Map<String, HaaskraalPayrollRow> haaskraalPayroll = {};

  @override
  void initState() {
    super.initState();
    employeesRepo.fetchFarms().then((f) {
      if (mounted) setState(() => farms = f);
    });
  }

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
                return StreamBuilder<List<TuckshopPurchase>>(
                  stream: tuckshopRepo.watchPurchases(),
                  builder: (context, tsSnap) {
                    return StreamBuilder<List<Payslip>>(
                      stream: widget.repo.watchPayslips(),
                      builder: (context, paySnap) {
                        final employees = empSnap.data ?? [];
                        final purchases = tsSnap.data ?? [];
                        final payslips = paySnap.data ?? [];

                        bool inRange(String dateStr) {
                          final d = parseDateStr(dateStr);
                          return d != null && !d.isBefore(from) && !d.isAfter(to);
                        }

                        final entries = (entrySnap.data ?? []).where((e) => inRange(e.date)).toList();
                        final kgEntries = (kgSnap.data ?? []).where((k) => inRange(k.date)).toList();
                        final purchasesInRange = purchases.where((p) => p.payslipId == null && inRange(p.date)).toList();
                        final haaskraalFarm = farms.where((f) => f.name.contains('Haaskraal')).firstOrNull;

                        final rows = <_PayrollRow>[];
                        for (final emp in employees) {
                          final haaskraalRow =
                              (haaskraalFarm != null && emp.farmId == haaskraalFarm.id) ? haaskraalPayroll[emp.id] : null;
                          if (haaskraalRow != null) {
                            // Haaskraal: the uploaded sheet is the source of truth for this
                            // run -- gross/rent/shop/uif/loan/nett come straight from it,
                            // not the app's own calc (and it has no PAYE column, so 0 here).
                            if (haaskraalRow.gross <= 0) continue;
                            rows.add(_PayrollRow(emp, haaskraalRow.gross, haaskraalRow.hoursWorked, haaskraalRow.hourlyRate, 0, 0, 0,
                                haaskraalRow.uif, haaskraalRow.rent, haaskraalRow.loan, haaskraalRow.tuckshopDeduction, haaskraalRow.nett, const []));
                            continue;
                          }

                          final empHoursEntries = entries.where((e) => e.employeeId == emp.id).toList();
                          final empKgEntries = kgEntries.where((k) => k.employeeId == emp.id).toList();
                          final hoursWorked = empHoursEntries.fold<double>(0, (s, e) => s + e.hours);
                          final hoursGross = empHoursEntries.fold<double>(0, (s, e) => s + e.gross);
                          final hourlyRate = hoursWorked > 0 ? hoursGross / hoursWorked : (emp.ratePerHour ?? 0);
                          final kgWorked = empKgEntries.fold<double>(0, (s, k) => s + k.kg);
                          final kgGross = empKgEntries.fold<double>(0, (s, k) => s + k.gross);
                          final kgRate = kgWorked > 0 ? kgGross / kgWorked : 0.0;
                          final gross = hoursGross + kgGross;
                          final empPurchases = purchasesInRange.where((p) => p.employeeId == emp.id).toList();
                          final tuckshop = empPurchases.fold<double>(0, (s, p) => s + p.revenue);
                          if (gross <= 0 && tuckshop <= 0) continue;
                          final hasId = (emp.idOrPassport ?? '').isNotEmpty;
                          final paye = hasId ? calcMonthlyPAYE(gross) : 0.0;
                          final uif = hasId ? calcUIF(gross) : 0.0;
                          final rent = emp.rentDeduction ?? 0;
                          final loan = emp.loanDeduction ?? 0;
                          final nett = gross - paye - uif - rent - loan - tuckshop;
                          rows.add(_PayrollRow(emp, gross, hoursWorked, hourlyRate, kgWorked, kgRate, paye, uif, rent, loan, tuckshop, nett,
                              empPurchases.map((p) => p.id).toList()));
                        }

                        // "Paid through" -- the most recent payroll run, grouped by the
                        // paid_date + period it shares with every payslip from that run.
                        Payslip? latestRun;
                        for (final p in payslips) {
                          if (latestRun == null || p.paidDate.compareTo(latestRun.paidDate) > 0) latestRun = p;
                        }
                        final latestRunRows = latestRun == null
                            ? <Payslip>[]
                            : payslips.where((p) => p.paidDate == latestRun!.paidDate && p.periodEnd == latestRun!.periodEnd).toList();
                        final latestRunTotal = latestRunRows.fold<double>(0, (s, p) => s + p.nett);

                        final overlapping = latestRun == null
                            ? <String>[]
                            : payslips
                                .where((p) =>
                                    rows.any((r) => r.employee.id == p.employeeId) &&
                                    !(to.isBefore(parseDateStr(p.periodStart)!) || from.isAfter(parseDateStr(p.periodEnd)!)))
                                .map((p) => employees.where((e) => e.id == p.employeeId).firstOrNull?.displayName ?? 'Unknown')
                                .toSet()
                                .toList();

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
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      final picked = await showDatePicker(context: context, initialDate: from, firstDate: DateTime(2020), lastDate: DateTime(2100));
                                      if (picked != null) setState(() { from = picked; haaskraalPayroll = {}; });
                                    },
                                    child: Text('From ${fmtDateDisplay(toDateStr(from))}'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      final picked = await showDatePicker(context: context, initialDate: to, firstDate: DateTime(2020), lastDate: DateTime(2100));
                                      if (picked != null) setState(() { to = picked; haaskraalPayroll = {}; });
                                    },
                                    child: Text('To ${fmtDateDisplay(toDateStr(to))}'),
                                  ),
                                ),
                              ],
                            ),
                            if (haaskraalFarm != null) ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: () => _uploadHaaskraalHours(context, employees, haaskraalFarm),
                                  icon: const Icon(Icons.upload_file_outlined),
                                  label: Text(haaskraalPayroll.isEmpty
                                      ? 'Upload Haaskraal payroll (Excel)'
                                      : 'Haaskraal payroll uploaded for ${haaskraalPayroll.length} employee${haaskraalPayroll.length == 1 ? '' : 's'} -- re-upload'),
                                ),
                              ),
                            ],
                            if (latestRun != null) ...[
                              const SizedBox(height: 12),
                              Card(
                                color: Colors.green.withValues(alpha: 0.08),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle_outline, color: Colors.green),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Paid through ${fmtDateDisplay(latestRun.periodEnd)} · ${fmtR(latestRunTotal)} nett · '
                                          'paid on ${fmtDateDisplay(latestRun.paidDate)}',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => _exportCsv(rows),
                                icon: const Icon(Icons.download),
                                label: const Text('Export CSV'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (rows.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text('No pay to report in this range.'),
                              )
                            else ...[
                              for (final r in rows)
                                Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ExpansionTile(
                                    title: Text(r.employee.displayName),
                                    subtitle: Text('Gross ${fmtR(r.gross)} · Nett ${fmtR(r.nett)}'),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (r.hoursWorked > 0)
                                              Text('${r.hoursWorked.toStringAsFixed(1)} hrs × ${fmtR(r.hourlyRate)}/hr',
                                                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                            if (r.kgWorked > 0)
                                              Text('${r.kgWorked.toStringAsFixed(1)} kg × ${fmtR(r.kgRate)}/kg',
                                                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                            if (r.hoursWorked > 0 || r.kgWorked > 0) const SizedBox(height: 6),
                                            _row('Gross', r.gross),
                                            if (r.paye > 0) _row('PAYE', -r.paye),
                                            if (r.uif > 0) _row('UIF', -r.uif),
                                            if (r.rent > 0) _row('Rent', -r.rent),
                                            if (r.loan > 0) _row('Loan', -r.loan),
                                            if (r.tuckshop > 0) _row('Tuck shop', -r.tuckshop),
                                            _row('Total deductions', -(r.paye + r.uif + r.rent + r.loan + r.tuckshop)),
                                            const Divider(),
                                            _row('Nett pay', r.nett, bold: true),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () => _runPayroll(context, rows, overlapping),
                                icon: const Icon(Icons.payments_outlined),
                                label: const Text('Run payroll for this period'),
                              ),
                            ],
                            const SizedBox(height: 28),
                            const Divider(),
                            const SizedBox(height: 12),
                            Text('SARS PAYE/UIF report', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            const Text(
                              'Totals from paid payslips only, by the date they were paid — use the matching '
                              'range for your EMP201 (monthly) or EMP501 (bi-annual reconciliation) filing. '
                              'UIF assumes no earnings ceiling; confirm against SARS\'s current ceiling before filing.',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      final picked =
                                          await showDatePicker(context: context, initialDate: sarsFrom, firstDate: DateTime(2020), lastDate: DateTime(2100));
                                      if (picked != null) setState(() => sarsFrom = picked);
                                    },
                                    child: Text('From ${fmtDateDisplay(toDateStr(sarsFrom))}'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      final picked =
                                          await showDatePicker(context: context, initialDate: sarsTo, firstDate: DateTime(2020), lastDate: DateTime(2100));
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
                                onPressed: sarsPayslips.isEmpty
                                    ? null
                                    : () => _exportSarsCsv(sarsByEmployee, employees, sarsPaye, sarsUifTotal, sarsTotalDue),
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
                                    subtitle: Text('Paid ${fmtDateDisplay(key.$1)} · ${runs[key]!.length} employees · '
                                        '${fmtR(runs[key]!.fold<double>(0, (s, p) => s + p.nett))} nett'),
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
              },
            );
          },
        );
      },
    );
  }

  Future<void> _uploadHaaskraalHours(BuildContext context, List<Employee> employees, Farm haaskraalFarm) async {
    final haaskraalEmployees = employees.where((e) => e.farmId == haaskraalFarm.id).toList();
    if (haaskraalEmployees.isEmpty) {
      showToast(context, 'No employees assigned to ${haaskraalFarm.name} yet', isError: true);
      return;
    }
    HoursImportResult? result;
    try {
      result = await pickAndParseHoursExcel(haaskraalEmployees);
    } catch (e) {
      if (context.mounted) showToast(context, 'Could not read that file: $e', isError: true);
      return;
    }
    if (result == null) return; // user cancelled the picker
    if (!context.mounted) return;
    setState(() => haaskraalPayroll = result!.rowsByEmployeeId);
    final matched = result.rowsByEmployeeId.length;
    if (result.unmatched.isEmpty) {
      showToast(context, 'Matched payroll for $matched employee${matched == 1 ? '' : 's'}');
    } else {
      showToast(context, 'Matched $matched -- could not match: ${result.unmatched.join(', ')}', isError: true);
    }
  }

  Future<void> _runPayroll(BuildContext context, List<_PayrollRow> rows, List<String> overlapping) async {
    var paidDate = DateTime.now();
    final total = rows.fold<double>(0, (s, r) => s + r.nett);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Run payroll'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${rows.length} employees · ${fmtR(total)} nett total for ${fmtDateDisplay(toDateStr(from))} – ${fmtDateDisplay(toDateStr(to))}.'),
              const SizedBox(height: 12),
              if (overlapping.isNotEmpty) ...[
                Text(
                  'Already has a payslip overlapping this range: ${overlapping.join(', ')}. Running again will pay them twice for the overlap.',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
              ],
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: ctx, initialDate: paidDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (picked != null) setLocal(() => paidDate = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Payment date'),
                  child: Text(fmtDateDisplay(toDateStr(paidDate))),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Run payroll')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final drafts = rows
        .map((r) => (
              Payslip(
                id: '',
                employeeId: r.employee.id,
                farmId: r.employee.farmId,
                periodStart: toDateStr(from),
                periodEnd: toDateStr(to),
                paidDate: toDateStr(paidDate),
                gross: r.gross,
                hoursWorked: r.hoursWorked,
                hourlyRate: r.hourlyRate,
                kgWorked: r.kgWorked,
                kgRate: r.kgRate,
                paye: r.paye,
                uif: r.uif,
                rent: r.rent,
                loan: r.loan,
                tuckshopDeduction: r.tuckshop,
                nett: r.nett,
                createdAt: DateTime.now(),
              ),
              r.tuckshopPurchaseIds,
            ))
        .toList();

    await widget.repo.runPayroll(drafts);
    if (!context.mounted) return;
    showToast(context, 'Payroll run: ${rows.length} employees, ${fmtR(total)} nett');
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
      ['Employee', 'Hours worked', 'Rate/hr', 'Kg picked', 'Rate/kg', 'Gross', 'PAYE', 'UIF', 'Rent', 'Loan', 'Tuck shop', 'Total deductions', 'Nett'],
      for (final r in rows)
        [
          r.employee.displayName,
          r.hoursWorked,
          r.hourlyRate,
          r.kgWorked,
          r.kgRate,
          r.gross,
          r.paye,
          r.uif,
          r.rent,
          r.loan,
          r.tuckshop,
          r.paye + r.uif + r.rent + r.loan + r.tuckshop,
          r.nett,
        ],
    ];
    final csv = const ListToCsvConverter().convert(data);
    await Share.share(csv, subject: 'hours-payroll-${todayStr()}.csv');
  }

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

class _PayrollRow {
  _PayrollRow(this.employee, this.gross, this.hoursWorked, this.hourlyRate, this.kgWorked, this.kgRate, this.paye, this.uif, this.rent, this.loan,
      this.tuckshop, this.nett, this.tuckshopPurchaseIds);
  final Employee employee;
  final double gross, hoursWorked, hourlyRate, kgWorked, kgRate, paye, uif, rent, loan, tuckshop, nett;
  final List<String> tuckshopPurchaseIds;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
