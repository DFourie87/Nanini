import '../../core/supabase_client.dart';
import 'game_breeding_models.dart';

class GameBreedingRepository {
  Stream<List<GameEvent>> watchEvents() => sb
      .from('game_events')
      .stream(primaryKey: ['id'])
      .order('event_date')
      .map((rows) => rows.map(GameEvent.fromJson).toList());

  Future<void> addEvent(GameEvent e) => sb.from('game_events').insert(e.toInsert());

  Future<void> deleteEvent(String id) => sb.from('game_events').delete().eq('id', id);

  Stream<List<BuffaloRegistration>> watchRegistrations() =>
      sb.from('buffalo_registrations').stream(primaryKey: ['farm_id']).map((rows) => rows.map(BuffaloRegistration.fromJson).toList());

  Future<void> upsertRegistration(BuffaloRegistration r) =>
      sb.from('buffalo_registrations').upsert(r.toUpsert(), onConflict: 'farm_id');
}
