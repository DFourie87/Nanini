import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../employees/employees_models.dart';
import 'hours_data.dart';
import 'hours_payslip_preview.dart';
import 'hours_models.dart';
import 'pay_run.dart';
import 'pay_widgets.dart';

/// Hours > Summary: the Work tab's three steps added up per worker and per
/// farm -- gross, deductions and nett -- and where payroll is run.
class HoursSummaryScreen extends StatelessWidget {
  const HoursSummaryScreen({super.key, required this.data, required this.lines, required this.scopeBar, required this.payUpTo, required this.farmName});
  final HoursData data;
  final List<PayLine> lines;
  final Widget scopeBar;
  final DateTime payUpTo;

  /// The farm filter's name, or null for all farms.
  final String? farmName;

  @override
  Widget build(BuildContext context) {
    double sum(double Function(PayLine) f, [List<PayLine>? of]) => (of ?? lines).fold<double>(0, (s, l) => s + f(l));
    return Column(
      children: [
        scopeBar,
        Expanded(
          child: !data.loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    if (lines.isEmpty)
                      const EmptyPayNote()
                    else ...[
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('${farmName ?? 'All farms'} · ${lines.length} worker${lines.length == 1 ? '' : 's'}',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                              Text('${fmtHours(_r(sum((l) => l.hours)))} worked', style: const TextStyle(color: NaniniColors.muted)),
                              const SizedBox(height: 6),
                              AmountRow('Gross', sum((l) => l.gross)),
                              AmountRow('Deductions', -sum((l) => l.deductions)),
                              const Divider(),
                              AmountRow('Nett to pay', sum((l) => l.nett), bold: true),
                            ],
                          ),
                        ),
                      ),
                      for (final (farm, farmLines) in byFarm(lines, data.farms))
                        FarmSection(
                          title: farmShort(farm),
                          totals: 'Nett ${fmtR(sum((l) => l.nett, farmLines))}',
                          children: [
                            for (final l in farmLines) _LineTile(l),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  AmountRow('${farmShort(farm)}: ${fmtHours(_r(sum((l) => l.hours, farmLines)))} · gross', sum((l) => l.gross, farmLines)),
                                  AmountRow('Deductions', -sum((l) => l.deductions, farmLines)),
                                  AmountRow('Nett', sum((l) => l.nett, farmLines), bold: true),
                                  const SizedBox(height: 8),
                                  // Each farm is paid on its own.
                                  FilledButton.icon(
                                    onPressed: () => _runPayroll(context, farm, farmLines),
                                    icon: const Icon(Icons.payments_outlined),
                                    label: Text('Run payroll -- ${farmShort(farm)}'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(onPressed: () => _exportCsv(), icon: const Icon(Icons.download), label: const Text('Export CSV')),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _runPayroll(BuildContext context, Farm? farm, List<PayLine> lines) async {
    if (!await requireAdmin(context)) return;
    if (!context.mounted) return;
    final farmLabel = farmShort(farm);
    final noTariff = lines.where((l) => l.hours > 0 && l.tariff <= 0).map((l) => l.employee.displayName).toList();
    if (noTariff.isNotEmpty) {
      return showProblem(context, 'Set a tariff first (Work > 2 Tariff) for: ${noTariff.join(', ')}.', title: "Can't run payroll yet");
    }
    final upTo = toDateStr(payUpTo);
    final total = lines.fold<double>(0, (s, l) => s + l.nett);
    var paidDate = DateTime.now();
    String? error;
    List<(Payslip, Employee)>? done;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: dialogTitleWithError('Run payroll -- $farmLabel', error),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$farmLabel: ${lines.length} workers · ${fmtR(total)} nett, '
                  'for work since their last pay up to ${fmtDateDisplay(upTo)}.'),
              const SizedBox(height: 12),
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final drafts = [
                  for (final l in lines)
                    (
                      Payslip(
                        id: '',
                        employeeId: l.employee.id,
                        farmId: l.employee.farmId,
                        periodStart: l.periodStart(upTo),
                        periodEnd: upTo,
                        paidDate: toDateStr(paidDate),
                        gross: l.gross,
                        hoursWorked: l.hours,
                        hourlyRate: l.tariff,
                        kgWorked: l.kg,
                        kgRate: l.kgRate,
                        paye: l.paye,
                        uif: l.uif,
                        rent: l.rent,
                        loan: l.loan,
                        tuckshopDeduction: l.tuckshop,
                        nett: l.nett,
                        createdAt: DateTime.now(),
                      ),
                      l.purchases.map((p) => p.id).toList(),
                    ),
                ];
                try {
                  await data.repo.runPayroll(drafts);
                  done = [for (var n = 0; n < drafts.length; n++) (drafts[n].$1, lines[n].employee)];
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  setLocal(() => error = friendlyDbError(e));
                }
              },
              child: const Text('Run payroll'),
            ),
          ],
        ),
      ),
    );
    final slips = done;
    if (slips == null || !context.mounted) return;
    showToast(context, 'Payroll run for $farmLabel: ${slips.length} workers, ${fmtR(total)} nett');
    final print = await confirmDialog(
      context,
      title: 'Print payslips?',
      message: 'A summary page for $farmLabel followed by every payslip. (Also later under Reports > Payslip history.)',
      confirmLabel: 'Print',
    );
    if (print && context.mounted) await showPdfPreview(context, () => buildRunPdf(farmName: farmLabel, slips: slips));
  }

  Future<void> _exportCsv() async {
    final rows = <List<dynamic>>[
      ['Farm', 'Employee', 'Since', 'Hours', 'Tariff/hr', 'Hours pay', 'Kg picked', 'Kg pay', 'Gross', 'PAYE', 'UIF', 'Rent', 'Loan', 'Tuck shop', 'Total deductions', 'Nett'],
      for (final (farm, farmLines) in byFarm(lines, data.farms))
        for (final l in farmLines)
          [
            farmShort(farm),
            l.employee.displayName,
            l.since ?? '',
            _r(l.hours),
            l.tariff,
            _r(l.hoursPay),
            _r(l.kg),
            _r(l.kgPay),
            _r(l.gross),
            _r(l.paye),
            _r(l.uif),
            l.rent,
            l.loan,
            _r(l.tuckshop),
            _r(l.deductions),
            _r(l.nett),
          ],
    ];
    await Share.share(const ListToCsvConverter().convert(rows), subject: 'hours-summary-${toDateStr(payUpTo)}.csv');
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile(this.l);
  final PayLine l;

  @override
  Widget build(BuildContext context) {
    final cuts = [
      if (l.paye > 0) 'PAYE ${fmtR(l.paye)}',
      if (l.uif > 0) 'UIF ${fmtR(l.uif)}',
      if (l.rent > 0) 'Rent ${fmtR(l.rent)}',
      if (l.tuckshop > 0) 'Tuck ${fmtR(l.tuckshop)}',
      if (l.loan > 0) 'Loan ${fmtR(l.loan)}',
    ];
    return ListTile(
      title: Text(l.employee.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text([
            if (l.hours > 0) '${fmtHours(_r(l.hours))} × ${fmtRCents(l.tariff)}',
            if (l.kg > 0) '${_r(l.kg)} kg picked',
            'gross ${fmtR(l.gross)}',
          ].join(' · ')),
          if (cuts.isNotEmpty) Text('Less ${cuts.join(' · ')}', style: const TextStyle(color: NaniniColors.muted)),
        ],
      ),
      trailing: Text(fmtR(l.nett), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: l.nett < 0 ? NaniniColors.red : NaniniColors.ink)),
    );
  }
}

double _r(double v) => (v * 100).roundToDouble() / 100;
