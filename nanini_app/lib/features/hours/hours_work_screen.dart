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

enum WorkStep { hours, tariff, deductions }

/// Hours > Work: the farm managers' check before pay, in three steps --
/// hours worked since the last pay (per worker and per farm), each worker's
/// tariff, then deductions (tuck shop debt, loan repayment). The Summary tab
/// adds it all up.
class HoursWorkScreen extends StatelessWidget {
  const HoursWorkScreen({
    super.key,
    required this.data,
    required this.lines,
    required this.scopeBar,
    required this.step,
    required this.onStep,
    required this.onDone,
  });
  final HoursData data;
  final List<PayLine> lines;
  final Widget scopeBar;
  final WorkStep step;
  final ValueChanged<WorkStep> onStep;

  /// After the last step: on to the Summary tab.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final farms = byFarm(lines, data.farms);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<WorkStep>(
            segments: const [
              ButtonSegment(value: WorkStep.hours, label: Text('1 Hours', maxLines: 1)),
              ButtonSegment(value: WorkStep.tariff, label: Text('2 Tariff', maxLines: 1)),
              ButtonSegment(value: WorkStep.deductions, label: Text('3 Deductions', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            selected: {step},
            onSelectionChanged: (s) => onStep(s.first),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
          ),
        ),
        scopeBar,
        Expanded(
          child: !data.loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    if (step == WorkStep.hours)
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
                    if (step == WorkStep.hours) const SizedBox(height: 8),
                    if (lines.isEmpty) const EmptyPayNote(),
                    for (final (farm, farmLines) in farms)
                      switch (step) {
                        WorkStep.hours => _hoursSection(context, farm, farmLines),
                        WorkStep.tariff => _tariffSection(context, farm, farmLines),
                        WorkStep.deductions => _deductionSection(context, farm, farmLines),
                      },
                  ],
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: switch (step) {
                  WorkStep.hours => () => onStep(WorkStep.tariff),
                  WorkStep.tariff => () => onStep(WorkStep.deductions),
                  WorkStep.deductions => onDone,
                },
                icon: const Icon(Icons.arrow_forward),
                label: Text(switch (step) {
                  WorkStep.hours => 'Next: check tariffs',
                  WorkStep.tariff => 'Next: deductions',
                  WorkStep.deductions => 'Done: see summary',
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Step 1: hours per worker, and per farm ---

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

  // --- Step 2: tariff per worker ---

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

  // --- Step 3: tuck shop debt and loan repayment ---

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
                if (l.rent > 0) Text('Rent ${fmtR(l.rent)} (from Employee List)', style: const TextStyle(color: NaniniColors.muted, fontSize: 13)),
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
