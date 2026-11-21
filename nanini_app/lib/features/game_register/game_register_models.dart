import '../../core/formatters.dart';

/// One species on a farm in a year's game register: the head counted at the
/// year end (28 February) and the value per head.
class GameCount {
  GameCount({this.id, required this.yearStart, required this.farm, required this.species, required this.head, required this.value, this.ord = 0});

  final String? id;
  final String yearStart;
  final String farm;
  final String species;
  final int head;
  final double value;
  final int ord;

  double get total => head * value;

  factory GameCount.fromJson(Map<String, dynamic> j) => GameCount(
    id: j['id'] as String?,
    yearStart: j['year_start'] as String,
    farm: j['farm'] as String,
    species: j['species'] as String,
    head: (j['head'] as num?)?.toInt() ?? 0,
    value: (j['value'] as num?)?.toDouble() ?? 0,
    ord: (j['ord'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toRow() => {'year_start': yearStart, 'farm': farm, 'species': species, 'head': head, 'value': value, 'ord': ord};

  GameCount copyWith({String? yearStart, int? head, double? value, int? ord}) => GameCount(
    id: yearStart == null ? id : null,
    yearStart: yearStart ?? this.yearStart,
    farm: farm,
    species: species,
    head: head ?? this.head,
    value: value ?? this.value,
    ord: ord ?? this.ord,
  );
}

/// The start (1 March, yyyy-MM-dd) of the financial year [iso] falls in.
String gameYearStart(String iso) {
  final d = DateTime.parse(iso);
  return toDateStr(DateTime(d.month >= 3 ? d.year : d.year - 1, 3, 1));
}

String previousYear(String yearStart) => toDateStr(DateTime(DateTime.parse(yearStart).year - 1, 3, 1));

/// A year's register: the farms in order, each with its species, the
/// totals and the fair value movement on last year.
class GameYear {
  GameYear(this.yearStart, this.rows, this.lastYear);

  final String yearStart;
  final List<GameCount> rows;
  final List<GameCount> lastYear;

  List<String> get farms {
    final out = <String>[];
    for (final r in [...rows]..sort((a, b) => a.ord.compareTo(b.ord))) {
      if (!out.contains(r.farm)) out.add(r.farm);
    }
    return out;
  }

  List<GameCount> of(String farm) => [
    for (final r in rows)
      if (r.farm == farm) r,
  ]..sort((a, b) => a.ord.compareTo(b.ord));
  double farmTotal(String farm) => of(farm).fold(0.0, (s, r) => s + r.total);
  int farmHead(String farm) => of(farm).fold(0, (s, r) => s + r.head);
  double get total => rows.fold(0.0, (s, r) => s + r.total);
  double get lastTotal => lastYear.fold(0.0, (s, r) => s + r.total);

  /// The fair value movement (billike waarde): this year's total less last year's.
  double? get fairValueMovement => lastYear.isEmpty ? null : total - lastTotal;

  /// Last year's head of [species] on [farm], or null.
  int? lastHead(String farm, String species) {
    for (final r in lastYear) {
      if (r.farm == farm && r.species == species) return r.head;
    }
    return null;
  }
}
