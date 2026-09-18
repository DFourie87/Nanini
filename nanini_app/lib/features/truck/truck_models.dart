class TruckBooking {
  TruckBooking({
    required this.id,
    required this.startAt,
    required this.endAt,
    this.locationText,
    this.lat,
    this.lng,
    this.bookedBy,
    this.notes,
  });
  final String id;
  final DateTime startAt;
  final DateTime endAt;
  final String? locationText;
  final double? lat;
  final double? lng;
  final String? bookedBy;
  final String? notes;

  factory TruckBooking.fromJson(Map<String, dynamic> j) => TruckBooking(
        id: j['id'] as String,
        startAt: DateTime.parse(j['start_at'] as String),
        endAt: DateTime.parse(j['end_at'] as String),
        locationText: j['location_text'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        bookedBy: j['booked_by'] as String?,
        notes: j['notes'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        'start_at': startAt.toIso8601String(),
        'end_at': endAt.toIso8601String(),
        'location_text': locationText,
        'lat': lat,
        'lng': lng,
        'booked_by': bookedBy,
        'notes': notes,
      };
}
