import '../delivery/delivery_models.dart';
import 'sales_customers_models.dart';
import 'sales_models.dart';

/// Why pallets were packed but not sent to market.
const kUnsentReasons = ['No market for this size', 'Last truck of the week full', 'Other'];

/// Pallets packed from a field but not sent to market (no market for the
/// size, or the week's last truck was full). They count in the bags
/// harvested per field, never in sales or average prices.
class UnsentPallets {
  UnsentPallets({this.id, required this.date, required this.field, this.pallets = const {}, this.bags = const {}, this.reason, this.note});
  final String? id;
  final String date;
  final String field;

  /// Pallet size key -> full pallets.
  final Map<String, int> pallets;

  /// Pallet size key -> loose bags (a part pallet).
  final Map<String, int> bags;
  final String? reason;
  final String? note;

  /// Pallet size key -> bags, full pallets and loose bags together.
  Map<String, int> get bagsBySize => {
        for (final s in kPalletSizes)
          if ((pallets[s.key] ?? 0) * s.bagsPerPallet + (bags[s.key] ?? 0) > 0) s.key: (pallets[s.key] ?? 0) * s.bagsPerPallet + (bags[s.key] ?? 0),
      };
  int get totalBags => bagsBySize.values.fold(0, (a, b) => a + b);
  int get totalPallets => pallets.values.fold(0, (a, b) => a + b);

  static Map<String, int> _counts(Object? j) => {
        for (final e in ((j as Map?) ?? const {}).entries)
          if (((e.value as num?)?.toInt() ?? 0) > 0) e.key as String: (e.value as num).toInt(),
      };

  factory UnsentPallets.fromJson(Map<String, dynamic> j) => UnsentPallets(
        id: j['id'] as String,
        date: j['packed_date'] as String,
        field: j['field'] as String,
        pallets: _counts(j['pallets']),
        bags: _counts(j['bags']),
        reason: j['reason'] as String?,
        note: j['note'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        'packed_date': date,
        'field': field,
        'pallets': pallets,
        'bags': bags,
        'reason': reason,
        'note': note,
      };
}

/// Bags of each pallet size on a potato delivery note: its full pallets and
/// its mixed pallets.
Map<String, int> potatoNoteBags(DeliveryNote n) {
  final out = <String, int>{};
  for (final s in kPalletSizes) {
    final count = (n.pallets[s.key] as num?)?.toInt() ?? 0;
    if (count > 0) out[s.key] = count * s.bagsPerPallet;
  }
  for (final mp in n.mixedPallets) {
    for (final e in ((mp as Map?) ?? const {}).entries) {
      final bags = (e.value as num?)?.toInt() ?? 0;
      if (bags > 0) out[e.key as String] = (out[e.key as String] ?? 0) + bags;
    }
  }
  return out;
}

/// One field's potatoes over a period.
class PotatoField {
  PotatoField(this.name);
  final String name;

  /// Pallet size key -> bags sent on approved delivery notes.
  final sent = <String, int>{};

  /// Pallet size key -> bags packed but not sent.
  final unsent = <String, int>{};
  double nett = 0;
  double bagsSold = 0;

  int get sentBags => sent.values.fold(0, (a, b) => a + b);
  int get unsentBags => unsent.values.fold(0, (a, b) => a + b);
  int get harvestedBags => sentBags + unsentBags;

  /// Nett per bag sold; null when none were sold.
  double? get avgPrice => bagsSold > 0 ? nett / bagsSold : null;
}

/// Potatoes per field: the bags harvested (sent to market on approved
/// delivery notes, plus those packed but not sent) and what was sold.
///
/// An account sale has no field of its own. It goes on a field through the
/// delivery note its agent's payment summary gives for it (the note number
/// on the truck); until it is on a payment summary, or when the note isn't
/// one of ours, its field is not known. Packed-not-sent bags are never in
/// the sales, so they don't touch the nett or the average prices.
class PotatoFields {
  PotatoFields({
    required List<DeliveryNote> notes,
    required List<UnsentPallets> unsent,
    required List<SalesReport> reports,
    required List<SalesLineItem> items,
    required List<CustomerPayment> payments,
    required List<Customer> customers,
    required DateTime from,
    required DateTime to,
    String? klass,
    required Map<String, String> sizeClass,
  }) {
    bool inRange(String date) {
      final d = DateTime.tryParse(date);
      return d != null && !d.isBefore(from) && !d.isAfter(to);
    }

    bool sizeWanted(String key) => klass == null || sizeClass[key] == klass;
    PotatoField field(String name) => _fields.putIfAbsent(name, () => PotatoField(name));

    final potatoNotes = notes.where((n) => n.produceType == 'potato' && n.isApproved && (n.field ?? '').isNotEmpty).toList();
    for (final n in potatoNotes.where((n) => inRange(n.noteDate))) {
      final f = field(n.field!);
      for (final e in potatoNoteBags(n).entries) {
        if (sizeWanted(e.key)) f.sent[e.key] = (f.sent[e.key] ?? 0) + e.value;
      }
    }
    for (final u in unsent.where((u) => inRange(u.date))) {
      final f = field(u.field);
      for (final e in u.bagsBySize.entries) {
        if (sizeWanted(e.key)) f.unsent[e.key] = (f.unsent[e.key] ?? 0) + e.value;
      }
    }

    // Account sale (agent + number) -> the field of the delivery note paid with it.
    final fieldByNote = {for (final n in potatoNotes) if (n.noteNumber != null) n.noteNumber!: n.field!};
    final agentById = {for (final c in customers) c.id: c.agent};
    final fieldBySale = <String, String>{};
    for (final p in payments) {
      final agent = agentById[p.customerId];
      if (agent == null) continue;
      for (final l in p.lines) {
        final m = RegExp(r'^\s*(\d+)\s*$').firstMatch(l.deliveryNote ?? '');
        final f = m == null ? null : fieldByNote[int.parse(m.group(1)!)];
        if (f != null) fieldBySale.putIfAbsent('$agent|${l.reportNumber}', () => f);
      }
    }

    final reportsById = {for (final r in reports) if (r.id != null) r.id!: r};
    for (final li in items) {
      final r = reportsById[li.reportId];
      if (r == null || (klass != null && li.effectiveClass != klass)) continue;
      // The same nett as Sales' own total, shared over the report's lines by their gross.
      final nett = r.grossTotal > 0 ? li.grossAmount / r.grossTotal * r.nettSales : 0.0;
      final bags = li.units ?? 0;
      final name = fieldBySale['${r.agent}|${baseReportNumber(r.reportNumber)}'];
      if (name == null) {
        unknownNett += nett;
        unknownBags += bags;
      } else {
        final f = field(name);
        f.nett += nett;
        f.bagsSold += bags;
      }
    }
  }

  final _fields = <String, PotatoField>{};

  /// Nett and bags of account sales whose field isn't known (yet).
  double unknownNett = 0;
  double unknownBags = 0;

  /// In field order (Field 1..8, then any other name).
  List<PotatoField> get fields => _fields.values.toList()
    ..sort((a, b) {
      final ai = kFieldNames.indexOf(a.name);
      final bi = kFieldNames.indexOf(b.name);
      if (ai != bi) {
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      }
      return a.name.compareTo(b.name);
    });

  int get sentBags => _fields.values.fold(0, (s, f) => s + f.sentBags);
  int get unsentBags => _fields.values.fold(0, (s, f) => s + f.unsentBags);
  int get harvestedBags => sentBags + unsentBags;
  double get linkedNett => _fields.values.fold(0.0, (s, f) => s + f.nett);
  double get totalNett => linkedNett + unknownNett;
  double get totalBagsSold => _fields.values.fold(0.0, (s, f) => s + f.bagsSold) + unknownBags;
}
