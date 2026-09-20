const kGameSpecies = ['Buffalo', 'Sable'];

enum GameEventType { birth, death, sale, purchase, weighing, health }

String gameEventTypeLabel(GameEventType t) => switch (t) {
      GameEventType.birth => 'Birth',
      GameEventType.death => 'Death',
      GameEventType.sale => 'Sale',
      GameEventType.purchase => 'Purchase',
      GameEventType.weighing => 'Weighing',
      GameEventType.health => 'Health',
    };

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
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String? id;
  final String species;
  final String? tagNumber;
  final GameEventType eventType;
  final String eventDate;
  final double? weightKg;
  final String? notes;
  final DateTime createdAt;

  factory GameEvent.fromJson(Map<String, dynamic> j) => GameEvent(
        id: j['id'] as String,
        species: j['species'] as String,
        tagNumber: j['tag_number'] as String?,
        eventType: gameEventTypeFromString(j['event_type'] as String?),
        eventDate: j['event_date'] as String,
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
        notes: j['notes'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String? ?? DateTime.now().toIso8601String()),
      );

  Map<String, dynamic> toInsert() => {
        'species': species,
        'tag_number': tagNumber,
        'event_type': eventType.name,
        'event_date': eventDate,
        'weight_kg': weightKg,
        'notes': notes,
      };
}
