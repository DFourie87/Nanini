import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import 'hours_data.dart';
import 'hours_log_screen.dart';
import 'pay_run.dart';
import 'pay_widgets.dart';

enum WorkStep { farm, hours, tariff, extras, deductions }

/// Hours > Work: a farm manager's check before pay, one step at a time --
/// choose the farm, then its hours worked since the last pay (per worker and
/// in total), each worker's tariff, extra pay (a set amount or hours at
/// another rate), then deductions (tuck shop debt, loan, rent). BACK / NEXT at the bottom; the Summary tab adds it all up.
class HoursWorkScreen extends StatelessWidget {
  const HoursWorkScreen({
    super.key,
    required this.data,
    required this.allLines,
    required this.farmId,
    required this.onFarm,
    required this.payUpTo,
    required this.onPayUpTo,
    required this.step,
    required this.onStep,
    required this.onDone,
  });
  final HoursData data;

  /// Every farm's pay lines (the chosen farm's are picked out here).
  final List<PayLine> allLines;
  final String? farmId;
  final ValueChanged<String> onFarm;
  final DateTime payUpTo;
  final ValueChanged<DateTime> onPayUpTo;
  final WorkStep step;
  final ValueChanged<WorkStep> onStep;

  /// After the last step: on to the Summary tab.
  final VoidCallback onDone;

  static const _titles = {
    WorkStep.farm: 'Which farm?',
    WorkStep.hours: 'Hours worked',
    WorkStep.tariff: 'Tariffs',
    WorkStep.extras: 'Extra pay',
    WorkStep.deductions: 'Deductions',
  };

  @override
  Widget build(BuildContext context) {
    final farm = data.farms.where((f) => f.id == farmId).firstOrNull;
    // No farm chosen yet (or "All farms" picked on Summary): start at the farm.
    final s = farm == null ? WorkStep.farm : step;
    final lines = allLines.where((l) => l.employee.farmId == farmId).toList();
    final n = WorkStep.values.indexOf(s);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Step ${n + 1} of ${WorkStep.values.length}${farm == null ? '' : ' · ${farmShort(farm)}'}',
                  style: const TextStyle(color: NaniniColors.muted, fontWeight: FontWeight.w600)),
              Text(_titles[s]!, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: (n + 1) / WorkStep.values.length, color: NaniniColors.rust, backgroundColor: NaniniColors.disabledBg),
            ],
          ),
        ),
        Expanded(
          child: !data.loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    if (s == WorkStep.farm) ..._farmStep(context),
                    if (s == WorkStep.hours)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => Scaffold(appBar: const NaniniAppBar(title: 'Add hours'), body: HoursLogScreen(repo: data.repo)),
                          )),
                          icon: const Icon(Icons.add),
                          label: const Text('Add hours'),
                        ),
                      ),
                    if (s == WorkStep.hours) const SizedBox(height: 8),
                    if (s == WorkStep.extras) ..._extrasTop(context, farm!, lines),
                    if (s != WorkStep.farm && lines.isEmpty) const EmptyPayNote(),
                    if (s != WorkStep.farm && lines.isNotEmpty)
                      switch (s) {
                        WorkStep.hours => _hoursSection(context, farm, lines),
                        WorkStep.tariff => _tariffSection(context, farm, lines),
                        WorkStep.extras => _extrasSection(context, farm, lines),
                        _ => _deductionSection(context, farm, lines),
                      },
                  ],
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: n == 0 ? null : () => onStep(WorkStep.values[n - 1]),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('BACK'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: switch (s) {
                      WorkStep.farm => farm == null ? null : () => onStep(WorkStep.hours),
                      WorkStep.deductions => onDone,
                      _ => () => onStep(WorkStep.values[n + 1]),
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(s == WorkStep.deductions ? 'SUMMARY' : 'NEXT'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Step 1: the farm, and pay up to which day ---

  List<Widget> _farmStep(BuildContext context) => [
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(context: context, initialDate: payUpTo, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (picked != null) onPayUpTo(picked);
          },
          icon: const Icon(Icons.event),
          label: Text('Since last pay, up to ${fmtDateDisplay(toDateStr(payUpTo))}'),
        ),
        const SizedBox(height: 12),
        for (final f in data.farms)
          () {
            final fl = allLines.where((l) => l.employee.farmId == f.id);
            final workers = fl.where((l) => l.hours > 0 || l.kg > 0).length;
            final hours = fl.fold<double>(0, (a, l) => a + l.hours);
            final selected = f.id == farmId;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: selected ? NaniniColors.rust : NaniniColors.line, width: selected ? 2.5 : 1),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Icon(Icons.agriculture, size: 32, color: selected ? NaniniColors.rust : NaniniColors.muted),
                title: Text(farmShort(f), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                subtitle: Text('$workers worker${workers == 1 ? '' : 's'} · ${fmtHours(_round(hours))} since the last pay'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () {
                  onFarm(f.id);
                  onStep(WorkStep.hours);
                },
              ),
            );
          }(),
      ];

  // --- Step 2: hours per worker, and the farm's total ---

  Widget _hoursSection(BuildContext context, Farm? farm, List<PayLine> farmLines) {
    final hours = farmLines.fold<double>(0, (s, l) => s + l.hours);
    final kg = farmLines.fold<double>(0, (s, l) => s + l.kg);
    final workers = farmLines.where((l) => l.hours > 0 || l.kg > 0).length;
    return FarmSection(
      title: farmShort(farm),
      totals: '$workers worker${workers == 1 ? '' : 's'} · ${fmtHours(_round(hours))}${kg > 0 ? ' · ${_fmtKg(kg)}' : ''}',
      children: [
        for (final l in farmLines)
          ListTile(
            title: Text(l.employee.displayName),
            subtitle: Text(_sinceText(l)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(fmtHours(_round(l.hours)), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: l.hours > 0 ? NaniniColors.ink : NaniniColors.muted)),
                if (l.kg > 0) Text(_fmtKg(l.kg), style: const TextStyle(color: NaniniColors.muted)),
              ],
            ),
            onTap: () => _showDays(context, l),
          ),
      ],
    );
  }

  String _sinceText(PayLine l) {
    final days = {...l.entries.map((e) => e.date), ...l.kgEntries.map((k) => k.date)}.length;
    final since = l.since == null ? 'not paid here yet' : 'since ${fmtDateDisplay(l.since)}';
    return '$days day${days == 1 ? '' : 's'} · $since';
  }

  void _showDays(BuildContext context, PayLine l) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(l.employee.displayName, style: Theme.of(ctx).textTheme.titleLarge),
            Text('${fmtHours(_round(l.hours))}${l.kg > 0 ? ' · ${_fmtKg(l.kg)}' : ''} · ${_sinceText(l)}',
                style: const TextStyle(color: NaniniColors.muted)),
            const SizedBox(height: 8),
            for (final e in l.entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(fmtDateDisplay(e.date)),
                subtitle: e.rate > 0 ? Text('Logged at ${fmtRCents(e.rate)}/hr') : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(fmtHours(_round(e.hours)), style: const TextStyle(fontWeight: FontWeight.w700)),
                    IconButton(
                      tooltip: 'Delete this day',
                      icon: const Icon(Icons.delete_outline, color: NaniniColors.red),
                      onPressed: () async {
                        final ok = await confirmDialog(ctx, message: 'Delete ${fmtHours(_round(e.hours))} on ${fmtDateDisplay(e.date)} for ${l.employee.displayName}?');
                        if (!ok || !ctx.mounted) return;
                        if (await trySave(ctx, () => data.repo.deleteEntry(e.id)) && ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
              ),
            for (final k in l.kgEntries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${fmtDateDisplay(k.date)} · picking'),
                subtitle: Text('${fmtRCents(k.ratePerKg)}/kg'),
                trailing: Text(_fmtKg(k.kg), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            if (l.entries.isEmpty && l.kgEntries.isEmpty)
              const Padding(padding: EdgeInsets.all(12), child: Text('No hours since the last pay (only tuck shop debt).')),
          ],
        ),
      ),
    );
  }

  // --- Step 3: tariff per worker ---

  Widget _tariffSection(BuildContext context, Farm? farm, List<PayLine> farmLines) {
    final missing = farmLines.where((l) => l.hours > 0 && l.tariff <= 0).length;
    return FarmSection(
      title: farmShort(farm),
      totals: missing > 0 ? '$missing without tariff' : fmtR(farmLines.fold<double>(0, (s, l) => s + l.gross)),
      children: [
        for (final l in farmLines)
          ListTile(
            title: Text(l.employee.displayName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (l.hours > 0)
                  Text(l.tariff > 0 ? '${fmtHours(_round(l.hours))} × ${fmtRCents(l.tariff)} = ${fmtR(l.hoursPay)}' : '${fmtHours(_round(l.hours))} -- no tariff set',
                      style: TextStyle(color: l.tariff > 0 ? NaniniColors.muted : NaniniColors.red, fontWeight: l.tariff > 0 ? null : FontWeight.w700)),
                if (l.kg > 0) Text('${_fmtKg(l.kg)} picked = ${fmtR(l.kgPay)}', style: const TextStyle(color: NaniniColors.muted)),
                if (l.hours > 0 && l.tariff > 0 && l.tariffDiffers)
                  const Text('Some days were logged at another rate -- pay uses this tariff.', style: TextStyle(color: NaniniColors.amber, fontSize: 12)),
              ],
            ),
            trailing: TextButton.icon(
              onPressed: () => _editAmount(
                context,
                title: 'Tariff for ${l.employee.displayName}',
                label: 'Rate per hour',
                current: l.employee.ratePerHour,
                mustBePositive: true,
                save: (v) => data.employeesRepo.updatePay(l.employee.id, ratePerHour: v),
              ),
              icon: const Icon(Icons.edit, size: 18),
              label: Text(l.tariff > 0 ? '${fmtRCents(l.tariff)}/hr' : 'Set', style: TextStyle(color: l.tariff > 0 ? null : NaniniColors.red)),
            ),
          ),
      ],
    );
  }

  // --- Step 4: extra pay (set amounts, hours at another rate) ---

  List<Widget> _extrasTop(BuildContext context, Farm farm, List<PayLine> lines) {
    final others = (data.employees ?? []).where((e) => e.farmId == farm.id && !lines.any((l) => l.employee.id == e.id)).toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return [
      const Text('Added to the gross pay: a bonus or allowance, or hours at a different rate (e.g. Sunday work).',
          style: TextStyle(color: NaniniColors.muted)),
      const SizedBox(height: 8),
      if (others.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              final e = await showDialog<Employee>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('Extra pay for'),
                  children: [for (final e in others) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e), child: Text(e.displayName))],
                ),
              );
              if (e != null && context.mounted) await _addExtra(context, e);
            },
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Someone not listed below'),
          ),
        ),
      const SizedBox(height: 8),
    ];
  }

  Widget _extrasSection(BuildContext context, Farm? farm, List<PayLine> farmLines) {
    final total = farmLines.fold<double>(0, (s, l) => s + l.extraPay);
    return FarmSection(
      title: farmShort(farm),
      totals: 'Extra ${fmtR(total)}',
      children: [
        for (final l in farmLines)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(l.employee.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                    TextButton.icon(onPressed: () => _addExtra(context, l.employee), icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
                  ],
                ),
                for (final x in l.extras)
                  Row(
                    children: [
                      const Icon(Icons.add_card_outlined, size: 20, color: NaniniColors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(x.isHours ? '${x.description}: ${fmtHours(_round(x.hours!))} × ${fmtRCents(x.rate)}' : x.description),
                      ),
                      Text(fmtR(x.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline, color: NaniniColors.red),
                        onPressed: () async {
                          final ok = await confirmDialog(context, message: 'Remove ${x.description} (${fmtR(x.amount)}) for ${l.employee.displayName}?');
                          if (ok && context.mounted) await trySave(context, () => data.repo.deleteExtra(x.id));
                        },
                      ),
                    ],
                  ),
                if (l.extras.isEmpty) const Text('No extra pay', style: TextStyle(color: NaniniColors.muted)),
                const Divider(height: 16),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _addExtra(BuildContext context, Employee e) async {
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
                    await data.repo.addExtra(
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

  // --- Step 5: tuck shop debt, loan and rent ---

  Widget _deductionSection(BuildContext context, Farm? farm, List<PayLine> farmLines) {
    final shop = farmLines.fold<double>(0, (s, l) => s + l.tuckshop);
    final loans = farmLines.fold<double>(0, (s, l) => s + l.loan);
    return FarmSection(
      title: farmShort(farm),
      totals: 'Tuck ${fmtR(shop)} · Loans ${fmtR(loans)}',
      children: [
        for (final l in farmLines)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.employee.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Row(
                  children: [
                    const Icon(Icons.storefront_outlined, size: 20, color: NaniniColors.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l.tuckshop > 0 ? 'Tuck shop debt: ${fmtR(l.tuckshop)}' : 'No tuck shop debt')),
                    if (l.purchases.isNotEmpty) TextButton(onPressed: () => _showPurchases(context, l), child: const Text('Check')),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, size: 20, color: NaniniColors.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l.loan > 0 ? 'Loan repayment: ${fmtR(l.loan)}' : 'No loan repayment')),
                    TextButton.icon(
                      onPressed: () => _editAmount(
                        context,
                        title: 'Loan repayment -- ${l.employee.displayName}',
                        label: 'Amount to take off this pay',
                        current: l.employee.loanDeduction,
                        mustBePositive: false,
                        save: (v) => data.employeesRepo.updatePay(l.employee.id, loanDeduction: v),
                      ),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Enter'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.house_outlined, size: 20, color: NaniniColors.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l.rent > 0 ? 'Rent: ${fmtR(l.rent)}' : 'No rent')),
                    TextButton.icon(
                      onPressed: () => _editAmount(
                        context,
                        title: 'Rent -- ${l.employee.displayName}',
                        label: 'Rent to take off each pay',
                        current: l.employee.rentDeduction,
                        mustBePositive: false,
                        save: (v) => data.employeesRepo.updatePay(l.employee.id, rentDeduction: v),
                      ),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Enter'),
                    ),
                  ],
                ),
                const Divider(height: 16),
              ],
            ),
          ),
      ],
    );
  }

  void _showPurchases(BuildContext context, PayLine l) {
    String itemName(String? id) => data.items.where((i) => i.id == id).firstOrNull?.name ?? 'Item';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('${l.employee.displayName} -- tuck shop', style: Theme.of(ctx).textTheme.titleLarge),
            Text('Not yet taken off a pay: ${fmtR(l.tuckshop)}', style: const TextStyle(color: NaniniColors.muted)),
            const SizedBox(height: 8),
            for (final p in l.purchases)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.itemId != null ? '${fmtNumQty(p.qty)} × ${itemName(p.itemId)}' : (p.note?.isNotEmpty == true ? p.note! : 'Purchase')),
                subtitle: Text(fmtDateDisplay(p.date)),
                trailing: Text(fmtRCents(p.revenue), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editAmount(
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
}

double _round(double v) => (v * 100).roundToDouble() / 100;
String _fmtKg(double kg) => '${kg == kg.roundToDouble() ? kg.round() : kg.toStringAsFixed(1)} kg';
String _plain(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2).replaceAll('.', ',');
String fmtNumQty(double? q) => q == null ? '1' : (q == q.roundToDouble() ? '${q.round()}' : '$q');
