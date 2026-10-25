enum GameEventType { birth, death, sale, purchase, weighing, health, campMove }

String gameEventTypeLabel(GameEventType t) => switch (t) {
      GameEventType.birth => 'Birth',
      GameEventType.death => 'Death',
      GameEventType.sale => 'Sale',
      GameEventType.purchase => 'Purchase',
      GameEventType.weighing => 'Weighing',
      GameEventType.health => 'Health',
      GameEventType.campMove => 'Camp Move',
    };

/// Event types where the camp an animal is in gets recorded -- its first
/// camp (birth/purchase) or a later move between camps.
bool gameEventCarriesCamp(GameEventType t) => t == GameEventType.birth || t == GameEventType.purchase || t == GameEventType.campMove;

GameEventType gameEventTypeFromString(String? s) =>
    GameEventType.values.firstWhere((t) => t.name == s, orElse: () => GameEventType.health);

class GameEvent {
  GameEvent({
    this.id,
    required this.species,
    this.tagNumber,
    required this.eventType,
    required this.eventDate,
    this.weightKg,
    this.sireTag,
    this.damTag,
    this.camp,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String? id;
  final String species;
  final String? tagNumber;
  final GameEventType eventType;
  final String eventDate;
  final double? weightKg;

  /// Only meaningful on a birth event -- the parents' tag numbers, used to
  /// walk the bloodline back through earlier birth events.
  final String? sireTag;
  final String? damTag;

  /// Which camp the animal was in as of this event (birth/purchase/camp
  /// move) -- an animal's current camp is whichever of these is most recent.
  final String? camp;
  final String? notes;
  final DateTime createdAt;

  factory GameEvent.fromJson(Map<String, dynamic> j) => GameEvent(
        id: j['id'] as String,
        species: j['species'] as String,
        tagNumber: j['tag_number'] as String?,
        eventType: gameEventTypeFromString(j['event_type'] as String?),
        eventDate: j['event_date'] as String,
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
        sireTag: j['sire_tag'] as String?,
        damTag: j['dam_tag'] as String?,
        camp: j['camp'] as String?,
        notes: j['notes'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String? ?? DateTime.now().toIso8601String()),
      );

  Map<String, dynamic> toInsert() => {
        'species': species,
        'tag_number': tagNumber,
        'event_type': eventType.name,
        'event_date': eventDate,
        'weight_kg': weightKg,
        'sire_tag': sireTag,
        'dam_tag': damTag,
        'camp': camp,
        'notes': notes,
      };
}

/// The Dept. of Agriculture "Registration of Land for the Keeping of
/// Buffalo" -- unlike the Hunting module's P3 exemption certificates, this
/// registration doesn't expire, so it's just reference data. One per farm
/// (each property registered to keep buffalo has its own registration
/// number), not per species.
class BuffaloRegistration {
  BuffaloRegistration({
    required this.farmId,
    this.registrationNumber,
    this.holderName,
    this.farmDescription,
    this.applicationDate,
    this.certifiedDate,
    this.spifStatus,
    this.fmdStatus,
    this.corridorDiseaseStatus,
  });
  final String farmId;
  final String? registrationNumber;
  final String? holderName;
  final String? farmDescription;
  final String? applicationDate;
  final String? certifiedDate;
  final String? spifStatus;
  final String? fmdStatus;
  final String? corridorDiseaseStatus;

  factory BuffaloRegistration.fromJson(Map<String, dynamic> j) => BuffaloRegistration(
        farmId: j['farm_id'] as String,
        registrationNumber: j['registration_number'] as String?,
        holderName: j['holder_name'] as String?,
        farmDescription: j['farm_description'] as String?,
        applicationDate: j['application_date'] as String?,
        certifiedDate: j['certified_date'] as String?,
        spifStatus: j['spif_status'] as String?,
        fmdStatus: j['fmd_status'] as String?,
        corridorDiseaseStatus: j['corridor_disease_status'] as String?,
      );

  Map<String, dynamic> toUpsert() => {
        'farm_id': farmId,
        'registration_number': registrationNumber,
        'holder_name': holderName,
        'farm_description': farmDescription,
        'application_date': applicationDate,
        'certified_date': certifiedDate,
        'spif_status': spifStatus,
        'fmd_status': fmdStatus,
        'corridor_disease_status': corridorDiseaseStatus,
      };
}

/// The most recent camp-carrying event (birth/purchase/camp move) for
/// `tag`, or null if the animal's camp was never recorded.
String? currentCampFor(String tag, Iterable<GameEvent> events) {
  final campEvents = events.where((e) => e.tagNumber == tag && gameEventCarriesCamp(e.eventType) && (e.camp ?? '').isNotEmpty).toList()
    ..sort((a, b) {
      final byDate = a.eventDate.compareTo(b.eventDate);
      return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
    });
  return campEvents.isEmpty ? null : campEvents.last.camp;
}

/// An animal in the herd register (Bloodline > Herd): on the farm -- ours
/// or kept here for someone else -- or an ancestor known only from the
/// pedigrees. Its parents by tag, so the family tree walks back past
/// animals never born here.
class GameAnimal {
  GameAnimal({
    this.id,
    required this.species,
    required this.tag,
    this.name,
    this.sex,
    this.born,
    this.owner,
    this.onFarm = true,
    this.status = 'alive',
    this.sire,
    this.dam,
    this.horns,
    this.microchip,
    this.notes,
    this.camp,
    this.subspecies,
    this.bloodline,
    this.sci,
    this.measured,
    this.inCalfTo,
    this.source,
    this.dna,
    this.photo,
    this.focusX,
    this.focusY,
  });
  final String? id;
  final String species;
  final String tag;
  final String? name;

  /// 'F', 'M', or null (not known yet).
  final String? sex;

  /// A year ("2019") or a date (yyyy-MM-dd).
  final String? born;

  /// Whose it is: 'Nanini', or whoever owns an animal kept here.
  final String? owner;

  /// False: an ancestor from the pedigrees, never on the farm.
  final bool onFarm;

  /// 'alive', 'dead' or 'sold'.
  final String status;
  final String? sire;
  final String? dam;
  final String? horns;
  final String? microchip;
  final String? notes;
  final String? camp;

  /// 'African', 'East African' or a cross.
  final String? subspecies;
  final String? bloodline;

  /// "75.75 (61.75 + 7 + 7)": tip to tip + boss L + boss R.
  final String? sci;

  /// When the horns were last measured (yyyy-MM-dd).
  final String? measured;
  final String? inCalfTo;

  /// Where it came from (auction, lot) or "Bred on farm".
  final String? source;
  final String? dna;

  /// Its photo in the game-photos storage bucket.
  final String? photo;

  /// Where the head is on [photo] (-1 left/top .. 1 right/bottom); photos are
  /// cropped around it. Null: the upper middle, where head and horns usually are.
  final double? focusX;
  final double? focusY;

  /// The photo's crop centre (x, y), each -1..1.
  (double, double) get focus => (focusX ?? 0, focusY ?? -0.25);

  /// Not pure African (East African or a cross): outside the African breeding plan.
  bool get notAfrican => (subspecies ?? '').isNotEmpty && subspecies != 'African';

  bool get isAlive => status == 'alive';

  /// "Kyle × R65", "Kyle × ?", or null when neither parent is known.
  String? get parents => (sire ?? '').isEmpty && (dam ?? '').isEmpty ? null : '${(sire ?? '').isEmpty ? '?' : sire} × ${(dam ?? '').isEmpty ? '?' : dam}';

  /// The tag, with the name when it's not the same: "Eben", "SPO20".
  String get label => (name ?? '').isEmpty || name == tag ? tag : '$tag ($name)';

  factory GameAnimal.fromJson(Map<String, dynamic> j) => GameAnimal(
        id: j['id'] as String?,
        species: j['species'] as String? ?? 'Buffalo',
        tag: j['tag'] as String,
        name: j['name'] as String?,
        sex: j['sex'] as String?,
        born: j['born'] as String?,
        owner: j['owner'] as String?,
        onFarm: j['on_farm'] as bool? ?? true,
        status: j['status'] as String? ?? 'alive',
        sire: j['sire'] as String?,
        dam: j['dam'] as String?,
        horns: j['horns'] as String?,
        microchip: j['microchip'] as String?,
        notes: j['notes'] as String?,
        camp: j['camp'] as String?,
        subspecies: j['subspecies'] as String?,
        bloodline: j['bloodline'] as String?,
        sci: j['sci'] as String?,
        measured: j['measured'] as String?,
        inCalfTo: j['in_calf_to'] as String?,
        source: j['source'] as String?,
        dna: j['dna'] as String?,
        photo: j['photo'] as String?,
        focusX: (j['photo_focus_x'] as num?)?.toDouble(),
        focusY: (j['photo_focus_y'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toUpsert() => {
        'species': species,
        'tag': tag,
        'name': name,
        'sex': sex,
        'born': born,
        'owner': owner,
        'on_farm': onFarm,
        'status': status,
        'sire': sire,
        'dam': dam,
        'horns': horns,
        'microchip': microchip,
        'notes': notes,
        'camp': camp,
        'subspecies': subspecies,
        'bloodline': bloodline,
        'sci': sci,
        'measured': measured,
        'in_calf_to': inCalfTo,
        'source': source,
        'dna': dna,
        'photo': photo,
      };
}

/// Mating guide: a cow and bull, the calf's inbreeding (Wright's F, %) and
/// whether that mating is best, acceptable or to be avoided.
class GameMating {
  GameMating({required this.cowTag, required this.bullTag, required this.calfInbreeding, required this.advice, this.shared, this.note});
  final String cowTag;
  final String bullTag;
  final double calfInbreeding;

  /// 'best', 'acceptable' or 'avoid'.
  final String advice;

  /// Ancestors the cow and bull share.
  final String? shared;
  final String? note;

  factory GameMating.fromJson(Map<String, dynamic> j) => GameMating(
        cowTag: j['cow_tag'] as String,
        bullTag: j['bull_tag'] as String,
        calfInbreeding: (j['calf_inbreeding'] as num).toDouble(),
        advice: j['advice'] as String,
        shared: j['shared'] as String?,
        note: j['note'] as String?,
      );
}

/// Each tag's parents (sire, dam): the herd register's, with a logged birth
/// winning where both have them.
Map<String, (String?, String?)> parentsByTag(Iterable<GameAnimal> animals, Iterable<GameEvent> events) => {
      for (final a in animals) a.tag: (a.sire, a.dam),
      for (final e in events)
        if (e.eventType == GameEventType.birth && (e.tagNumber ?? '').isNotEmpty && ((e.sireTag ?? '').isNotEmpty || (e.damTag ?? '').isNotEmpty))
          e.tagNumber!: (e.sireTag, e.damTag),
    };

/// When an animal was born and its age on [today], as the herd lists it:
/// "30/01/15 (11Y8M)"; a year only: "2019 (7Y)"; null when not known.
String? bornWithAge(String? born, DateTime today) {
  if ((born ?? '').isEmpty) return null;
  final d = born!.length == 10 ? DateTime.tryParse(born) : null;
  if (d == null) {
    final y = int.tryParse(born);
    return y == null ? born : '$born (${today.year - y < 0 ? 0 : today.year - y}Y)';
  }
  var months = (today.year - d.year) * 12 + today.month - d.month - (today.day < d.day ? 1 : 0);
  if (months < 0) months = 0;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${two(d.year % 100)} (${months ~/ 12}Y${months % 12}M)';
}

/// [cow]'s calves, oldest first: the register's animals with her as dam,
/// and births logged in the app that aren't in the register yet.
List<GameAnimal> calvesOf(GameAnimal cow, Iterable<GameAnimal> animals, Iterable<GameEvent> events) {
  final calves = [for (final a in animals) if (a.dam == cow.tag && a.tag != cow.tag) a];
  final known = {for (final c in calves) c.tag};
  for (final e in events) {
    final tag = e.tagNumber ?? '';
    if (e.eventType != GameEventType.birth || e.damTag != cow.tag || tag.isEmpty || known.contains(tag)) continue;
    known.add(tag);
    calves.add(GameAnimal(species: cow.species, tag: tag, born: e.eventDate, owner: cow.owner, sire: e.sireTag, dam: cow.tag, camp: e.camp, notes: e.notes));
  }
  // A year ("2019") sorts before that year's dates; unknown last.
  return calves..sort((x, y) => (x.born ?? '9999').compareTo(y.born ?? '9999'));
}

/// Inbreeding from the pedigrees (Wright): a calf's inbreeding is the
/// kinship of its sire and dam, traced through every shared ancestor.
/// Unknown parents count as unrelated (so the true figure can only be
/// higher). [parents]: tag -> (sire, dam).
class Pedigree {
  Pedigree(this.parents);
  final Map<String, (String?, String?)> parents;
  final _ancestors = <String, Set<String>>{};
  final _kinship = <String, double>{};

  (String?, String?) _of(String tag) {
    final (s, d) = parents[tag] ?? (null, null);
    return ((s ?? '').isEmpty ? null : s, (d ?? '').isEmpty ? null : d);
  }

  /// Every ancestor of [tag].
  Set<String> ancestors(String tag) => _ancestors[tag] ??= () {
        final out = <String>{};
        final todo = [tag];
        while (todo.isNotEmpty) {
          final (s, d) = _of(todo.removeLast());
          for (final p in [s, d]) {
            if (p != null && out.add(p)) todo.add(p);
          }
        }
        return out;
      }();

  /// The kinship of [a] and [b]: the inbreeding of a calf of theirs.
  double kinship(String? a, String? b, [int depth = 0]) {
    if (a == null || b == null || depth > 40) return 0;
    if (a == b) {
      final (s, d) = _of(a);
      return 0.5 * (1 + kinship(s, d, depth + 1));
    }
    // Follow back the one that isn't an ancestor of the other.
    if (ancestors(b).contains(a)) (a, b) = (b, a);
    final key = '$a|$b';
    final known = _kinship[key];
    if (known != null) return known;
    final (s, d) = _of(a);
    return _kinship[key] = 0.5 * (kinship(s, b, depth + 1) + kinship(d, b, depth + 1));
  }

  /// [tag]'s own inbreeding (its sire and dam's kinship).
  double inbreeding(String tag) {
    final (s, d) = _of(tag);
    return kinship(s, d);
  }

  /// The ancestors [a] and [b] share (or one of them, if it's behind the
  /// other) -- the nearest ones only, not those behind them.
  List<String> shared(String a, String b) {
    final common = ({a, ...ancestors(a)}).intersection({b, ...ancestors(b)});
    return [for (final c in common) if (!common.any((o) => o != c && ancestors(o).contains(c))) c]..sort();
  }
}
