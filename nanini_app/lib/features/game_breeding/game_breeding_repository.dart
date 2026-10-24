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

  /// The herd register (game_animals.sql).
  Stream<List<GameAnimal>> watchAnimals(String species) => sb
      .from('game_animals')
      .stream(primaryKey: ['id'])
      .eq('species', species)
      .map((rows) => rows.map(GameAnimal.fromJson).toList()..sort((a, b) => a.tag.toLowerCase().compareTo(b.tag.toLowerCase())));

  /// A new animal, or changes to one (its tag too).
  Future<void> saveAnimal(GameAnimal a) =>
      a.id == null ? sb.from('game_animals').insert(a.toUpsert()) : sb.from('game_animals').update(a.toUpsert()).eq('id', a.id!);

  Future<void> deleteAnimal(String id) => sb.from('game_animals').delete().eq('id', id);

  /// The mating guide (game_animals.sql).
  Future<List<GameMating>> fetchMatings(String species) async {
    final rows = await sb.from('game_matings').select().eq('species', species);
    return (rows as List).map((r) => GameMating.fromJson(r as Map<String, dynamic>)).toList();
  }
}
