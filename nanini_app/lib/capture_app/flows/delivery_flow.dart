import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/capture/capture_models.dart';
import '../../features/delivery/delivery_models.dart';
import '../../theme/nanini_theme.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../farm_icons.dart';

enum _S { produce, target, count, pepper, butternut, check }

/// Pepper screens, one per size and colour, in this order.
const _pepperKeys = ['5kgRed', '5kgYellow', '5kgGreen', '4kgRed', '4kgYellow', '4kgGreen'];
const _butternutKeys = ['10kg', '7kg'];

/// Loading a packaging truck: count what goes on it, then save it when the
/// truck is full. The count is kept on the phone the whole time (even if the
/// app is closed), since a truck can take hours to load. On approval in the
/// hub it becomes a pending delivery note in Packaging > Records.
class DeliveryFlow extends StatefulWidget {
  const DeliveryFlow({super.key});
  @override
  State<DeliveryFlow> createState() => _DeliveryFlowState();
}

class _DeliveryFlowState extends State<DeliveryFlow> {
  ProduceType? produce;
  String date = dayStr(DateTime.now());
  int target = kDefaultTarget;
  final pallets = <String, int>{for (final s in kPalletSizes) s.key: 0};
  final mixed = <Map<String, int>>[];
  final peppers = <String, int>{'5kgRed': 0, '5kgYellow': 0, '5kgGreen': 0, '4kgRed': 0, '4kgYellow': 0, '4kgGreen': 0};
  final butternuts = <String, int>{'10kg': 0, '7kg': 0};
  int i = 0;

  /// Potatoes first ask how many pallets the truck takes, on its own screen;
  /// peppers ask for each size and colour, and butternuts for each bag size,
  /// on a screen of its own.
  List<_S> get steps => switch (produce) {
    ProduceType.potato => const [_S.produce, _S.target, _S.count, _S.check],
    ProduceType.pepper => [_S.produce, for (final _ in _pepperKeys) _S.pepper, _S.check],
    ProduceType.butternut => [_S.produce, for (final _ in _butternutKeys) _S.butternut, _S.check],
    null => const [_S.produce, _S.count, _S.check],
  };

  /// What's typed on each pepper / butternut screen, kept while moving
  /// between screens.
  final pepperText = <String, String>{for (final k in _pepperKeys) k: ''};
  final butternutText = <String, String>{for (final k in _butternutKeys) k: ''};

  /// What's typed on the pallets-per-truck screen; kept while moving between
  /// screens, so going back from the counter shows the number entered.
  late String targetText = '$target';

  @override
  void initState() {
    super.initState();
    final d = context.read<CaptureStore>().truckDraft;
    if (d != null) {
      produce = ProduceType.values.asNameMap()[d['produce_type']];
      date = d['date'] as String? ?? date;
      target = (d['target'] as num?)?.toInt() ?? kDefaultTarget;
      (d['pallets'] as Map?)?.forEach((k, v) => pallets[k as String] = (v as num).toInt());
      for (final m in (d['mixed_pallets'] as List?) ?? const []) {
        mixed.add({for (final e in (m as Map).entries) e.key as String: (e.value as num).toInt()});
      }
      (d['peppers'] as Map?)?.forEach((k, v) => peppers[k as String] = (v as num).toInt());
      (d['butternuts'] as Map?)?.forEach((k, v) => butternuts[k as String] = (v as num).toInt());
      targetText = '$target';
      peppers.forEach((k, v) => pepperText[k] = v > 0 ? '$v' : '');
      butternuts.forEach((k, v) => butternutText[k] = v > 0 ? '$v' : '');
      // Carry on where the loading left off.
      if (produce != null) i = produce == ProduceType.potato ? steps.indexOf(_S.count) : 1;
    }
  }

  int get totalPallets => pallets.values.fold(0, (a, b) => a + b) + mixed.length;
  int get total => switch (produce) {
    ProduceType.potato => totalPallets,
    ProduceType.pepper => peppers.values.fold(0, (a, b) => a + b),
    ProduceType.butternut => butternuts.values.fold(0, (a, b) => a + b),
    null => 0,
  };
  String get unit => switch (produce) {
    ProduceType.potato => 'pallets',
    ProduceType.pepper => 'boxes',
    _ => 'bags',
  };

  Map<String, dynamic> _payload() => {
    'produce_type': produce!.name,
    'date': date,
    'target': produce == ProduceType.potato ? target : null,
    'pallets': produce == ProduceType.potato ? pallets : <String, int>{},
    'mixed_pallets': produce == ProduceType.potato ? mixed : <Map<String, int>>[],
    'peppers': produce == ProduceType.pepper ? peppers : null,
    'butternuts': produce == ProduceType.butternut ? butternuts : null,
    'total': total,
  };

  void _changed(VoidCallback f) {
    setState(f);
    context.read<CaptureStore>().saveTruckDraft(produce == null ? null : _payload());
  }

  void next() => setState(() => i = (i + 1).clamp(0, steps.length - 1));
  void back() => i == 0 ? Navigator.of(context).pop() : setState(() => i--);

  void _need(String msg) => showNeed(context, msg);

  @override
  Widget build(BuildContext context) {
    StepPage page(String q, Widget child, {VoidCallback? onNext, String? hint, String nextLabel = 'NEXT', IconData nextIcon = Icons.arrow_forward}) => StepPage(
      task: 'Packaging',
      step: i + 1,
      steps: steps.length,
      question: q,
      hint: hint,
      onBack: back,
      onNext: onNext,
      nextLabel: nextLabel,
      nextIcon: nextIcon,
      child: child,
    );

    switch (steps[i]) {
      case _S.produce:
        return page(
          'What is going on the truck?',
          ListView(
            children: [
              for (final (p, emoji, picture, label) in const [
                (ProduceType.potato, '🥔', null, 'POTATOES'),
                (ProduceType.pepper, '🫑', null, 'PEPPERS'),
                // No butternut emoji (🎃 is a pumpkin) -- drawn instead.
                (ProduceType.butternut, null, ButternutIcon(size: 46), 'BUTTERNUTS'),
              ])
                BigChoice(
                  emoji: emoji,
                  leading: picture,
                  label: label,
                  selected: produce == p,
                  onTap: () async {
                    if (produce != null && produce != p && total > 0) {
                      final ok = await _ask('Start a new truck? The counting so far will be lost.');
                      if (!ok) return;
                      _reset();
                    }
                    _changed(() => produce = p);
                    next();
                  },
                ),
            ],
          ),
        );
      case _S.target:
        return page(
          'How many pallets does this truck take?',
          NumberPad(
            value: targetText,
            decimal: false,
            onChanged: (v) {
              setState(() => targetText = v);
              final n = int.tryParse(v);
              if (n != null && n > 0) _changed(() => target = n);
            },
          ),
          hint: 'Usually $kDefaultTarget',
          onNext: () => (int.tryParse(targetText) ?? 0) > 0 ? next() : _need('Type how many pallets the truck takes'),
        );
      case _S.count:
        return page(
          switch (produce) {
            ProduceType.potato => 'Count the pallets',
            ProduceType.pepper => 'Count the boxes',
            _ => 'Count the bags',
          },
          ListView(
            children: [
              if (produce == ProduceType.potato) ..._potato(),
            ],
          ),
          hint: 'Saved on the phone while you load. Tap a number to type it.',
          nextLabel: 'TRUCK FULL',
          nextIcon: Icons.local_shipping,
          onNext: () {
            if (total <= 0) return _need('Nothing counted yet');
            if (produce == ProduceType.potato && totalPallets != target) {
              return _need('$totalPallets of $target pallets. The truck must have $target.');
            }
            next();
          },
        );
      case _S.pepper:
        final key = _pepperKeys[i - steps.indexOf(_S.pepper)];
        final colour = key.replaceFirst(RegExp(r'^\d+kg'), '');
        return page(
          'How many boxes?',
          Column(
            children: [
              Row(
                children: [
                  PepperIcon(colour: PepperColour.of(key), size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${key.substring(0, key.length - colour.length).replaceFirst('kg', ' kg')}  ${colour.toUpperCase()}',
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: NaniniColors.ink),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: NumberPad(
                  value: pepperText[key]!,
                  decimal: false,
                  onChanged: (v) {
                    setState(() => pepperText[key] = v);
                    _changed(() => peppers[key] = int.tryParse(v) ?? 0);
                  },
                ),
              ),
            ],
          ),
          hint: 'None of these? Just press NEXT',
          onNext: next,
        );
      case _S.butternut:
        final key = _butternutKeys[i - steps.indexOf(_S.butternut)];
        return page(
          'How many bags?',
          Column(
            children: [
              Row(
                children: [
                  const ButternutIcon(size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${key.replaceFirst('kg', ' kg')}  BAGS',
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: NaniniColors.ink),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: NumberPad(
                  value: butternutText[key]!,
                  decimal: false,
                  onChanged: (v) {
                    setState(() => butternutText[key] = v);
                    _changed(() => butternuts[key] = int.tryParse(v) ?? 0);
                  },
                ),
              ),
            ],
          ),
          hint: 'None of these? Just press NEXT',
          onNext: next,
        );
      case _S.check:
        return page(
          'Is this right?',
          ListView(
            children: [
              CheckLine(icon: Icons.local_shipping, text: '$total $unit of ${produce?.name}'),
              if (produce == ProduceType.potato)
                for (final s in kPalletSizes.where((s) => (pallets[s.key] ?? 0) > 0))
                  CheckLine(icon: Icons.inventory_2, color: Color(s.color), text: '${pallets[s.key]} × ${s.label}'),
              if (produce == ProduceType.potato && mixed.isNotEmpty)
                CheckLine(icon: Icons.inventory_2, color: NaniniColors.muted, text: '${mixed.length} × mixed pallet'),
              if (produce == ProduceType.pepper)
                for (final e in peppers.entries.where((e) => e.value > 0))
                  CheckLine(leading: PepperIcon(colour: PepperColour.of(e.key), size: 34), text: '${e.value} × ${e.key.replaceFirst('kg', 'kg ')}'),
              if (produce == ProduceType.butternut)
                for (final e in butternuts.entries.where((e) => e.value > 0))
                  CheckLine(leading: const ButternutIcon(size: 34), text: '${e.value} × ${e.key} bags'),
            ],
          ),
          hint: 'If something is wrong, press BACK',
          nextLabel: 'SAVE',
          nextIcon: Icons.check,
          onNext: () => total > 0 ? _save() : _need('Nothing counted yet -- press BACK'),
        );
    }
  }

  List<Widget> _potato() => [
    Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              '$totalPallets of $target pallets',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: totalPallets == target ? NaniniColors.green : NaniniColors.ink),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: target <= 0 ? 0 : (totalPallets / target).clamp(0, 1),
                minHeight: 16,
                color: totalPallets == target ? NaniniColors.green : NaniniColors.rust,
                backgroundColor: NaniniColors.disabledBg,
              ),
            ),
          ],
        ),
      ),
    ),
    for (final s in kPalletSizes) _counter(s.label, () => pallets[s.key]!, (v) => _changed(() => pallets[s.key] = v), color: Color(s.color)),
    const SizedBox(height: 8),
    SizedBox(
      height: 60,
      child: OutlinedButton.icon(
        onPressed: _addMixed,
        icon: const Icon(Icons.add, size: 28),
        label: const Text('MIXED PALLET', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
      ),
    ),
    for (final (idx, m) in mixed.indexed)
      ListTile(
        title: Text('Mixed pallet ${idx + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        subtitle: Text(m.entries.map((e) => '${kPalletSizes.firstWhere((s) => s.key == e.key).label}: ${e.value}').join('\n')),
        trailing: IconButton(
          iconSize: 30,
          icon: const Icon(Icons.delete_outline, color: NaniniColors.red),
          onPressed: () async {
            if (await _ask('Remove mixed pallet ${idx + 1}?')) _changed(() => mixed.removeAt(idx));
          },
        ),
      ),
  ];

  /// [read] is called at tap time (not build time), so quick repeated taps
  /// each count.
  Widget _counter(String label, int Function() read, ValueChanged<int> onChanged, {Color? color}) {
    final value = read();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color ?? NaniniColors.line, width: value > 0 ? 3 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: color ?? NaniniColors.ink),
              ),
            ),
            IconButton(
              iconSize: 44,
              onPressed: value > 0 ? () => onChanged((read() - 1).clamp(0, 99999)) : null,
              icon: const Icon(Icons.remove_circle, color: NaniniColors.rust),
            ),
            InkWell(
              onTap: () async {
                final v = await _typeNumber(label, read());
                if (v != null) onChanged(v);
              },
              child: SizedBox(
                width: 56,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            IconButton(
              iconSize: 44,
              onPressed: () => onChanged(read() + 1),
              icon: const Icon(Icons.add_circle, color: NaniniColors.green),
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> _typeNumber(String title, int current) async {
    var v = current == 0 ? '' : '$current';
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 22)),
          content: SizedBox(
            width: 320,
            height: 420,
            child: NumberPad(value: v, decimal: false, onChanged: (x) => setLocal(() => v = x)),
          ),
          actions: [
            SizedBox(
              height: 56,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL', style: TextStyle(fontSize: 18)),
              ),
            ),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, int.tryParse(v) ?? 0),
                child: const Text('OK', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMixed() async {
    final lines = <String, int>{for (final s in kPalletSizes) s.key: 0};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Mixed pallet: bags of each', style: TextStyle(fontSize: 22)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final s in kPalletSizes)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.label,
                                style: TextStyle(fontSize: 16, color: Color(s.color), fontWeight: FontWeight.w600),
                              ),
                            ),
                            IconButton(
                              onPressed: lines[s.key]! > 0 ? () => setLocal(() => lines[s.key] = (lines[s.key]! - 1).clamp(0, 9999)) : null,
                              icon: const Icon(Icons.remove_circle),
                            ),
                            InkWell(
                              onTap: () async {
                                final v = await _typeNumber(s.label, lines[s.key]!);
                                if (v != null) setLocal(() => lines[s.key] = v);
                              },
                              child: SizedBox(
                                width: 40,
                                child: Text(
                                  '${lines[s.key]}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setLocal(() => lines[s.key] = lines[s.key]! + 1),
                              icon: const Icon(Icons.add_circle, color: NaniniColors.green),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                // Running total of the bags on this pallet, always in view.
                const Divider(),
                Text(
                  'Total: ${lines.values.fold(0, (a, b) => a + b)} bags',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: NaniniColors.ink),
                ),
              ],
            ),
          ),
          actions: [
            SizedBox(
              height: 56,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCEL', style: TextStyle(fontSize: 18)),
              ),
            ),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ADD', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok == true && lines.values.any((v) => v > 0)) {
      _changed(() => mixed.add(Map.of(lines)..removeWhere((k, v) => v <= 0)));
    }
  }

  Future<bool> _ask(String msg) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(msg, style: const TextStyle(fontSize: 20)),
          actions: [
            SizedBox(
              height: 56,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('NO', style: TextStyle(fontSize: 18)),
              ),
            ),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('YES', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ) ??
      false;

  void _reset() {
    target = kDefaultTarget;
    targetText = '$kDefaultTarget';
    pallets.updateAll((k, v) => 0);
    mixed.clear();
    peppers.updateAll((k, v) => 0);
    pepperText.updateAll((k, v) => '');
    butternuts.updateAll((k, v) => 0);
    butternutText.updateAll((k, v) => '');
    date = dayStr(DateTime.now());
  }

  Future<void> _save() async {
    final store = context.read<CaptureStore>();
    await store.add(CaptureModule.delivery, _payload(), '${produce!.name} truck: $total $unit');
    await store.saveTruckDraft(null);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SavedScreen(task: 'truck', another: (_) => const DeliveryFlow()),
      ),
    );
  }
}
