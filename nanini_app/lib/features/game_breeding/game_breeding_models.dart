const kGameSpecies = ['Buffalo', 'Sable'];

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
