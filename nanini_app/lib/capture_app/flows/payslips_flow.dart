import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/capture/capture_models.dart';
import '../../features/employees/employees_models.dart';
import '../../features/hours/hours_models.dart';
import '../../features/hours/pay_run.dart';
import '../../theme/nanini_theme.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../pay_ref.dart';
import '../ref_data.dart';

enum _S { farm, hours, tariffs, extras, deductions, check }

/// Payslips: a farm manager's check before pay (was Hours > Work in the
/// hub). For one farm: every worker's hours since their last pay, their
/// tariff, extra pay, then deductions (tuck shop debt, loan, rent). Changes
/// and new extra pay are sent to the hub (Hours) to approve; the office then
/// runs payroll from Summary.
class PayslipsFlow extends StatefulWidget {
  const PayslipsFlow({super.key});
  @override
  State<PayslipsFlow> createState() => _PayslipsFlowState();
}

class _PayslipsFlowState extends State<PayslipsFlow> {
  RefItem? farm;
  int i = 0;

  /// Changes typed here, per worker (not yet approved).
  final rate = <String, double>{};
  final rent = <String, double>{};
  final loan = <String, double>{};
  final newExtras = <PayExtra>[];

  static const steps = _S.values;

  void next() => setState(() => i = (i + 1).clamp(0, steps.length - 1));
  void back() => i == 0 ? Navigator.of(context).pop() : setState(() => i--);
  void _need(String msg) => showNeed(context, msg);

  bool get changed => rate.isNotEmpty || rent.isNotEmpty || loan.isNotEmpty || newExtras.isNotEmpty;

  List<PayLine> _lines(PayRef pay) {
    final emps = [
      for (final e in pay.employees) e.copyWithPay(ratePerHour: rate[e.id], rentDeduction: rent[e.id], loanDeduction: loan[e.id]),
    ];
    return pay.linesFor(farm!.id, employees: emps, extras: [...pay.extras, ...newExtras]);
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<CaptureStore>().ref;
    final pay = ref.pay;
    final s = steps[i];
    StepPage page(String q, Widget child, {VoidCallback? onNext, String? hint, String nextLabel = 'NEXT', IconData nextIcon = Icons.arrow_forward}) =>
        StepPage(task: 'Payslips', step: i + 1, steps: steps.length, question: q, hint: hint, onBack: back, onNext: onNext, nextLabel: nextLabel, nextIcon: nextIcon, child: child);

    if (pay == null) {
      return page(
        'Payslips',
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('The pay lists are not on this phone yet. Connect to Wi-Fi and press the refresh button on the first screen.',
              style: TextStyle(fontSize: 20)),
        ),
      );
    }
    final lines = farm == null ? <PayLine>[] : _lines(pay);

    switch (s) {
      case _S.farm:
        final farms = ref.farms.where((f) => pay.employees.any((e) => e.farmId == f.id)).toList();
        final noFarm = pay.employees.where((e) => e.farmId == null || !ref.farms.any((f) => f.id == e.farmId)).toList();
        return page(
          'Which farm?',
          ListView(children: [
            for (final f in farms)
              () {
                final fl = pay.linesFor(f.id);
                final hours = fl.fold<double>(0, (a, l) => a + l.hours);
                return BigChoice(
                  icon: Icons.landscape,
                  label: f.name,
                  sub: '${fl.length} workers · ${fmtNum(_r(hours))} h since the last pay',
                  selected: farm?.id == f.id,
                  onTap: () {
                    setState(() => farm = f);
                    next();
                  },
                );
              }(),
            if (noFarm.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('${noFarm.length} worker${noFarm.length == 1 ? ' has' : 's have'} no farm in Employees > List: '
                      '${noFarm.map((e) => e.displayName).join(', ')}',
                      style: const TextStyle(fontSize: 16, color: NaniniColors.red, fontWeight: FontWeight.w600)),
                ),
              ),
          ]),
        );
      case _S.hours:
        final total = lines.fold<double>(0, (a, l) => a + l.hours);
        return page(
          'Hours since the last pay',
          ListView(children: [
            _farmTotal('${lines.length} workers · ${fmtNum(_r(total))} h'),
            for (final l in lines)
              _row(
                l.employee.displayName,
                l.since == null ? 'Not paid here yet' : 'Since ${l.since}',
                '${fmtNum(_r(l.hours))} h${l.kg > 0 ? '\n${fmtNum(_r(l.kg))} kg' : ''}',
                dim: l.hours == 0 && l.kg == 0,
              ),
          ]),
          hint: 'Hours wrong or missing? Fix them with the HOURS button first.',
          onNext: next,
        );
      case _S.tariffs:
        return page(
          'Tariff per hour',
          ListView(children: [
            for (final l in lines)
              BigChoice(
                icon: l.tariff > 0 ? Icons.payments_outlined : Icons.warning_amber,
                color: rate.containsKey(l.employee.id) ? NaniniColors.amber : (l.tariff > 0 ? NaniniColors.green : NaniniColors.red),
                label: l.employee.displayName,
                sub: l.tariff > 0 ? 'R ${fmtNum(l.tariff)} per hour${rate.containsKey(l.employee.id) ? ' (changed)' : ''}' : 'NO TARIFF -- tap to set',
                onTap: () async {
                  final v = await _askNumber('Tariff for ${l.employee.displayName}?', prefix: 'R', start: l.tariff);
                  if (v != null) setState(() => rate[l.employee.id] = v);
                },
              ),
          ]),
          hint: 'Tap a name to change the tariff',
          onNext: () {
            final missing = lines.where((l) => l.hours > 0 && l.tariff <= 0).map((l) => l.employee.displayName).toList();
            if (missing.isNotEmpty) return _need('Set a tariff for ${missing.join(', ')}');
            next();
          },
        );
      case _S.extras:
        return page(
          'Extra pay',
          ListView(children: [
            for (final l in lines)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 5),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(child: Text(l.employee.displayName, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700))),
                        TextButton.icon(
                          onPressed: () => _addExtra(l.employee),
                          icon: const Icon(Icons.add_circle, size: 30, color: NaniniColors.green),
                          label: const Text('ADD', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      for (final x in l.extras)
                        Row(children: [
                          Expanded(
                            child: Text(x.isHours ? '${x.description}: ${fmtNum(x.hours!)} h × R ${fmtNum(x.rate ?? 0)}' : x.description,
                                style: const TextStyle(fontSize: 18)),
                          ),
                          Text('R ${fmtNum(x.amount)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          if (newExtras.contains(x))
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: NaniniColors.red),
                              onPressed: () => setState(() => newExtras.remove(x)),
                            )
                          else
                            const SizedBox(width: 12),
                        ]),
                    ],
                  ),
                ),
              ),
          ]),
          hint: 'A bonus, or hours at another rate (e.g. Sunday work)',
          onNext: next,
        );
      case _S.deductions:
        return page(
          'Deductions',
          ListView(children: [
            for (final l in lines)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 5),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l.employee.displayName, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                      _deduction(Icons.storefront_outlined, 'Tuck shop', l.tuckshop, null),
                      _deduction(Icons.account_balance_wallet_outlined, 'Loan', l.loan, () async {
                        final v = await _askNumber('Loan to take off ${l.employee.displayName}?', prefix: 'R', start: l.loan, allowZero: true);
                        if (v != null) setState(() => loan[l.employee.id] = v);
                      }),
                      _deduction(Icons.house_outlined, 'Rent', l.rent, () async {
                        final v = await _askNumber('Rent for ${l.employee.displayName}?', prefix: 'R', start: l.rent, allowZero: true);
                        if (v != null) setState(() => rent[l.employee.id] = v);
                      }),
                    ],
                  ),
                ),
              ),
          ]),
          hint: 'Tap Loan or Rent to change it',
          onNext: next,
        );
      case _S.check:
        final byId = {for (final e in pay.employees) e.id: e};
        String name(String id) => byId[id]?.displayName ?? '';
        return page(
          'Is this right?',
          ListView(children: [
            CheckLine(icon: Icons.landscape, text: farm?.name ?? ''),
            if (!changed) const CheckLine(icon: Icons.check_circle, color: NaniniColors.green, text: 'Nothing changed -- the office sees the hours as they are'),
            for (final e in rate.entries) CheckLine(icon: Icons.payments_outlined, text: '${name(e.key)}: tariff R ${fmtNum(e.value)}/h'),
            for (final x in newExtras) CheckLine(icon: Icons.add_card_outlined, color: NaniniColors.green, text: '${name(x.employeeId)}: ${x.description} R ${fmtNum(x.amount)}'),
            for (final e in loan.entries) CheckLine(icon: Icons.account_balance_wallet_outlined, text: '${name(e.key)}: loan R ${fmtNum(e.value)}'),
            for (final e in rent.entries) CheckLine(icon: Icons.house_outlined, text: '${name(e.key)}: rent R ${fmtNum(e.value)}'),
          ]),
          hint: changed ? 'If something is wrong, press BACK' : null,
          nextLabel: changed ? 'SEND' : 'DONE',
          nextIcon: changed ? Icons.send : Icons.check,
          onNext: () => changed ? _save(pay) : Navigator.of(context).pop(),
        );
    }
  }

  Widget _farmTotal(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: NaniniColors.rust)),
      );

  Widget _row(String title, String sub, String trailing, {bool dim = false}) => Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          title: Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: dim ? NaniniColors.muted : NaniniColors.ink)),
          subtitle: Text(sub, style: const TextStyle(fontSize: 15)),
          trailing: Text(trailing, textAlign: TextAlign.right, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: dim ? NaniniColors.muted : NaniniColors.ink)),
        ),
      );

  Widget _deduction(IconData icon, String label, double amount, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, size: 26, color: NaniniColors.muted),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 18))),
            Text(amount > 0 ? 'R ${fmtNum(_r(amount))}' : 'none', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (onTap != null) const Icon(Icons.edit, size: 22, color: NaniniColors.rust) else const SizedBox(width: 22),
          ]),
        ),
      );

  Future<double?> _askNumber(String question, {String? prefix, String? unit, double start = 0, bool allowZero = false}) =>
      Navigator.of(context).push<double>(MaterialPageRoute(
        builder: (_) => _NumberPage(question: question, prefix: prefix, unit: unit, start: start, allowZero: allowZero),
      ));

  Future<void> _addExtra(Employee e) async {
    final byHours = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Extra pay for ${e.displayName}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            BigChoice(icon: Icons.payments_outlined, label: 'AN AMOUNT', sub: 'e.g. a bonus', onTap: () => Navigator.pop(ctx, false)),
            BigChoice(icon: Icons.schedule, label: 'HOURS AT A RATE', sub: 'e.g. Sunday work', onTap: () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    if (byHours == null || !mounted) return;
    final desc = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => _TextPage(question: 'What is it for?', suggestions: byHours ? const ['Sunday work', 'Public holiday', 'Overtime'] : const ['Bonus', 'Allowance']),
    ));
    if (desc == null || !mounted) return;
    double? hours, rate, amount;
    if (byHours) {
      hours = await _askNumber('How many hours?', unit: 'h');
      if (hours == null || !mounted) return;
      rate = await _askNumber('Rate per hour?', prefix: 'R', start: e.ratePerHour ?? 0);
      if (rate == null) return;
      amount = (hours * rate * 100).roundToDouble() / 100;
    } else {
      amount = await _askNumber('How much?', prefix: 'R');
      if (amount == null) return;
    }
    setState(() => newExtras.add(PayExtra(
          id: 'new-${DateTime.now().microsecondsSinceEpoch}',
          employeeId: e.id,
          farmId: e.farmId,
          date: dayStr(DateTime.now()),
          description: desc,
          hours: hours,
          rate: rate,
          amount: amount!,
        )));
  }

  Future<void> _save(PayRef pay) async {
    final store = context.read<CaptureStore>();
    final byId = {for (final e in pay.employees) e.id: e};
    final ids = {...rate.keys, ...rent.keys, ...loan.keys};
    await store.add(
      CaptureModule.payCheck,
      {
        'farm_id': farm!.id,
        'farm_name': farm!.name,
        'changes': [
          for (final id in ids)
            {
              'employee_id': id,
              'employee_name': byId[id]?.displayName ?? '',
              'rate_per_hour': ?rate[id],
              'rent_deduction': ?rent[id],
              'loan_deduction': ?loan[id],
            },
        ],
        'extras': [
          for (final x in newExtras)
            {
              'employee_id': x.employeeId,
              'employee_name': byId[x.employeeId]?.displayName ?? '',
              'date': x.date,
              'description': x.description,
              'hours': ?x.hours,
              'rate': ?x.rate,
              'amount': x.amount,
            },
        ],
      },
      'Payslips ${farm!.name}: ${ids.length + newExtras.length} changes',
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(task: 'payslip check', another: (_) => const PayslipsFlow())));
  }
}

double _r(double v) => (v * 100).roundToDouble() / 100;

/// One number on its own screen (a tariff, hours, an amount).
class _NumberPage extends StatefulWidget {
  const _NumberPage({required this.question, this.prefix, this.unit, this.start = 0, this.allowZero = false});
  final String question;
  final String? prefix;
  final String? unit;
  final double start;
  final bool allowZero;
  @override
  State<_NumberPage> createState() => _NumberPageState();
}

class _NumberPageState extends State<_NumberPage> {
  late String value = widget.start > 0 ? fmtNum(widget.start).replaceAll(',', '.') : '';

  /// The first key typed replaces the number shown (the current tariff,
  /// loan...) rather than adding onto it.
  bool fresh = true;

  @override
  Widget build(BuildContext context) => StepPage(
        task: 'Payslips',
        step: 1,
        steps: 1,
        question: widget.question,
        onBack: () => Navigator.pop(context),
        nextLabel: 'OK',
        nextIcon: Icons.check,
        onNext: () {
          final v = padValue(value) ?? 0;
          if (v < 0 || (v == 0 && !widget.allowZero)) return showNeed(context, 'Type the number');
          Navigator.pop(context, v);
        },
        child: NumberPad(
          value: value,
          prefix: widget.prefix,
          unit: widget.unit,
          onChanged: (v) => setState(() {
            if (fresh && v.length > value.length && v.startsWith(value)) v = v.substring(value.length);
            fresh = false;
            value = v;
          }),
        ),
      );
}

/// A short text (what extra pay is for), with quick choices.
class _TextPage extends StatefulWidget {
  const _TextPage({required this.question, this.suggestions = const []});
  final String question;
  final List<String> suggestions;
  @override
  State<_TextPage> createState() => _TextPageState();
}

class _TextPageState extends State<_TextPage> {
  final ctrl = TextEditingController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StepPage(
        task: 'Payslips',
        step: 1,
        steps: 1,
        question: widget.question,
        onBack: () => Navigator.pop(context),
        nextLabel: 'OK',
        nextIcon: Icons.check,
        onNext: () => ctrl.text.trim().isEmpty ? showNeed(context, 'Tap a choice or type it') : Navigator.pop(context, ctrl.text.trim()),
        child: ListView(children: [
          for (final s in widget.suggestions) BigChoice(label: s, onTap: () => Navigator.pop(context, s)),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 22),
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Or type it here'),
          ),
        ]),
      );
}
