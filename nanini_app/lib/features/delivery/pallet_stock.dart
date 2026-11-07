import 'delivery_models.dart';

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

/// Pallets an agent paid for instead of returning them (Green Network's
/// pallet invoice, kept with its account sale as sales_deductions kind
/// "pallets").
class PalletsPaidFor {
  const PalletsPaidFor({required this.agentName, required this.qty, required this.date, required this.document, required this.amount});
  final String agentName;
  final int qty;

  /// yyyy-MM-dd (its account sale's).
  final String date;

  /// The agent's number for it (IN160836), or its label.
  final String document;

  /// Incl. VAT.
  final double amount;
}

/// The buyer's own number for pallets it paid for, from the deduction's
/// label ("Pallets paid for: 31 PALLET @ R65 INCL (IN160836)" -> IN160836).
String? palletInvoiceNumber(String label) => RegExp(r'\(([A-Z]{1,4}\d{3,})\)\s*$').firstMatch(label.trim())?.group(1);

/// How many pallets a pallet invoice's line is for: "Pallets paid for: 31
/// PALLET @ R65 INCL (IN160836)" -> 31; null when it doesn't say.
int? palletCount(String label) {
  final m = RegExp(r'(\d+)\s*PALLETS?\b', caseSensitive: false).firstMatch(label);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Per agent: pallets collected (the Add collected entries; a minus entry
/// returned empty), pallets it paid for, and the difference (collected less
/// paid for). Agents with either, by name.
Map<String, (int collected, int paidFor, int difference)> palletsCollectedAndPaidFor(List<PalletPurchase> entries, List<PalletsPaidFor> paid) {
  final collected = <String, int>{};
  for (final e in entries.where((e) => e.kind == PalletEntryKind.collected)) {
    collected[e.agentName] = (collected[e.agentName] ?? 0) + e.qty;
  }
  final paidFor = <String, int>{};
  for (final p in paid) {
    paidFor[p.agentName] = (paidFor[p.agentName] ?? 0) + p.qty;
  }
  final names = {...collected.keys, ...paidFor.keys}.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return {
    for (final n in names) n: (collected[n] ?? 0, paidFor[n] ?? 0, (collected[n] ?? 0) - (paidFor[n] ?? 0)),
  };
}
