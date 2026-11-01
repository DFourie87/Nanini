import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/capture/capture_models.dart';
import '../../features/capture/fridge_sheet_capture.dart' show isFridgeItemName;
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../ref_data.dart';

/// The fridge counted on pay day (after the fridge sheet's pages are
/// photographed, before it's restocked): how many of each fridge item (wors,
/// chicken pieces) are in it now. Straight in; the hub's Tuck Shop > Fridge
/// check puts it against the count before: opening + bought - taken on the
/// sheets and sales = should be there.
class FridgeCountFlow extends StatefulWidget {
  const FridgeCountFlow({super.key});
  @override
  State<FridgeCountFlow> createState() => _FridgeCountFlowState();
}

class _FridgeCountFlowState extends State<FridgeCountFlow> {
  RefItem? shop;

  /// The item being counted (an index into the shop's fridge items), or the
  /// check when past the last.
  int at = 0;
  final counts = <String, String>{};

  List<RefItem> _shops(RefData ref) => [for (final f in ref.shopFarms) if (ref.shopItems.any((i) => i.farmId == f.id && isFridgeItemName(i.name))) f];

  List<RefShopItem> _items(RefData ref) =>
      [for (final i in ref.shopItems) if (i.farmId == shop?.id && isFridgeItemName(i.name)) i]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<CaptureStore>().ref;
    final shops = _shops(ref);
    // One shop with a fridge (Limpopodraai): straight to counting.
    if (shop == null && shops.length == 1) shop = shops.single;
    final pickShop = shops.length > 1;
    final items = _items(ref);
    final steps = (pickShop ? 1 : 0) + items.length + 1;
    StepPage page(int step, String q, Widget child, {VoidCallback? onBack, VoidCallback? onNext, String? hint, String nextLabel = 'NEXT', IconData nextIcon = Icons.arrow_forward}) =>
        StepPage(
            task: 'Fridge count',
            step: step,
            steps: steps,
            question: q,
            hint: hint,
            onBack: onBack ?? () => Navigator.of(context).pop(),
            onNext: onNext,
            nextLabel: nextLabel,
            nextIcon: nextIcon,
            child: child);

    if (shop == null) {
      return page(
        1,
        'Which fridge?',
        shops.isEmpty
            ? const EmptyListNote()
            : ListView(children: [
                for (final f in shops) BigChoice(icon: Icons.kitchen, label: f.name, onTap: () => setState(() => shop = f)),
              ]),
      );
    }
    void back() => at == 0 ? (pickShop ? setState(() => shop = null) : Navigator.of(context).pop()) : setState(() => at--);
    final first = pickShop ? 2 : 1;
    if (at < items.length) {
      final it = items[at];
      return page(
        first + at,
        'How many ${it.name} are in the fridge now?',
        NumberPad(value: counts[it.id] ?? '', decimal: false, onChanged: (v) => setState(() => counts[it.id] = v)),
        hint: 'Count them all, before putting new stock in. None: type 0.',
        onBack: back,
        onNext: () => (counts[it.id] ?? '').isEmpty ? showNeed(context, 'Type how many (0 for none)') : setState(() => at++),
      );
    }
    return page(
      first + items.length,
      'Is this right?',
      ListView(children: [
        CheckLine(icon: Icons.kitchen, text: '${shop!.name} -- ${dayStr(DateTime.now())}'),
        for (final it in items) CheckLine(icon: Icons.inventory_2, text: '${it.name}: ${counts[it.id] ?? 0}'),
      ]),
      hint: 'The hub checks it against the last count, what was bought and what is on the fridge sheets',
      onBack: back,
      nextLabel: 'SAVE',
      nextIcon: Icons.check,
      onNext: () => _save(items),
    );
  }

  Future<void> _save(List<RefShopItem> items) async {
    final store = context.read<CaptureStore>();
    final lines = [for (final it in items) {'item_id': it.id, 'item_name': it.name, 'qty': int.parse(counts[it.id] ?? '0')}];
    await store.add(
      CaptureModule.fridgeSheet,
      {'kind': 'count', 'date': dayStr(DateTime.now()), 'farm_id': shop!.id, 'farm_name': shop!.name, 'counts': lines},
      'Fridge count ${shop!.name}: ${lines.map((l) => '${l['qty']} ${l['item_name']}').join(', ')}',
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(task: 'count', another: (_) => const FridgeCountFlow())));
  }
}
