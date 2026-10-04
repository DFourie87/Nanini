import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/capture/capture_models.dart';
import '../../features/employees/employees_models.dart';
import '../../features/hours/hours_models.dart';
import '../../features/hours/pay_run.dart';
import '../../features/tuckshop/tuckshop_models.dart';
import '../../theme/nanini_theme.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../pay_ref.dart';
import '../ref_data.dart';
import '../../core/run_once.dart';

enum _S { farm, hours, tariffs, extras, deductions, tax, check }

/// Payslips: a farm manager's check before pay (was Hours > Work in the
/// hub). For one farm: every worker's hours since their last pay, their
/// tariff, extra pay, deductions (tuck shop debt per shop, loan, rent), then
/// PAYE and UIF (whether UIF is taken off is chosen per worker).
/// Changes (including the Haaskraal tuck shop debt, which is typed in) and new
/// extra pay are sent to the hub (Hours) to approve; the office then runs
/// payroll from Summary.
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

  /// Hours since the last pay typed in, per worker, and what they were.
  final hours = <String, double>{};
  final hoursWas = <String, double>{};

  /// Haaskraal tuck shop debt typed in, per worker (replaces what's owing).
  final tuck = <String, double>{};
  final newExtras = <PayExtra>[];

  /// UIF deducted or not, changed here per worker.
  final uif = <String, bool>{};

  static const steps = _S.values;

  void next() => setState(() => i = (i + 1).clamp(0, steps.length - 1));
  void back() => i == 0 ? Navigator.of(context).pop() : setState(() => i--);
  void _need(String msg) => showNeed(context, msg);

  bool get changed => rate.isNotEmpty || rent.isNotEmpty || loan.isNotEmpty || tuck.isNotEmpty || hours.isNotEmpty || newExtras.isNotEmpty || uif.isNotEmpty;

  /// Whether UIF is taken off [e] before any change here: as chosen before
  /// (on this phone, not yet in the hub, or in the hub), else when an
  /// ID/passport is on file.
  bool _uifBefore(Employee e, RefData ref) {
    final hub = e.uifDeduct;
    final kept = context.read<CaptureStore>().rememberedPay(e.id, 'uif', hub == null ? null : (hub ? 1 : 0));
    if (kept != null) return kept > 0;
    return hub ?? (e.hasId || ref.people.any((p) => p.id == e.id && p.hasId));
  }

  /// The Haaskraal farm (its tuck shop debt is typed in on the Deductions).
  RefItem? _haaskraal(RefData ref) => ref.farms.where((f) => f.name.toLowerCase().contains('haaskraal')).firstOrNull;

  /// The shop a purchase was made at. Older purchases sold per item were
  /// saved without their shop: they're the item's shop (Limpopodraai's --
  /// Haaskraal's shop is a money total, always saved with its farm). Only a
  /// purchase with neither counts at the worker's own farm.
  String? _shop(TuckshopPurchase p, Employee e, RefData ref) {
    if (p.farmId != null) return p.farmId;
    if (p.itemId != null) {
      return ref.shopItems.where((i) => i.id == p.itemId).firstOrNull?.farmId ??
          ref.farms.where((f) => f.name.toLowerCase().contains('limpopodraai')).firstOrNull?.id ??
          e.farmId;
    }
    return e.farmId;
  }

  List<PayLine> _lines(PayRef pay, RefData ref) {
    // Typed now, else typed on this phone before (until the hub's changes).
    final store = context.read<CaptureStore>();
    final emps = [
      for (final e in pay.employees)
        e.copyWithPay(
          ratePerHour: rate[e.id] ?? store.rememberedPay(e.id, 'rate', e.ratePerHour),
          rentDeduction: rent[e.id] ?? store.rememberedPay(e.id, 'rent', e.rentDeduction),
          loanDeduction: loan[e.id] ?? store.rememberedPay(e.id, 'loan', e.loanDeduction),
          uifDeduct: uif[e.id] ?? _uifBefore(e, ref),
        ),
    ];
    // A typed Haaskraal tuck shop debt: the difference to what's owing there
    // is added as one purchase, so every total below uses the typed amount.
    final haas = _haaskraal(ref)?.id;
    final byId = {for (final e in pay.employees) e.id: e};
    final today = dayStr(DateTime.now());
    final purchases = [
      ...pay.purchases,
      for (final t in tuck.entries)
        if (byId[t.key] case final e?)
          TuckshopPurchase(
            id: 'typed-${t.key}',
            employeeId: t.key,
            revenue: t.value -
                pay.purchases
                    .where((p) => p.employeeId == t.key && p.payslipId == null && p.date.compareTo(today) <= 0 && _shop(p, e, ref) == haas)
                    .fold<double>(0, (s, p) => s + p.revenue),
            cogs: 0,
            date: today,
            farmId: haas,
          ),
    ];
    // Typed hours since the last pay: the difference as one entry today.
    final entries = [
      ...pay.entries,
      for (final h in hours.entries)
        if (byId[h.key] case final e? when h.value != hoursWas[h.key])
          () {
            final diff = h.value - (hoursWas[h.key] ?? 0);
            final r = rate[e.id] ?? store.rememberedPay(e.id, 'rate', e.ratePerHour) ?? e.ratePerHour ?? 0;
            return HoursEntry(
              id: 'typed-${h.key}',
              employeeId: h.key,
              date: today,
              hours: diff,
              rate: r,
              dailyThreshold: 9,
              otMultiplier: 1.5,
              normalHours: diff,
              otHours: 0,
              gross: diff * r,
              farmId: e.farmId,
            );
          }(),
    ];
    return pay.linesFor(farm!.id, employees: emps, extras: [...pay.extras, ...newExtras], purchases: purchases, entries: entries);
  }

  /// "Farm Haaskraal - Swartwater" -> "Haaskraal".
  static String _short(String name) {
    var n = name.replaceFirst(RegExp(r'^Farm\s+'), '');
    final dash = n.indexOf(' - ');
    if (dash > 0) n = n.substring(0, dash);
    return n.trim().isEmpty ? name : n.trim();
  }

  /// Tuck shop debt. The shop of the farm the worker is paid at always has
  /// its line (so Haaskraal's can always be typed in for its workers), plus
  /// a line for every other shop they owe at. With only their own shop's
  /// line it's a plain "Tuck shop"; with more, each is named after its farm.
  /// Only the Haaskraal shop's debt can be typed in, like the loan;
  /// Limpopodraai's comes from its till.
  List<Widget> _tuckLines(PayLine l, RefData ref) {
    final e = l.employee;
    final haas = _haaskraal(ref)?.id;
    final byShop = <String?, double>{};
    for (final p in l.purchases) {
      final shop = _shop(p, e, ref);
      byShop[shop] = (byShop[shop] ?? 0) + p.revenue;
    }
    VoidCallback? typeIn(String? shop, double amount) => shop == null || shop != haas
        ? null
        : () async {
            final v = await _askNumber('Haaskraal tuck shop debt of ${e.displayName}?', prefix: 'R', start: amount, allowZero: true);
            if (v != null) setState(() => tuck[e.id] = v);
          };
    String label(String? shop) => ref.shopFarms.any((f) => f.id == shop) ? 'Tuck shop ${_farmName(ref, shop)}' : 'Tuck shop';
    // A typed Haaskraal amount counts as owed there, even when it's 0.
    bool owes(String? s) => (byShop[s] ?? 0).abs() > 0.005 || (s == haas && tuck.containsKey(e.id));
    final own = e.farmId;
    final ownHasShop = ref.shopFarms.any((f) => f.id == own);
    final others = [for (final s in byShop.keys) if (s != own && owes(s)) s]
      ..sort((a, b) => _farmName(ref, a).compareTo(_farmName(ref, b)));
    if (others.isEmpty) {
      return [_deduction(Icons.storefront_outlined, 'Tuck shop', l.tuckshop, typeIn(own, l.tuckshop))];
    }
    return [
      if (ownHasShop || owes(own)) _deduction(Icons.storefront_outlined, label(own), byShop[own] ?? 0, typeIn(own, byShop[own] ?? 0)),
      for (final s in others) _deduction(Icons.storefront_outlined, label(s), byShop[s]!, typeIn(s, byShop[s]!)),
    ];
  }

  /// A value typed on this phone before and not yet in the hub.
  bool _sentBefore(PayRef pay, String id, String field) {
    final e = pay.employees.where((x) => x.id == id).firstOrNull;
    if (e == null) return false;
    final hub = switch (field) { 'rate' => e.ratePerHour, 'rent' => e.rentDeduction, _ => e.loanDeduction };
    final v = context.read<CaptureStore>().rememberedPay(id, field, hub);
    return v != null && v != hub;
  }

  String _farmName(RefData ref, String? id) => _short(ref.farms.where((f) => f.id == id).firstOrNull?.name ?? 'other farm');

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CaptureStore>();
    final ref = store.ref;
    // With what's sent but not yet approved worked in (hours, picking, tuck
    // shop, earlier checks), so it matches what the office will pay.
    final pay = store.payWithPending;
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
    final lines = farm == null ? <PayLine>[] : _lines(pay, ref);

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
                onTap: () => runOnce('payslips_flow.1', () async {
                  final e = l.employee;
                  final v = await _askNumber('Hours of ${e.displayName} since the last pay?', unit: 'h', start: l.hours, allowZero: true);
                  if (v == null) return;
                  setState(() {
                    hoursWas.putIfAbsent(e.id, () => l.hours);
                    hours[e.id] = v;
                  });
                }),
                changed: hours.containsKey(l.employee.id) && hours[l.employee.id] != hoursWas[l.employee.id],
                l.employee.displayName,
                [
                  l.since == null ? 'Not paid here yet' : 'Since ${l.since}',
                  if (l.entries.where((e) => e.id.startsWith('pending-')).fold<double>(0, (a, e) => a + e.hours) case final w when w.abs() > 0.001)
                    'incl. ${fmtNum(_r(w))} h still to approve',
                  // People move between farms: say where else they worked.
                  for (final f in ref.farms.where((f) => f.id != l.employee.farmId))
                    if (l.entries.where((e) => e.farmId == f.id).fold<double>(0, (a, e) => a + e.hours) case final h when h > 0)
                      'incl. ${fmtNum(_r(h))} h at ${f.name}',
                ].join('\n'),
                '${fmtNum(_r(l.hours))} h${l.kg > 0 ? '\n${fmtNum(_r(l.kg))} kg' : ''}',
                dim: l.hours == 0 && l.kg == 0,
              ),
          ]),
          hint: 'Tap a worker to change their hours since the last pay',
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
                sub: l.tariff > 0
                    ? 'R${fmtNum(l.tariff)} per hour${rate.containsKey(l.employee.id) ? ' (changed)' : _sentBefore(ref.pay!, l.employee.id, 'rate') ? ' (sent before)' : ''}'
                    : 'NO TARIFF -- tap to set',
                onTap: () => runOnce('payslips_flow.2', () async {
                  final v = await _askNumber('Tariff for ${l.employee.displayName}?', prefix: 'R', start: l.tariff);
                  if (v != null) setState(() => rate[l.employee.id] = v);
                }),
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
                          onPressed: () => runOnce('payslips_flow.3', () => _addExtra(l.employee)),
                          icon: const Icon(Icons.add_circle, size: 30, color: NaniniColors.green),
                          label: const Text('ADD', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      for (final x in l.extras)
                        Row(children: [
                          Expanded(
                            child: Text(x.isHours ? '${x.description}: ${fmtNum(x.hours!)} h × R${fmtNum(x.rate ?? 0)}' : x.description,
                                style: const TextStyle(fontSize: 18)),
                          ),
                          Text('R${fmtNum(x.amount)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                      ..._tuckLines(l, ref),
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
          hint: 'Tap a line with the pencil to change it',
          onNext: next,
        );
      case _S.tax:
        return page(
          'PAYE and UIF',
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
                      // PAYE only when the pay is over the tax threshold.
                      if (l.paye > 0.005) _deduction(Icons.account_balance_outlined, 'PAYE', l.paye, null),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: l.deductsUif,
                        title: Text('UIF${uif.containsKey(l.employee.id) ? ' (changed)' : ''}', style: const TextStyle(fontSize: 18)),
                        subtitle: Text(l.deductsUif ? 'Deducted: R${fmtNum(_r(l.uif))}' : 'Not deducted', style: const TextStyle(fontSize: 16)),
                        onChanged: (v) => setState(() {
                          final e = l.employee;
                          v == _uifBefore(pay.employees.firstWhere((x) => x.id == e.id), ref) ? uif.remove(e.id) : uif[e.id] = v;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
          ]),
          hint: 'Switch UIF on or off -- it is remembered for next time',
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
            for (final e in rate.entries) CheckLine(icon: Icons.payments_outlined, text: '${name(e.key)}: tariff R${fmtNum(e.value)}/h'),
            for (final x in newExtras) CheckLine(icon: Icons.add_card_outlined, color: NaniniColors.green, text: '${name(x.employeeId)}: ${x.description} R${fmtNum(x.amount)}'),
            for (final e in hours.entries)
              if (e.value != hoursWas[e.key])
                CheckLine(icon: Icons.schedule, text: '${name(e.key)}: ${fmtNum(_r(e.value))} h since the last pay (was ${fmtNum(_r(hoursWas[e.key] ?? 0))} h)'),
            for (final e in tuck.entries)
              CheckLine(icon: Icons.storefront_outlined, text: '${name(e.key)}: Haaskraal tuck shop R${fmtNum(e.value)}'),
            for (final e in loan.entries) CheckLine(icon: Icons.account_balance_wallet_outlined, text: '${name(e.key)}: loan R${fmtNum(e.value)}'),
            for (final e in rent.entries) CheckLine(icon: Icons.house_outlined, text: '${name(e.key)}: rent R${fmtNum(e.value)}'),
            for (final e in uif.entries) CheckLine(icon: Icons.account_balance_outlined, text: '${name(e.key)}: ${e.value ? 'UIF deducted' : 'no UIF'}'),
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

  Widget _row(String title, String sub, String trailing, {bool dim = false, VoidCallback? onTap, bool changed = false}) => Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          onTap: onTap,
          leading: onTap == null ? null : Icon(changed ? Icons.edit_note : Icons.edit, color: changed ? NaniniColors.amber : NaniniColors.rust),
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
            Text(amount > 0 ? 'R${fmtNum(_r(amount))}' : 'none', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
    hours.removeWhere((id, v) => v == hoursWas[id]);
    // Remembered on this phone, so the next check starts from these.
    for (final (field, typed, hub) in [
      ('rate', rate, (Employee e) => e.ratePerHour),
      ('rent', rent, (Employee e) => e.rentDeduction),
      ('loan', loan, (Employee e) => e.loanDeduction),
    ]) {
      for (final t in typed.entries) {
        if (byId[t.key] case final e?) await store.rememberPay(t.key, field, t.value, hub(e));
      }
    }
    for (final u in uif.entries) {
      final hub = byId[u.key]?.uifDeduct;
      await store.rememberPay(u.key, 'uif', u.value ? 1 : 0, hub == null ? null : (hub ? 1 : 0));
    }
    final ids = {...rate.keys, ...rent.keys, ...loan.keys, ...tuck.keys, ...hours.keys, ...uif.keys};
    final haas = _haaskraal(store.ref);
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
              'uif_deduct': ?uif[id],
              if (hours.containsKey(id)) ...{
                'hours_since_last_pay': hours[id],
                'hours_was': hoursWas[id],
                'hours_up_to': dayStr(DateTime.now()),
              },
              if (tuck.containsKey(id)) ...{
                'tuckshop_debt': tuck[id],
                'tuckshop_farm_id': haas?.id,
                'tuckshop_farm_name': haas?.name,
              },
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
