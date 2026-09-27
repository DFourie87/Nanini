import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/capture/capture_models.dart';
import '../../theme/nanini_theme.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../ref_data.dart';

enum _S { shop, person, items, check }

/// A tuck shop sale on the book. Item shops (Limpopodraai) pick items and
/// quantities; Haaskraal's shop is written down as a money amount, the same
/// way the hub's Tuck Shop app handles each farm.
class TuckshopFlow extends StatefulWidget {
  const TuckshopFlow({super.key});
  @override
  State<TuckshopFlow> createState() => _TuckshopFlowState();
}

class _TuckshopFlowState extends State<TuckshopFlow> {
  RefItem? shop;
  RefPerson? person;
  final basket = <String, int>{};
  String amount = '';
  int i = 0;

  static const steps = [_S.shop, _S.person, _S.items, _S.check];

  bool get manual => shop != null && RefData.isManualShop(shop!);

  void next() => setState(() => i = (i + 1).clamp(0, steps.length - 1));
  void back() => i == 0 ? Navigator.of(context).pop() : setState(() => i--);

  void _need(String msg) => showNeed(context, msg);

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<CaptureStore>().ref;
    final items = ref.shopItems.where((it) => it.farmId == shop?.id).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    double total() => manual ? (padValue(amount) ?? 0) : basket.entries.fold(0.0, (s, e) => s + e.value * (items.where((it) => it.id == e.key).firstOrNull?.price ?? 0));

    StepPage page(String q, Widget child, {VoidCallback? onNext, String? hint, String nextLabel = 'NEXT', IconData nextIcon = Icons.arrow_forward}) =>
        StepPage(task: 'Tuck shop', step: i + 1, steps: steps.length, question: q, hint: hint, onBack: back, onNext: onNext, nextLabel: nextLabel, nextIcon: nextIcon, child: child);

    switch (steps[i]) {
      case _S.shop:
        final shops = ref.shopFarms;
        return page(
          'Which shop?',
          shops.isEmpty
              ? const EmptyListNote()
              : ListView(children: [
                  for (final f in shops)
                    BigChoice(icon: Icons.storefront, label: f.name, selected: shop?.id == f.id, onTap: () {
                      setState(() {
                        if (shop?.id != f.id) basket.clear();
                        shop = f;
                      });
                      next();
                    }),
                ]),
        );
      case _S.person:
        final onFarm = ref.people.where((p) => p.farmId == shop?.id).toList();
        return page(
          'Who is buying?',
          PersonPicker(
            people: onFarm.isEmpty ? ref.people : onFarm,
            selectedIds: {?person?.id},
            onPick: (p) {
              setState(() => person = p);
              next();
            },
          ),
        );
      case _S.items:
        if (manual) {
          return page(
            'How much did ${person?.name} buy for?',
            NumberPad(value: amount, prefix: 'R', onChanged: (v) => setState(() => amount = v)),
            onNext: () => (padValue(amount) ?? 0) > 0 ? next() : _need('Type the amount'),
          );
        }
        return page(
          'What is ${person?.name} buying?',
          items.isEmpty
              ? const EmptyListNote()
              : ListView(children: [
                  for (final it in items) _itemRow(it),
                ]),
          hint: 'Press + for each one. Total: R ${fmtNum(total())}',
          onNext: () => basket.values.any((q) => q > 0) ? next() : _need('Press + on at least one item'),
        );
      case _S.check:
        return page(
          'Is this right?',
          ListView(children: [
            CheckLine(icon: Icons.person, text: person?.name ?? ''),
            CheckLine(icon: Icons.storefront, text: shop?.name ?? ''),
            if (!manual)
              for (final e in basket.entries.where((e) => e.value > 0))
                CheckLine(icon: Icons.shopping_basket, text: '${e.value} × ${items.firstWhere((it) => it.id == e.key).name}'),
            CheckLine(icon: Icons.payments, text: 'Total R ${fmtNum(total())}'),
          ]),
          hint: 'If something is wrong, press BACK',
          nextLabel: 'SAVE',
          nextIcon: Icons.check,
          onNext: () => _save(items, total()),
        );
    }
  }

  /// Whole items this phone may still sell: the downloaded stock level less
  /// sales already captured here that the office hasn't processed yet.
  int _available(RefShopItem it) {
    final left = it.stock - context.read<CaptureStore>().reservedQty(it.id);
    return left <= 0 ? 0 : left.floor();
  }

  Widget _itemRow(RefShopItem it) {
    final q = basket[it.id] ?? 0;
    final available = _available(it);
    final atLimit = q >= available;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: q > 0 ? NaniniColors.rust : NaniniColors.line, width: q > 0 ? 3 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: NaniniColors.ink)),
                  Text(
                    available > 0 ? 'In stock: $available' : 'Out of stock',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: available > 0 ? NaniniColors.green : NaniniColors.red),
                  ),
                ],
              ),
            ),
            IconButton(
              iconSize: 44,
              onPressed: q > 0 ? () => setState(() => basket[it.id] = ((basket[it.id] ?? 0) - 1).clamp(0, 9999)) : null,
              icon: const Icon(Icons.remove_circle, color: NaniniColors.rust),
            ),
            SizedBox(width: 40, child: Text('$q', textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
            // Stops at the stock level: nothing can be sold that isn't there.
            IconButton(
              iconSize: 44,
              onPressed: atLimit
                  ? () => _need(available > 0 ? 'Only $available ${it.name} in stock' : '${it.name} is out of stock')
                  : () => setState(() => basket[it.id] = ((basket[it.id] ?? 0) + 1).clamp(0, available)),
              icon: Icon(Icons.add_circle, color: atLimit ? NaniniColors.disabledBg : NaniniColors.green),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(List<RefShopItem> items, double total) async {
    final store = context.read<CaptureStore>();
    final payload = <String, dynamic>{
      'farm_id': shop!.id,
      'farm_name': shop!.name,
      'employee_id': person!.id,
      'employee_name': person!.name,
      'date': dayStr(DateTime.now()),
    };
    if (manual) {
      payload['manual_total'] = total;
    } else {
      payload['lines'] = [
        for (final e in basket.entries.where((e) => e.value > 0))
          () {
            final it = items.firstWhere((x) => x.id == e.key);
            return {'item_id': it.id, 'item_name': it.name, 'qty': e.value, 'price': it.price};
          }(),
      ];
    }
    await store.add(CaptureModule.tuckshop, payload, '${person!.name}: R ${fmtNum(total)}');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(task: 'sale', another: (_) => const TuckshopFlow())));
  }
}
