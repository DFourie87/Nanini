import '../../core/supabase_client.dart';
import 'truck_models.dart';

class TruckRepository {
  Stream<List<TruckBooking>> watchBookings() =>
      sb.from('truck_bookings').stream(primaryKey: ['id']).order('start_at').map((r) => r.map(TruckBooking.fromJson).toList());

  Future<String?> fetchTrackingUrl() async {
    final row = await sb.from('truck_settings').select().eq('id', 1).maybeSingle();
    return row?['tracking_url'] as String?;
  }

  Future<void> setTrackingUrl(String url) => sb.from('truck_settings').upsert({'id': 1, 'tracking_url': url});

  Future<void> addBooking(TruckBooking b) => sb.from('truck_bookings').insert(b.toInsert());

  Future<void> updateBooking(String id, TruckBooking b) => sb.from('truck_bookings').update(b.toInsert()).eq('id', id);

  Future<void> deleteBooking(String id) => sb.from('truck_bookings').delete().eq('id', id);

  bool overlaps(TruckBooking candidate, List<TruckBooking> existing, {String? excludeId}) {
    return existing.any((b) => b.id != excludeId && candidate.startAt.isBefore(b.endAt) && candidate.endAt.isAfter(b.startAt));
  }
}
