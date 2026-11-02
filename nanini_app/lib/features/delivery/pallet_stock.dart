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
