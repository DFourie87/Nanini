import 'delivery_models.dart';

/// Packaging > Bags/Boxes: the bags and boxes on the floor to pack -- bought
/// (Crown Bag's invoices for the potato bags, typed in for the rest), less
/// [bagLosses] of what's bought for losses, less what went out on the
/// delivery notes. Counted from [kBagsFrom].
const kBagsFrom = '2025-02-01';

/// Losses on what's bought: 1% of potato and butternut bags, 0.25% of
/// pepper boxes.
double bagLosses(ProduceType p) => p == ProduceType.pepper ? 0.0025 : 0.01;

/// "1%", "0.25%".
String bagLossesText(ProduceType p) => '${(bagLosses(p) * 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}%';

/// A kind of bag or box as bought; [uses]: what the phones count that goes
/// into it (Baby and Small potatoes share the 10kg Small bag).
class BagKind {
  const BagKind(this.key, this.label, this.uses);
  final String key, label;
  final List<String> uses;
}

const kPotatoBags = <BagKind>[
  BagKind('small10', '10kg 1st Small (Baby and Small)', ['baby10', 'small10']),
  BagKind('largemed10', '10kg 1st Large/Medium', ['largemed10']),
  BagKind('large10', '10kg 1st Large', ['large10']),
  BagKind('smallmed7', '7kg 1st Small/Medium', ['smallmed7']),
  BagKind('med7', '7kg 1st Medium', ['med7']),
  BagKind('med10g2', '10kg 2nd Medium', ['med10g2']),
  BagKind('largemed10g2', '10kg 2nd Large/Medium', ['largemed10g2']),
  BagKind('large10g2', '10kg 2nd Large', ['large10g2']),
];

const kPepperBoxes = <BagKind>[
  BagKind('5kgRed', '5kg Red', ['5kgRed']),
  BagKind('5kgYellow', '5kg Yellow', ['5kgYellow']),
  BagKind('5kgGreen', '5kg Green', ['5kgGreen']),
  BagKind('4kgRed', '4kg Red', ['4kgRed']),
  BagKind('4kgYellow', '4kg Yellow', ['4kgYellow']),
  BagKind('4kgGreen', '4kg Green', ['4kgGreen']),
];

const kButternutBags = <BagKind>[
  BagKind('10kg', '10kg', ['10kg']),
  BagKind('7kg', '7kg', ['7kg']),
];

List<BagKind> bagKinds(ProduceType p) => switch (p) {
      ProduceType.potato => kPotatoBags,
      ProduceType.pepper => kPepperBoxes,
      ProduceType.butternut => kButternutBags,
    };

String bagLabel(ProduceType p, String item) => bagKinds(p).where((k) => k.key == item).firstOrNull?.label ?? item;

/// Bags or boxes bought (or returned: [qty] below 0).
class BagPurchase {
  BagPurchase({required this.id, required this.date, required this.produce, required this.item, required this.qty, this.reference, this.description, this.sourceKey});
  final String id;
  final String date;
  final ProduceType produce;
  final String item;
  final int qty;
  final String? reference, description;

  /// Set for an invoice line brought in from email (scripts/fetch_crown_bags.py).
  final String? sourceKey;
  bool get fromEmail => sourceKey != null;

  static BagPurchase? fromJson(Map<String, dynamic> j) {
    final p = ProduceType.values.asNameMap()[j['produce']];
    if (p == null) return null;
    return BagPurchase(
      id: j['id'] as String,
      date: j['purchase_date'] as String,
      produce: p,
      item: j['item'] as String,
      qty: (j['qty'] as num).toInt(),
      reference: j['reference'] as String?,
      description: j['description'] as String?,
      sourceKey: j['source_key'] as String?,
    );
  }
}

class BagBalance {
  /// One bag or box: [rate] of what's bought for losses.
  BagBalance(this.bought, this.used, double rate) : losses = bought <= 0 ? 0 : (bought * rate).round();

  /// All of them together (each one's losses added up).
  BagBalance.total(Iterable<BagBalance> all)
      : bought = all.fold(0, (s, b) => s + b.bought),
        used = all.fold(0, (s, b) => s + b.used),
        losses = all.fold(0, (s, b) => s + b.losses);

  final int bought, used, losses;
  int get available => bought - losses - used;
}

/// How many of each bag or box went out on the delivery notes from [from].
Map<String, int> bagsUsed(ProduceType p, List<DeliveryNote> notes, {String from = kBagsFrom}) {
  final kinds = bagKinds(p);
  String? kindOf(String counted) => kinds.where((k) => k.uses.contains(counted)).firstOrNull?.key;
  final used = <String, int>{};
  void add(String counted, num n) {
    final k = kindOf(counted);
    if (k != null && n != 0) used[k] = (used[k] ?? 0) + n.round();
  }

  for (final n in notes) {
    if (n.produceType != p.name || n.noteDate.compareTo(from) < 0) continue;
    if (p == ProduceType.potato) {
      for (final s in kPalletSizes) {
        add(s.key, ((n.pallets[s.key] as num?) ?? 0) * s.bagsPerPallet);
      }
      for (final m in n.mixedPallets) {
        if (m is Map) m.forEach((k, v) => add('$k', (v as num?) ?? 0));
      }
    } else {
      n.produceDetail?.forEach((k, v) => add(k, (v as num?) ?? 0));
    }
  }
  return used;
}

/// Each bag or box: bought and used from [from].
Map<String, BagBalance> bagBalances(ProduceType p, List<BagPurchase> purchases, List<DeliveryNote> notes, {String from = kBagsFrom}) {
  final used = bagsUsed(p, notes, from: from);
  final bought = <String, int>{};
  for (final b in purchases.where((b) => b.produce == p && b.date.compareTo(from) >= 0)) {
    bought[b.item] = (bought[b.item] ?? 0) + b.qty;
  }
  return {for (final k in bagKinds(p)) k.key: BagBalance(bought[k.key] ?? 0, used[k.key] ?? 0, bagLosses(p))};
}
