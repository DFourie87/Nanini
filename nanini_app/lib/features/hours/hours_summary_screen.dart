import 'package:csv/csv.dart';
import 'package:provider/provider.dart';
import '../../core/auth/app_modules.dart';
import '../../core/auth/session.dart';
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
  const HoursSummaryScreen({super.key, required this.data, required this.lines, required this.scopeBar, required this.payUpTo, required this.farmName, this.memberInfo});
  final HoursData data;
  final List<PayLine> lines;
  final Widget scopeBar;
  final DateTime payUpTo;

  /// The farm filter's name, or null for all farms.
  final String? farmName;

  /// The Members tab: every member of Nanini 121 CC, for their salary
  /// info; [lines] are then only theirs.
  final List<Employee>? memberInfo;

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
                    if (memberInfo != null) ...[
                      for (final m in memberInfo!) _MemberCard(m, data: data),
                      if (memberInfo!.isEmpty) const EmptyPayNote(),
                    ],
                    if (lines.isEmpty && memberInfo == null)
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
                                  ..._byMethod(farmLines),
                                  const SizedBox(height: 8),
                                  // Hours per worker per day of the month.
                                  OutlinedButton.icon(
                                    onPressed: () => _showCalendar(context, farmShort(farm), farmLines),
                                    icon: const Icon(Icons.calendar_month_outlined),
                                    label: const Text('Calendar'),
                                  ),
                                  const SizedBox(height: 8),
                                  // The summary page printed with the payslips, before paying.
                                  OutlinedButton.icon(
                                    onPressed: () => _previewSummary(context, farmShort(farm), farmLines),
                                    icon: const Icon(Icons.preview_outlined),
                                    label: const Text('Summary'),
                                  ),
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
                                  OutlinedButton.icon(
                                    onPressed: () => _showCalendar(context, 'Members', members),
                                    icon: const Icon(Icons.calendar_month_outlined),
                                    label: const Text('Calendar'),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: () => _previewSummary(context, 'Members', members),
                                    icon: const Icon(Icons.preview_outlined),
                                    label: const Text('Summary'),
                                  ),
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

  /// The hours calendar for this pay period (from the earliest day after a
  /// last pay up to the "pay up to" date), by calendar date: every worker's
  /// hours per day.
  Future<void> _showCalendar(BuildContext context, String farmLabel, List<PayLine> farmLines) {
    final upTo = toDateStr(payUpTo);
    final from = farmLines.map((l) => l.periodStart(upTo)).fold<String>(upTo, (a, b) => b.compareTo(a) < 0 ? b : a);
    return showPdfPreview(
      context,
      () => buildCalendarPdf(
        farmName: farmLabel,
        from: parseDateStr(from) ?? payUpTo,
        to: payUpTo,
        employees: [for (final l in farmLines) l.employee],
        entries: data.entries ?? const [],
      ),
      landscape: true,
      title: 'Calendar: $farmLabel',
    );
  }

  /// The summary page that's printed with the payslips, as it stands now
  /// (nothing is paid or saved).
  Future<void> _previewSummary(BuildContext context, String farmLabel, List<PayLine> farmLines) {
    final upTo = toDateStr(payUpTo);
    final today = toDateStr(DateTime.now());
    // The ATM access code only if today's is already set (another farm paid
    // today); otherwise Run payroll makes it, so none is shown yet.
    final code = (data.payslips ?? const <Payslip>[]).where((p) => p.paidDate == today && (p.atmAccessCode ?? '').isNotEmpty).firstOrNull?.atmAccessCode;
    final slips = [for (final l in farmLines) (_draftPayslip(l, upTo: upTo, paidDate: today, atmCode: code), l.employee)];
    return showPdfPreview(context, () => buildRunPdf(farmName: farmLabel, slips: slips, preview: true), landscape: true, title: 'Summary: $farmLabel');
  }

  /// Pays a farm -- all its workers, or only those ticked (someone paid
  /// earlier or later than the rest is simply left for their own run; each
  /// worker's next pay starts after their own last payslip).
  Future<void> _runPayroll(BuildContext context, Farm? farm, List<PayLine> farmLines, {String? label}) async {
    // An admin, or someone given this farm's payroll (e.g. Haaskraal's) in
    // Manage users. The members' run is for admins only.
    final allowed = farm != null && context.read<Session>().can(farmRight('payroll', farm.name));
    if (!allowed && !await requireAdmin(context)) return;
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
                    const SizedBox(height: 10),
                    const Text('Untick employees not paid now', style: TextStyle(fontWeight: FontWeight.w600)),
                    Row(
                      children: [
                        TextButton(onPressed: () => setLocal(() => picked.addAll(farmLines.map((l) => l.employee.id))), child: const Text('All')),
                        TextButton(onPressed: () => setLocal(picked.clear), child: const Text('None')),
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
                        child: Text('Printed on the payslips of those paid by ATM. The same for everyone paid on this day.',
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
                    return setLocal(() => error = 'Paid by ATM, so the payslip needs a phone number (Employees > List) for: ${noPhone.join(', ')}.');
                  }
                  final noTariff = lines.where((l) => l.hours > 0 && l.tariff <= 0).map((l) => l.employee.displayName).toList();
                  if (noTariff.isNotEmpty) return setLocal(() => error = 'Set a tariff first (tap the worker, or Payslips on the phone) for: ${noTariff.join(', ')}.');
                  final drafts = [
                    for (final l in lines)
                      (
                        _draftPayslip(l, upTo: upTo, paidDate: toDateStr(paidDate), atmCode: code),
                        l.purchases.map((p) => p.id).toList(),
                        l.extras.map((x) => x.id).toList(),
                      ),
                  ];
                  // First the summary and payslips as they'll be printed:
                  // approve to pay, or back to this window to change things.
                  final slips = [for (var n = 0; n < drafts.length; n++) (drafts[n].$1, lines[n].employee)];
                  final approved = await confirmPdfPreview(
                    ctx,
                    () => buildRunPdf(farmName: farmLabel, slips: slips),
                    title: 'Payroll $farmLabel: ${lines.length} workers, ${fmtR(total)} nett',
                    approveLabel: 'Approve and run payroll',
                  );
                  if (!approved || !ctx.mounted) return;
                  try {
                    await data.repo.runPayroll(drafts);
                    done = [for (var n = 0; n < drafts.length; n++) (drafts[n].$1, lines[n].employee)];
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    final why = friendlyDbError(e);
                    setLocal(() => error = why);
                    // Clearly not paid: say so, not just the red line above.
                    if (ctx.mounted) {
                      await showDialog<void>(
                        context: ctx,
                        builder: (c) => AlertDialog(
                          title: const Text('Payroll NOT run', style: TextStyle(color: NaniniColors.red)),
                          content: Text('Nothing was saved -- nobody is marked as paid.\n\n$why'),
                          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
                        ),
                      );
                    }
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
    if (print && context.mounted) await showPdfPreview(context, () => buildRunPdf(farmName: farmLabel, slips: slips), title: 'Payslips: $farmLabel');
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

/// A member's salary info: monthly salary, PAYE and UIF on it, nett, how
/// they're paid and when last paid. Set in List (the member's details).
class _MemberCard extends StatelessWidget {
  const _MemberCard(this.m, {required this.data});
  final Employee m;
  final HoursData data;

  @override
  Widget build(BuildContext context) {
    final salary = m.monthlySalary ?? 0;
    final paye = calcMonthlyPAYE(salary);
    final uifOn = m.uifDeduct ?? m.hasId;
    final uif = uifOn ? calcUIF(salary) : 0.0;
    final farm = data.farms.where((f) => f.id == m.farmId).firstOrNull;
    final paid = (data.payslips ?? const <Payslip>[]).where((p) => p.employeeId == m.id).map((p) => p.paidDate).fold<String?>(
        null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a);
    final method = switch (m.paymentMethod) {
      PaymentMethod.bank => 'Paid by bank transfer${(m.bankName ?? '').isEmpty ? '' : ' (${m.bankName})'}',
      PaymentMethod.atm => 'Paid by ATM',
      PaymentMethod.cash => 'Paid in cash',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(m.displayName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text([if (farm != null) farmShort(farm), if (!m.onPayroll) 'not on payroll' else method].join(' · '),
                style: const TextStyle(color: NaniniColors.muted)),
            if (m.onPayroll) ...[
              const SizedBox(height: 6),
              AmountRow('Monthly salary', salary),
              if (paye > 0) AmountRow('PAYE', -paye),
              if (uif > 0) AmountRow('UIF', -uif),
              const Divider(),
              AmountRow('Nett salary', salary - paye - uif, bold: true),
              Text(paid == null ? 'Not paid here yet' : 'Last paid ${fmtDateDisplay(paid)}', style: const TextStyle(color: NaniniColors.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineTile extends StatefulWidget {
  const _LineTile(this.l, {this.onTap});
  final PayLine l;

  /// Office correction of this worker's tariff, rent, loan or extra pay.
  final VoidCallback? onTap;

  @override
  State<_LineTile> createState() => _LineTileState();
}

/// Name and nett; tap the name to see how the pay is worked out.
class _LineTileState extends State<_LineTile> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    const muted = NaniniColors.muted;
    // One line per step of the sum: + pay, − deductions, = totals.
    Widget line(String sign, String label, double amount, {bool bold = false, Color? color}) {
      final style = TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 18,
              child: Text(sign, style: style.copyWith(fontWeight: FontWeight.w700)),
            ),
            Expanded(child: Text(label, style: style, softWrap: true)),
            const SizedBox(width: 8),
            Text(fmtR(amount), style: style),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => open = !open),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Icon(open ? Icons.expand_less : Icons.expand_more, size: 20, color: NaniniColors.muted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(l.employee.displayName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        Text(
                          fmtR(l.nett),
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: l.nett < 0 ? NaniniColors.red : NaniniColors.ink),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.onTap != null)
                IconButton(tooltip: 'Change tariff, rent, loan or extra pay', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: widget.onTap),
            ],
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (l.hours > 0) line('+', '${fmtHours(_r(l.hours))} × ${fmtRCents(l.tariff)}', l.hoursPay),
                  if (l.kg > 0) line('+', '${_r(l.kg)} kg × ${fmtRCents(l.kgRate)}', l.kgPay),
                  for (final x in l.extras)
                    line(
                      '+',
                      x.hours != null && x.hours! > 0 ? '${x.description}: ${fmtHours(_r(x.hours!))} × ${fmtRCents(x.rate ?? 0)}' : x.description,
                      x.amount,
                    ),
                  if (l.salary > 0) line('+', 'Salary', l.salary),
                  line('=', 'Gross', l.gross, bold: true),
                  if (l.paye > 0) line('−', 'PAYE', l.paye, color: muted),
                  if (l.uif > 0) line('−', 'UIF', l.uif, color: muted),
                  if (l.rent > 0) line('−', 'Rent', l.rent, color: muted),
                  if (l.loan > 0) line('−', 'Loan', l.loan, color: muted),
                  if (l.tuckshop > 0) line('−', 'Tuck shop', l.tuckshop, color: muted),
                  if (l.deductions > 0) line('=', 'Nett', l.nett, bold: true, color: l.nett < 0 ? NaniniColors.red : null),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// How the nett is paid out -- an allocation of it, so each is shown
/// negative and together they come to exactly the nett shown above: by bank
/// transfer, in cash and by ATM. Every worker is in exactly one. The amounts
/// are whole rands like the nett, so any rand lost to rounding goes to the
/// biggest one.
List<Widget> _byMethod(List<PayLine> lines) {
  final split = payoutSplit(lines);
  return [
    AmountRow('  by bank transfer', -split[PaymentMethod.bank]!, color: NaniniColors.muted),
    AmountRow('  in cash', -split[PaymentMethod.cash]!, color: NaniniColors.muted),
    AmountRow('  by ATM', -split[PaymentMethod.atm]!, color: NaniniColors.muted),
  ];
}

/// The nett of [lines] per way of paying, in whole rands that add up to the
/// nett rounded to the rand.
@visibleForTesting
Map<PaymentMethod, double> payoutSplit(List<PayLine> lines) {
  double of(PaymentMethod m) => lines.where((l) => l.employee.paymentMethod == m).fold<double>(0, (s, l) => s + l.nett);
  final exact = {for (final m in PaymentMethod.values) m: of(m)};
  final rounded = {for (final e in exact.entries) e.key: e.value.roundToDouble()};
  final total = exact.values.fold<double>(0, (a, b) => a + b).roundToDouble();
  final diff = total - rounded.values.fold<double>(0, (a, b) => a + b);
  if (diff != 0) {
    final biggest = rounded.keys.reduce((a, b) => exact[a]!.abs() >= exact[b]!.abs() ? a : b);
    rounded[biggest] = rounded[biggest]! + diff;
  }
  return rounded;
}

double _r(double v) => (v * 100).roundToDouble() / 100;

/// [l] as a payslip (not saved): what Run payroll pays and the summary shows.
Payslip _draftPayslip(PayLine l, {required String upTo, required String paidDate, String? atmCode}) => Payslip(
      id: '',
      employeeId: l.employee.id,
      farmId: l.employee.farmId,
      periodStart: l.periodStart(upTo),
      periodEnd: upTo,
      paidDate: paidDate,
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
      atmAccessCode: l.employee.paymentMethod == PaymentMethod.atm ? atmCode : null,
      nett: l.nett,
      createdAt: DateTime.now(),
    );
