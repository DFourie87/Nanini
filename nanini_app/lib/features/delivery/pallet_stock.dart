import 'delivery_models.dart';

/// Pallets collected that can't be used (broken): 8% of the stock take plus
/// those collected, whole ones.
const kPalletLossRate = 0.08;
const kPalletLossText = '8%';

/// One market agent's pallets on the floor: its last count (the rest is
/// after that day), plus collected empty there, less those not useable
/// ([kPalletLossRate] of count + collected), plus adjustments, less returned
/// loaded on the potato delivery notes.
class PalletBalance {
  PalletBalance({this.counted, this.countDate, this.collected = 0, this.losses = 0, this.adjusted = 0, this.returned = 0});

  /// All the agents together.
  PalletBalance.total(Iterable<PalletBalance> all)
      : counted = all.any((b) => b.counted != null) ? all.fold<int>(0, (s, b) => s + (b.counted ?? 0)) : null,
        countDate = null,
        collected = all.fold(0, (s, b) => s + b.collected),
        losses = all.fold(0, (s, b) => s + b.losses),
        adjusted = all.fold(0, (s, b) => s + b.adjusted),
        returned = all.fold(0, (s, b) => s + b.returned);

  /// The last count and its day; null: never counted (everything counts).
  final int? counted;
  final String? countDate;
  final int collected, losses, adjusted, returned;
  int get onFloor => (counted ?? 0) + collected - losses + adjusted - returned;
}

/// Each agent's pallets (every agent pallets were collected at or sent to),
/// by name.
Map<String, PalletBalance> palletBalances(List<PalletPurchase> entries, List<DeliveryNote> notes) {
  final sent = [for (final n in notes) if (n.produceType == 'potato' && n.agentName != null && n.total != 0) n];
  final names = {for (final e in entries) e.agentName, for (final n in sent) n.agentName!}.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  final out = <String, PalletBalance>{};
  for (final name in names) {
    final mine = entries.where((e) => e.agentName == name).toList();
    final counts = mine.where((e) => e.kind == PalletEntryKind.count).toList()
      ..sort((a, b) => a.date != b.date ? a.date.compareTo(b.date) : a.createdAt.compareTo(b.createdAt));
    final count = counts.lastOrNull;
    bool after(String date) => count == null || date.compareTo(count.date) > 0;
    int sum(PalletEntryKind k) => mine.where((e) => e.kind == k && after(e.date)).fold(0, (s, e) => s + e.qty);
    final collected = sum(PalletEntryKind.collected);
    final base = (count?.qty ?? 0) + collected;
    out[name] = PalletBalance(
      counted: count?.qty,
      countDate: count?.date,
      collected: collected,
      losses: base <= 0 ? 0 : (base * kPalletLossRate).round(),
      adjusted: sum(PalletEntryKind.adjust),
      returned: sent.where((n) => n.agentName == name && after(n.noteDate)).fold(0, (s, n) => s + n.total),
    );
  }
  return out;
}

/// The average pallets a potato truck from [from] (a delivery note is a
/// truck): (average, trucks).
(double, int) palletsPerTruck(List<DeliveryNote> notes, {required String from}) {
  final trucks = [for (final n in notes) if (n.produceType == 'potato' && n.total > 0 && n.noteDate.compareTo(from) >= 0) n];
  if (trucks.isEmpty) return (0, 0);
  return (trucks.fold(0, (s, n) => s + n.total) / trucks.length, trucks.length);
}

/// Pallets sent loaded to each agent on the potato delivery notes: (this
/// season -- from [from] --, all), by name.
Map<String, (int, int)> palletsSentByAgent(List<DeliveryNote> notes, {required String from}) {
  final out = <String, (int, int)>{};
  for (final n in notes) {
    if (n.produceType != 'potato' || n.agentName == null || n.total == 0) continue;
    final (season, all) = out[n.agentName!] ?? (0, 0);
    out[n.agentName!] = (season + (n.noteDate.compareTo(from) >= 0 ? n.total : 0), all + n.total);
  }
  return Map.fromEntries(out.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())));
}
