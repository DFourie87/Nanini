import '../../core/supabase_client.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'game_breeding_models.dart';

/// Farms available for buffalo-keeping registration -- Doornbult doesn't
/// keep buffalo, so it's excluded here even though it's a valid farm
/// elsewhere in the app.
Future<List<Farm>> fetchBuffaloFarms() async {
  final farms = await EmployeesRepository().fetchFarms();
  return farms.where((f) => !f.name.toLowerCase().contains('doornbult')).toList();
}

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
