import '../sales/potato_fields.dart';
import 'delivery_models.dart';

/// Packaging > Bags/Boxes: the bags and boxes on the floor to pack -- bought
/// (Crown Bag's invoices for the potato bags, typed in for the rest), less
/// [bagLosses] for losses, less what went out on the
/// delivery notes. Counted from [kBagsFrom].
const kBagsFrom = '2026-02-01';

/// Losses: potato bags 0.5% of the stock take plus purchases; pepper boxes
/// 0.25% and butternut bags 1% of purchases.
double bagLosses(ProduceType p) => switch (p) {
      ProduceType.potato => 0.005,
      ProduceType.pepper => 0.0025,
      ProduceType.butternut => 0.01,
    };

/// Potato bags' losses are on the stock take too, not only on purchases.
bool bagLossesOnStock(ProduceType p) => p == ProduceType.potato;

/// "1%", "0.25%".
String bagLossesText(ProduceType p) => '${(bagLosses(p) * 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}%';

/// A kind of bag or box as bought; [uses]: what the phones count that goes
/// into it (Baby and Small potatoes share the 10kg Small bag; all 2nd and
/// 3rd grades the brown bag).
class BagKind {
  const BagKind(this.key, this.label, this.uses);
  final String key, label;
  final List<String> uses;
}

final kPotatoBags = <BagKind>[
  // From Large to Small, then the brown bag (as on the floor list).
  const BagKind('large10', '10kg 1st Large', ['large10']),
  const BagKind('largemed10', '10kg 1st Large/Medium', ['largemed10']),
  const BagKind('med7', '7kg 1st Medium', ['med7']),
  const BagKind('smallmed7', '7kg 1st Small/Medium', ['smallmed7']),
  const BagKind('small10', '10kg 1st Small (Baby and Small)', ['baby10', 'small10']),
  // Every 2nd and 3rd grade goes in the same bag: normally a brown generic one.
  BagKind('brown10', '10kg 2nd/3rd grade (brown bag)', [for (final s in kPalletSizes) if (s.grade != 'g1') s.key]),
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

/// What a bag_purchases row is: bags or boxes bought (or returned: [qty]
/// below 0), an adjustment by hand (opening stock, losses, damage: plus or
/// minus), or a count on the floor (the number from the end of that day).
enum BagEntryKind { bought, adjust, count }

class BagPurchase {
  BagPurchase({
    required this.id,
    required this.date,
    required this.produce,
    required this.item,
    required this.qty,
    this.kind = BagEntryKind.bought,
    this.reference,
    this.description,
    this.sourceKey,
    this.createdAt = '',
  });
  final String id;
  final String date;
  final ProduceType produce;
  final String item;
  final int qty;
  final BagEntryKind kind;

  /// [reference]: the invoice; [description]: as on the invoice, or why
  /// adjusted.
  final String? reference, description;

  /// Set for an invoice line brought in from email (scripts/fetch_crown_bags.py).
  final String? sourceKey;
  bool get fromEmail => sourceKey != null;

  /// Two counts on the same day: the later one counts.
  final String createdAt;

  static BagPurchase? fromJson(Map<String, dynamic> j) {
    final p = ProduceType.values.asNameMap()[j['produce']];
    if (p == null) return null;
    return BagPurchase(
      id: j['id'] as String,
      date: j['purchase_date'] as String,
      produce: p,
      item: j['item'] as String,
      qty: (j['qty'] as num).toInt(),
      kind: BagEntryKind.values.asNameMap()[j['kind']] ?? BagEntryKind.bought,
      reference: j['reference'] as String?,
      description: j['description'] as String?,
      sourceKey: j['source_key'] as String?,
      createdAt: j['created_at'] as String? ?? '',
    );
  }
}

class BagBalance {
  BagBalance({this.counted, this.countDate, required this.bought, required this.losses, required this.adjusted, required this.used, this.packed = 0});

  /// All of them together.
  BagBalance.total(Iterable<BagBalance> all)
      : counted = all.any((b) => b.counted != null) ? all.fold<int>(0, (s, b) => s + (b.counted ?? 0)) : null,
        countDate = null,
        bought = all.fold(0, (s, b) => s + b.bought),
        losses = all.fold(0, (s, b) => s + b.losses),
        adjusted = all.fold(0, (s, b) => s + b.adjusted),
        used = all.fold(0, (s, b) => s + b.used),
        packed = all.fold(0, (s, b) => s + b.packed);

  /// The last count on the floor and its day (the rest is after it); null:
  /// never counted -- everything from [kBagsFrom].
  final int? counted;
  final String? countDate;
  final int bought, losses, adjusted;

  /// [used]: loaded on the trucks (the delivery notes, sent or still to
  /// approve -- not what was sold); [packed]: packed but not sent (Sales >
  /// Summary, potatoes).
  final int used, packed;
  int get available => (counted ?? 0) + bought - losses + adjusted - used - packed;
}

/// Losses on [base] bags or boxes at [rate], whole ones.
int lossesOn(int base, double rate) => base <= 0 ? 0 : (base * rate).round();

/// Bags or boxes for what went out on each delivery note: (date, bag, how many).
Iterable<(String, String, int)> _bagsOnNotes(ProduceType p, List<DeliveryNote> notes) sync* {
  final kinds = bagKinds(p);
  String? kindOf(String counted) => kinds.where((k) => k.uses.contains(counted)).firstOrNull?.key;
  for (final n in notes) {
    if (n.produceType != p.name) continue;
    final per = <String, num>{};
    if (p == ProduceType.potato) {
      for (final s in kPalletSizes) {
        per[s.key] = (per[s.key] ?? 0) + ((n.pallets[s.key] as num?) ?? 0) * s.bagsPerPallet;
      }
      for (final m in n.mixedPallets) {
        if (m is Map) m.forEach((k, v) => per['$k'] = (per['$k'] ?? 0) + ((v as num?) ?? 0));
      }
    } else {
      n.produceDetail?.forEach((k, v) => per[k] = (per[k] ?? 0) + ((v as num?) ?? 0));
    }
    for (final e in per.entries) {
      final k = kindOf(e.key);
      if (k != null && e.value != 0) yield (n.noteDate, k, e.value.round());
    }
  }
}

/// How many of each bag or box went out on the delivery notes from [from].
Map<String, int> bagsUsed(ProduceType p, List<DeliveryNote> notes, {String from = kBagsFrom}) {
  final used = <String, int>{};
  for (final (date, k, n) in _bagsOnNotes(p, notes)) {
    if (date.compareTo(from) >= 0) used[k] = (used[k] ?? 0) + n;
  }
  return used;
}

/// Potato bags packed but not sent: (date, bag, how many).
Iterable<(String, String, int)> _bagsUnsent(List<UnsentPallets> unsent) sync* {
  String? kindOf(String counted) => kPotatoBags.where((k) => k.uses.contains(counted)).firstOrNull?.key;
  for (final u in unsent) {
    for (final e in u.bagsBySize.entries) {
      final k = kindOf(e.key);
      if (k != null && e.value != 0) yield (u.date, k, e.value);
    }
  }
}

/// Each bag or box on the floor: its last count (else nothing, from
/// [kBagsFrom]), plus bought less losses, plus adjustments, less loaded on
/// the trucks and (potatoes) packed but not sent -- all after the count's day.
Map<String, BagBalance> bagBalances(ProduceType p, List<BagPurchase> purchases, List<DeliveryNote> notes, {List<UnsentPallets> unsent = const []}) {
  final rate = bagLosses(p);
  final mine = purchases.where((b) => b.produce == p).toList();
  final onNotes = _bagsOnNotes(p, notes).toList();
  final notSent = p == ProduceType.potato ? _bagsUnsent(unsent).toList() : const <(String, String, int)>[];
  final out = <String, BagBalance>{};
  for (final k in bagKinds(p)) {
    final counts = mine.where((b) => b.item == k.key && b.kind == BagEntryKind.count).toList()
      ..sort((a, b) => a.date != b.date ? a.date.compareTo(b.date) : a.createdAt.compareTo(b.createdAt));
    final count = counts.lastOrNull;
    // After the count's day; never counted: from the start.
    bool afterStart(String date) => count == null ? date.compareTo(kBagsFrom) >= 0 : date.compareTo(count.date) > 0;
    int sum(BagEntryKind kind) => mine.where((b) => b.item == k.key && b.kind == kind && afterStart(b.date)).fold(0, (s, b) => s + b.qty);
    final bought = sum(BagEntryKind.bought);
    out[k.key] = BagBalance(
      counted: count?.qty,
      countDate: count?.date,
      bought: bought,
      losses: lossesOn(bought + (bagLossesOnStock(p) ? count?.qty ?? 0 : 0), rate),
      adjusted: sum(BagEntryKind.adjust),
      used: onNotes.where((u) => u.$2 == k.key && afterStart(u.$1)).fold(0, (s, u) => s + u.$3),
      packed: notSent.where((u) => u.$2 == k.key && afterStart(u.$1)).fold(0, (s, u) => s + u.$3),
    );
  }
  return out;
}
