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
import 'pay_edit.dart';
import 'hours_models.dart';
import 'pay_run.dart';
import 'pay_widgets.dart';

/// Employees > Summary: the Payslips check (on the capture phones) added up per worker and per
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
    // Members of Nanini 121 CC (only admins get them) are kept apart: not in
    // the farm totals, paid in their own run below.
    final workers = lines.where((l) => !l.employee.isMember).toList();
    final members = membersOf(lines);
    double sum(double Function(PayLine) f, [List<PayLine>? of]) => (of ?? workers).fold<double>(0, (s, l) => s + f(l));
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
                      if (workers.isNotEmpty)
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('${farmName ?? 'All farms'} · ${workers.length} worker${workers.length == 1 ? '' : 's'}',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                              Text('${fmtHours(_r(sum((l) => l.hours)))} worked', style: const TextStyle(color: NaniniColors.muted)),
                              const SizedBox(height: 6),
                              AmountRow('Gross', sum((l) => l.gross)),
                              AmountRow('Deductions', -sum((l) => l.deductions)),
                              const Divider(),
                              AmountRow('Nett to pay', sum((l) => l.nett), bold: true),
                              ..._byMethod(workers),
                            ],
                          ),
                        ),
                      ),
                      for (final (farm, farmLines) in byFarm(lines, data.farms))
                        FarmSection(
                          title: farmShort(farm),
                          totals: 'Nett ${fmtR(sum((l) => l.nett, farmLines))}',
                          children: [
                            for (final l in farmLines) _LineTile(l, onTap: () => showPayLineEditor(context, data, l, payUpTo)),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  AmountRow('${farmShort(farm)}: ${fmtHours(_r(sum((l) => l.hours, farmLines)))} · gross', sum((l) => l.gross, farmLines)),
                                  AmountRow('Deductions', -sum((l) => l.deductions, farmLines)),
                                  AmountRow('Nett', sum((l) => l.nett, farmLines), bold: true),
                                  ..._byMethod(farmLines, atmFarm: _atmFarm(farm)),
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
                      if (members.isNotEmpty)
                        FarmSection(
                          title: 'Members (private)',
                          totals: 'Nett ${fmtR(sum((l) => l.nett, members))}',
                          children: [
                            for (final l in members) _LineTile(l, onTap: () => showPayLineEditor(context, data, l, payUpTo)),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  AmountRow('Members: gross', sum((l) => l.gross, members)),
                                  AmountRow('Deductions', -sum((l) => l.deductions, members)),
                                  AmountRow('Nett', sum((l) => l.nett, members), bold: true),
                                  ..._byMethod(members),
                                  const SizedBox(height: 8),
                                  FilledButton.icon(
                                    onPressed: () => _runPayroll(context, null, members, label: 'Members'),
                                    icon: const Icon(Icons.lock_outline),
                                    label: const Text('Run payroll -- Members'),
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

  /// Pays a farm -- all its workers, or only those ticked (someone paid
  /// earlier or later than the rest is simply left for their own run; each
  /// worker's next pay starts after their own last payslip).
  Future<void> _runPayroll(BuildContext context, Farm? farm, List<PayLine> farmLines, {String? label}) async {
    if (!await requireAdmin(context)) return;
    if (!context.mounted) return;
    final farmLabel = label ?? farmShort(farm);
    final upTo = toDateStr(payUpTo);
    final picked = {for (final l in farmLines) l.employee.id};
    var paidDate = DateTime.now();
    // ATM card pay: one 6-digit access code per payday, the same for every
    // farm's run that day and new on every other payday.
    String atmCode() => atmCodeFor(toDateStr(paidDate), data.payslips ?? const []);
    var code = atmCode();
    String? error;
    List<(Payslip, Employee)>? done;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final lines = farmLines.where((l) => picked.contains(l.employee.id)).toList();
          final total = lines.fold<double>(0, (s, l) => s + l.nett);
          return AlertDialog(
            title: dialogTitleWithError('Run payroll -- $farmLabel', error),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${lines.length} of ${farmLines.length} workers · ${fmtR(total)} nett, for work since their last pay up to ${fmtDateDisplay(upTo)}.'),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        TextButton(onPressed: () => setLocal(() => picked.addAll(farmLines.map((l) => l.employee.id))), child: const Text('All')),
                        TextButton(onPressed: () => setLocal(picked.clear), child: const Text('None')),
                        const Expanded(
                          child: Text('Untick anyone paid on another day', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
                        ),
                      ],
                    ),
                    for (final l in farmLines)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: picked.contains(l.employee.id),
                        onChanged: (v) => setLocal(() => v == true ? picked.add(l.employee.id) : picked.remove(l.employee.id)),
                        title: Text(l.employee.displayName),
                        secondary: Text(fmtR(l.nett), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final d = await showDatePicker(context: ctx, initialDate: paidDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                        if (d != null) {
                          setLocal(() {
                            paidDate = d;
                            code = atmCode();
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Payment date'),
                        child: Text(fmtDateDisplay(toDateStr(paidDate))),
                      ),
                    ),
                    if (lines.any((l) => l.employee.paymentMethod == PaymentMethod.atm)) ...[
                      const SizedBox(height: 10),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'ATM access code for this payday'),
                        child: Text(code, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 3)),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Printed on the payslips of those paid by ATM card. The same for everyone paid on this day.',
                            style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  if (lines.isEmpty) return setLocal(() => error = 'Tick at least one worker.');
                  final noPhone = lines
                      .where((l) => l.employee.paymentMethod == PaymentMethod.atm && (l.employee.phoneNumber ?? '').trim().isEmpty)
                      .map((l) => l.employee.displayName)
                      .toList();
                  if (noPhone.isNotEmpty) {
                    return setLocal(() => error = 'Paid by ATM card, so the payslip needs a phone number (Employees > List) for: ${noPhone.join(', ')}.');
                  }
                  final noTariff = lines.where((l) => l.hours > 0 && l.tariff <= 0).map((l) => l.employee.displayName).toList();
                  if (noTariff.isNotEmpty) return setLocal(() => error = 'Set a tariff first (tap the worker, or Payslips on the phone) for: ${noTariff.join(', ')}.');
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
                          // A member's salary is shown as a pay line of its own.
                          extraPay: l.extraPay + l.salary,
                          extras: [
                            if (l.salary > 0) {'description': 'Monthly salary', 'amount': l.salary},
                            ...l.extras.map((x) => x.toLine()),
                          ],
                          paye: l.paye,
                          uif: l.uif,
                          rent: l.rent,
                          loan: l.loan,
                          tuckshopDeduction: l.tuckshop,
                          atmAccessCode: l.employee.paymentMethod == PaymentMethod.atm ? code : null,
                          nett: l.nett,
                          createdAt: DateTime.now(),
                        ),
                        l.purchases.map((p) => p.id).toList(),
                        l.extras.map((x) => x.id).toList(),
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
                child: Text('Pay ${lines.length}'),
              ),
            ],
          );
        },
      ),
    );
    final slips = done;
    if (slips == null || !context.mounted) return;
    final total = slips.fold<double>(0, (s, p) => s + p.$1.nett);
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
      ['Farm', 'Employee', 'Since', 'Hours', 'Tariff/hr', 'Hours pay', 'Kg picked', 'Kg pay', 'Extra pay', 'Gross', 'PAYE', 'UIF', 'Rent', 'Loan', 'Tuck shop', 'Total deductions', 'Nett'],
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
            _r(l.extraPay),
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
  const _LineTile(this.l, {this.onTap});
  final PayLine l;

  /// Office correction of this worker's tariff, rent, loan or extra pay.
  final VoidCallback? onTap;

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
      onTap: onTap,
      title: Text(l.employee.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text([
            if (l.hours > 0) '${fmtHours(_r(l.hours))} × ${fmtRCents(l.tariff)}',
            if (l.kg > 0) '${_r(l.kg)} kg picked',
            if (l.salary > 0) 'salary ${fmtR(l.salary)}',
            if (l.extraPay != 0) 'extra ${fmtR(l.extraPay)}',
            'gross ${fmtR(l.gross)}',
          ].join(' · ')),
          if (cuts.isNotEmpty) Text('Less ${cuts.join(' · ')}', style: const TextStyle(color: NaniniColors.muted)),
        ],
      ),
      trailing: Text(fmtR(l.nett), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: l.nett < 0 ? NaniniColors.red : NaniniColors.ink)),
    );
  }
}

/// How the nett is paid out: by bank transfer, and in cash -- or, for
/// Doornbult ([atmFarm]), by ATM card instead of cash. The other one shows
/// only when someone is paid that way.
List<Widget> _byMethod(List<PayLine> lines, {bool atmFarm = false}) {
  double of(PaymentMethod m) => lines.where((l) => l.employee.paymentMethod == m).fold<double>(0, (s, l) => s + l.nett);
  final atm = of(PaymentMethod.atm);
  final cash = of(PaymentMethod.cash);
  return [
    AmountRow('  by bank transfer', of(PaymentMethod.bank), color: NaniniColors.muted),
    if (atmFarm || atm != 0) AmountRow('  by ATM card', atm, color: NaniniColors.muted),
    if (!atmFarm || cash != 0) AmountRow('  in cash', cash, color: NaniniColors.muted),
  ];
}

/// Doornbult pays by ATM card, not in cash.
bool _atmFarm(Farm? farm) => (farm?.name ?? '').toLowerCase().contains('doornbult');

double _r(double v) => (v * 100).roundToDouble() / 100;
