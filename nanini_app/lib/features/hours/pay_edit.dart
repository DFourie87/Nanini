import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/dialog_error.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import 'hours_data.dart';
import 'hours_repository.dart';
import 'pay_run.dart';

/// Office corrections to one worker's pay (Hours > Summary): tariff, rent,
/// loan and extra pay. Farm managers do the same check on their phones
/// (Nanini Capture > Payslips) and send it here to approve.
Future<void> showPayLineEditor(BuildContext context, HoursData data, PayLine l, DateTime payUpTo) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: data,
        builder: (ctx, _) {
          // Live: shows each change as soon as it's saved.
          final e = data.employees?.where((x) => x.id == l.employee.id).firstOrNull ?? l.employee;
          final extras = data.extras.where((x) => x.employeeId == e.id && x.payslipId == null).toList();
          Widget row(IconData icon, String label, String value, VoidCallback onEdit) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon, color: NaniniColors.muted),
                title: Text(label),
                trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: onEdit,
              );
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(e.displayName, style: Theme.of(ctx).textTheme.titleLarge),
                  const Text('Tap a line to change it', style: TextStyle(color: NaniniColors.muted)),
                  row(Icons.payments_outlined, 'Tariff', e.ratePerHour == null ? 'Set' : '${fmtRCents(e.ratePerHour)}/hr', () => editPayAmount(ctx,
                      title: 'Tariff for ${e.displayName}', label: 'Rate per hour', current: e.ratePerHour, mustBePositive: true,
                      save: (v) => data.employeesRepo.updatePay(e.id, ratePerHour: v))),
                  row(Icons.account_balance_wallet_outlined, 'Loan repayment', fmtR(e.loanDeduction ?? 0), () => editPayAmount(ctx,
                      title: 'Loan repayment -- ${e.displayName}', label: 'Amount to take off each pay', current: e.loanDeduction, mustBePositive: false,
                      save: (v) => data.employeesRepo.updatePay(e.id, loanDeduction: v))),
                  row(Icons.house_outlined, 'Rent', fmtR(e.rentDeduction ?? 0), () => editPayAmount(ctx,
                      title: 'Rent -- ${e.displayName}', label: 'Rent to take off each pay', current: e.rentDeduction, mustBePositive: false,
                      save: (v) => data.employeesRepo.updatePay(e.id, rentDeduction: v))),
                  const Divider(),
                  Row(children: [
                    Expanded(child: Text('Extra pay', style: Theme.of(ctx).textTheme.titleMedium)),
                    TextButton.icon(onPressed: () => addExtraPay(ctx, data.repo, e, payUpTo), icon: const Icon(Icons.add), label: const Text('Add')),
                  ]),
                  if (extras.isEmpty) const Text('None', style: TextStyle(color: NaniniColors.muted)),
                  for (final x in extras)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(x.isHours ? '${x.description}: ${x.hours} h × ${fmtRCents(x.rate)}' : x.description),
                      subtitle: Text(fmtDateDisplay(x.date)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(fmtR(x.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: NaniniColors.red),
                          onPressed: () async {
                            final ok = await confirmDialog(ctx, message: 'Remove ${x.description} (${fmtR(x.amount)})?');
                            if (ok && ctx.mounted) await trySave(ctx, () => data.repo.deleteExtra(x.id));
                          },
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );

Future<void> addExtraPay(BuildContext context, HoursRepository repo, Employee e, DateTime payUpTo) async {
  var byHours = false;
  final descCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  final hoursCtrl = TextEditingController();
  final rateCtrl = TextEditingController();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final h = parseNum(hoursCtrl.text) ?? 0;
        final r = parseNum(rateCtrl.text) ?? 0;
        return AlertDialog(
          title: dialogTitleWithError('Extra pay -- ${e.displayName}', error),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Amount')),
                      ButtonSegment(value: true, label: Text('Hours at a rate')),
                    ],
                    selected: {byHours},
                    onSelectionChanged: (v) => setLocal(() => byHours = v.first),
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: 'What for', hintText: byHours ? 'e.g. Sunday work' : 'e.g. Bonus'),
                  ),
                  const SizedBox(height: 10),
                  if (!byHours)
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Amount', prefixText: 'R '),
                    )
                  else ...[
                    TextField(
                      controller: hoursCtrl,
                      onChanged: (_) => setLocal(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Hours'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: rateCtrl,
                      onChanged: (_) => setLocal(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Rate per hour',
                        prefixText: 'R ',
                        helperText: e.ratePerHour == null ? null : 'Normal tariff ${fmtRCents(e.ratePerHour)}/hr',
                      ),
                    ),
                    if (h > 0 && r > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('= ${fmtRCents(h * r)}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  ],
                  const SizedBox(height: 8),
                  Text('Paid with the next pay (up to ${fmtDateDisplay(toDateStr(payUpTo))}).', style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final desc = descCtrl.text.trim();
                final amount = byHours ? h * r : parseNum(amountCtrl.text) ?? 0;
                if (desc.isEmpty) return setLocal(() => error = 'Type what it is for.');
                if (byHours && (h <= 0 || r <= 0)) return setLocal(() => error = 'Type the hours and the rate.');
                if (!byHours && amount == 0) return setLocal(() => error = 'Type the amount.');
                try {
                  await repo.addExtra(
                    employeeId: e.id,
                    farmId: e.farmId,
                    date: toDateStr(payUpTo),
                    description: desc,
                    hours: byHours ? h : null,
                    rate: byHours ? r : null,
                    amount: (amount * 100).roundToDouble() / 100,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (err) {
                  setLocal(() => error = friendlyDbError(err));
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    ),
  );
}


Future<void> editPayAmount(
  BuildContext context, {
  required String title,
  required String label,
  required double? current,
  required bool mustBePositive,
  required Future<void> Function(double) save,
}) async {
  final ctrl = TextEditingController(text: current == null || current == 0 ? '' : _plain(current));
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: dialogTitleWithError(title, error),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, prefixText: 'R '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final v = ctrl.text.trim().isEmpty && !mustBePositive ? 0.0 : parseNum(ctrl.text);
              if (v == null || v < 0 || (mustBePositive && v <= 0)) {
                setLocal(() => error = mustBePositive ? 'Type the rate, e.g. 25,50' : 'Type an amount (0 for none)');
                return;
              }
              try {
                await save(v);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                setLocal(() => error = friendlyDbError(e));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

String _plain(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2).replaceAll('.', ',');
