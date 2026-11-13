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

/// A figure of [palletsCollectedAndPaidFor].
enum PalletFigure { sent, collected, paidFor }

/// One line behind a figure: a delivery note, a collected entry or a pallet
/// invoice -- its date (yyyy-MM-dd), agent, what it is and its pallets.
class PalletLine {
  const PalletLine(this.date, this.agent, this.what, this.pallets);
  final String date;
  final String agent;
  final String what;
  final int pallets;
}

/// What [figure] is made of, from [from] (this harvest season), for [agent]
/// (null: every agent) -- newest first: the potato delivery notes (sent),
/// the Add collected entries (collected) or the agent's pallet invoices
/// (paid for). They add up to the figure in [palletsCollectedAndPaidFor].
List<PalletLine> palletLines(PalletFigure figure,
    {required List<DeliveryNote> notes,
    required List<PalletPurchase> entries,
    required List<PalletsPaidFor> paid,
    required String from,
    String? agent}) {
  bool mine(String name) => agent == null || name == agent;
  final out = switch (figure) {
    PalletFigure.sent => [
        for (final n in notes)
          if (n.produceType == 'potato' && n.agentName != null && n.total != 0 && n.noteDate.compareTo(from) >= 0 && mine(n.agentName!))
            PalletLine(n.noteDate, n.agentName!, 'Delivery note ${n.noteNumber ?? '-'}${(n.field ?? '').isEmpty ? '' : ' · ${n.field}'}', n.total),
      ],
    PalletFigure.collected => [
        for (final e in entries)
          if (e.kind == PalletEntryKind.collected && e.date.compareTo(from) >= 0 && mine(e.agentName))
            PalletLine(e.date, e.agentName, e.qty < 0 ? 'Returned empty${_why(e.description)}' : 'Collected${_why(e.description)}', e.qty),
      ],
    PalletFigure.paidFor => [
        for (final p in paid)
          if (p.date.compareTo(from) >= 0 && mine(p.agentName))
            PalletLine(p.date, p.agentName, 'Pallet invoice ${p.document} · R${p.amount.toStringAsFixed(2)}', p.qty),
      ],
  };
  return out..sort((a, b) => b.date.compareTo(a.date));
}

String _why(String? d) => (d ?? '').trim().isEmpty ? '' : ' · ${d!.trim()}';

/// Per agent, from [from] (this harvest season): pallets sent loaded (the
/// potato delivery notes, [sent]), collected (the Add collected entries; a
/// minus entry returned empty), paid for (its pallet invoices), and the
/// difference: collected - sent + paid for (minus: still out at the agent).
/// Agents with any of them, by name.
Map<String, (int sent, int collected, int paidFor, int difference)> palletsCollectedAndPaidFor(
    Map<String, int> sent, List<PalletPurchase> entries, List<PalletsPaidFor> paid,
    {required String from}) {
  final collected = <String, int>{};
  for (final e in entries.where((e) => e.kind == PalletEntryKind.collected && e.date.compareTo(from) >= 0)) {
    collected[e.agentName] = (collected[e.agentName] ?? 0) + e.qty;
  }
  final paidFor = <String, int>{};
  for (final p in paid.where((p) => p.date.compareTo(from) >= 0)) {
    paidFor[p.agentName] = (paidFor[p.agentName] ?? 0) + p.qty;
  }
  final names = {...sent.keys.where((k) => (sent[k] ?? 0) != 0), ...collected.keys, ...paidFor.keys}.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return {
    for (final n in names)
      n: (sent[n] ?? 0, collected[n] ?? 0, paidFor[n] ?? 0, (collected[n] ?? 0) - (sent[n] ?? 0) + (paidFor[n] ?? 0)),
  };
}

/// [agent]'s pallet movements from [from] (null: all), oldest first, as a
/// CSV's rows: each delivery note (returned to the agent), collected entry
/// and pallet invoice (paid for), with the difference after it (collected -
/// returned + paid for: minus is still out at the agent).
List<List<String>> palletMovementRows(String agent,
    {required List<DeliveryNote> notes, required List<PalletPurchase> entries, required List<PalletsPaidFor> paid, String? from}) {
  final since = from ?? '0000-01-01';
  List<PalletLine> of(PalletFigure f) => palletLines(f, notes: notes, entries: entries, paid: paid, from: since, agent: agent);
  final lines = [
    for (final l in of(PalletFigure.collected)) (l, PalletFigure.collected),
    for (final l in of(PalletFigure.sent)) (l, PalletFigure.sent),
    for (final l in of(PalletFigure.paidFor)) (l, PalletFigure.paidFor),
  ]..sort((a, b) => a.$1.date.compareTo(b.$1.date));
  var balance = 0;
  final rows = <List<String>>[
    ['Date', 'What', 'Collected', 'Returned', 'Paid for', 'Difference'],
  ];
  for (final (l, f) in lines) {
    balance += f == PalletFigure.sent ? -l.pallets : l.pallets;
    rows.add([
      l.date,
      l.what,
      f == PalletFigure.collected ? '${l.pallets}' : '',
      f == PalletFigure.sent ? '${l.pallets}' : '',
      f == PalletFigure.paidFor ? '${l.pallets}' : '',
      '$balance',
    ]);
  }
  int sum(PalletFigure f) => lines.where((x) => x.$2 == f).fold(0, (s, x) => s + x.$1.pallets);
  rows.add(['', 'Total', '${sum(PalletFigure.collected)}', '${sum(PalletFigure.sent)}', '${sum(PalletFigure.paidFor)}', '$balance']);
  return rows;
}
