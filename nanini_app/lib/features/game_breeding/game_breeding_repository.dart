import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  static const photoBucket = 'game-photos';

  /// Stores [bytes] as [tag]'s photo and puts it on the animal -- an
  /// ancestor not in the register yet is added (not on the farm).
  Future<void> setPhoto(String species, String tag, Uint8List bytes, {String? id, String? oldPath, String extension = 'jpg'}) async {
    // Storage keys: letters, digits, "-" and "_" only, plus a short hash so
    // "Tag 65" and "Tag_65" (or "¹Lr2-21" and "Lr2-21") stay apart.
    final safe = tag.replaceAll(RegExp(r'[^A-Za-z0-9-]+'), '_');
    final hash = base64Url.encode(utf8.encode(tag)).hashCode.toUnsigned(32).toRadixString(36);
    final ext = extension.toLowerCase() == 'png' ? 'png' : 'jpg';
    final path = '$species/$safe-$hash.$ext';
    await sb.storage.from(photoBucket).uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg', upsert: true));
    if (id != null) {
      await sb.from('game_animals').update({'photo': path}).eq('id', id);
    } else {
      await sb.from('game_animals').upsert({'species': species, 'tag': tag, 'on_farm': false, 'photo': path}, onConflict: 'species,tag', ignoreDuplicates: true);
      await sb.from('game_animals').update({'photo': path}).eq('species', species).eq('tag', tag);
    }
    if (oldPath != null && oldPath != path) await sb.storage.from(photoBucket).remove([oldPath]);
  }

  Future<void> removePhoto(String id, String path) async {
    await sb.from('game_animals').update({'photo': null}).eq('id', id);
    await sb.storage.from(photoBucket).remove([path]);
  }

  /// Links to show the photos at [paths] (a day long).
  Future<Map<String, String>> photoUrls(List<String> paths) async {
    if (paths.isEmpty) return {};
    final signed = await sb.storage.from(photoBucket).createSignedUrlsResult(paths, 60 * 60 * 24);
    return {for (final s in signed.whereType<SignedUrlSuccess>()) s.path: s.signedUrl};
  }
}
