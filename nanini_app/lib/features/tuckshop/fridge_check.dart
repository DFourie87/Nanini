import 'tuckshop_models.dart';

/// Write-offs made for a shortage found by a fridge count start with this
/// (not counted again as written off in the next check).
const kShortWriteoffReason = 'Short on fridge count';

/// The write-off reason for [item]'s shortage at the count of [date].
String shortWriteoffReason(String date) => '$kShortWriteoffReason $date';

/// One item between two fridge counts: what should be in the fridge at the
/// second count, and what was there.
///   opening (the count before) + bought - taken (fridge sheets and sales)
///   - written off = should be; should be - counted = short.
/// The days: sales and write-offs after the opening count's day up to and
/// on the closing count's day (the fridge sheet's sales are dated pay day);
/// stock bought on the opening count's day up to the day before the closing
/// count (restocked after counting on pay day).
class FridgeCheck {
  FridgeCheck({
    required this.item,
    required this.closeDate,
    required this.counted,
    this.openDate,
    this.opening,
    this.bought = 0,
    this.taken = 0,
    this.writtenOff = 0,
    this.shortWrittenOff = false,
  });
  final TuckshopItem item;

  /// The count before; null: the first count (the check starts from it).
  final String? openDate;
  final double? opening;
  final double bought, taken, writtenOff;
  final String closeDate;
  final double counted;

  /// The shortage is already written off (Write off on the check).
  final bool shortWrittenOff;

  bool get isFirst => opening == null;
  double get shouldBe => (opening ?? counted) + bought - taken - writtenOff;

  /// More than 0: missing (taken and not written down, or stolen); less than
  /// 0: more there than expected (a purchase not typed in, marks counted
  /// twice).
  double get short => isFirst ? 0 : shouldBe - counted;
}

/// Every count of the fridge items, newest first, against the count before
/// it. Two counts of an item on one day: the later one only (a recount).
List<FridgeCheck> fridgeChecks({
  required List<TuckshopItem> items,
  required List<TuckshopCount> counts,
  required List<TuckshopStockPurchase> bought,
  required List<TuckshopPurchase> sales,
  required List<TuckshopWriteoff> writeoffs,
}) {
  final out = <FridgeCheck>[];
  for (final item in items) {
    final byDay = <String, TuckshopCount>{};
    for (final c in counts.where((c) => c.itemId == item.id)) {
      final had = byDay[c.date];
      if (had == null || (c.createdAt ?? '').compareTo(had.createdAt ?? '') >= 0) byDay[c.date] = c;
    }
    final days = byDay.keys.toList()..sort();
    for (final (n, day) in days.indexed) {
      final close = byDay[day]!;
      final reason = shortWriteoffReason(day);
      final done = writeoffs.any((w) => w.itemId == item.id && (w.reason ?? '') == reason);
      if (n == 0) {
        out.add(FridgeCheck(item: item, closeDate: day, counted: close.qty));
        continue;
      }
      final open = byDay[days[n - 1]]!;
      bool after(String d) => d.compareTo(open.date) > 0 && d.compareTo(day) <= 0;
      out.add(FridgeCheck(
        item: item,
        openDate: open.date,
        opening: open.qty,
        closeDate: day,
        counted: close.qty,
        bought: bought.where((b) => b.itemId == item.id && b.date.compareTo(open.date) >= 0 && b.date.compareTo(day) < 0).fold(0.0, (s, b) => s + b.qty),
        taken: sales.where((p) => p.itemId == item.id && after(p.date)).fold(0.0, (s, p) => s + (p.qty ?? 0)),
        writtenOff: writeoffs
            .where((w) => w.itemId == item.id && after(w.date) && !(w.reason ?? '').startsWith(kShortWriteoffReason))
            .fold(0.0, (s, w) => s + w.qty),
        shortWrittenOff: done,
      ));
    }
  }
  out.sort((a, b) => b.closeDate != a.closeDate ? b.closeDate.compareTo(a.closeDate) : a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase()));
  return out;
}
