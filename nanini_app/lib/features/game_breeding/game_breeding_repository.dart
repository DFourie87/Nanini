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

  /// Some of an animal's details only (e.g. its status or camp after a
  /// logged event).
  Future<void> updateAnimal(String id, Map<String, dynamic> fields) => sb.from('game_animals').update(fields).eq('id', id);

  Future<void> deleteAnimal(String id) => sb.from('game_animals').delete().eq('id', id);

  /// The mating guide (game_animals.sql).
  Future<List<GameMating>> fetchMatings(String species) async {
    final rows = await sb.from('game_matings').select().eq('species', species);
    return (rows as List).map((r) => GameMating.fromJson(r as Map<String, dynamic>)).toList();
  }

  static const photoBucket = 'game-photos';

  /// A photo is good enough for the bloodline book when its short side is at
  /// least this (the books' own photos are 900 × 600).
  static const goodPhotoSide = 600;

  /// Whether a newer photo ([w] × [h]) should replace the animal's current
  /// one ([oldW] × [oldH], null: none or not known): when it's good enough
  /// for the book, or about as good as the current one (at least 80% of its
  /// size) -- then the latest wins.
  static bool betterPhoto(int w, int h, {int? oldW, int? oldH}) {
    final side = w < h ? w : h;
    if (side >= goodPhotoSide || oldW == null || oldH == null) return true;
    return side >= 0.8 * (oldW < oldH ? oldW : oldH);
  }

  /// Keeps [bytes] ([width] × [height]) as a photo of [tag] (game_photos) and
  /// makes it the animal's photo when there is none yet, when it's better
  /// ([betterPhoto]) or when [force]d. An ancestor not in the register yet
  /// is added (not on the farm). Returns whether it became the animal's photo.
  Future<bool> addPhoto(String species, String tag, Uint8List bytes,
      {required int width, required int height, String? id, String? current, String extension = 'jpg', String source = 'App', bool force = false}) async {
    // Storage keys: letters, digits, "-" and "_" only; the time keeps each photo.
    final safe = tag.replaceAll(RegExp(r'[^A-Za-z0-9-]+'), '_');
    final ext = extension.toLowerCase() == 'png' ? 'png' : 'jpg';
    final path = '$species/$safe-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}.$ext';
    await sb.storage.from(photoBucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'));
    await sb.from('game_photos').insert({'species': species, 'tag': tag, 'path': path, 'width': width, 'height': height, 'source': source});
    var use = force || current == null;
    if (!use) {
      final old = await sb.from('game_photos').select('width, height').eq('path', current).maybeSingle();
      use = betterPhoto(width, height, oldW: (old?['width'] as num?)?.toInt(), oldH: (old?['height'] as num?)?.toInt());
    }
    if (!use) return false;
    await usePhoto(species, tag, path, id: id);
    return true;
  }

  /// Makes [path] the photo of [tag] (adding the tag as an ancestor if it's
  /// not in the register).
  Future<void> usePhoto(String species, String tag, String path, {String? id}) async {
    // A new photo: its focus starts at the upper middle again.
    final row = {'photo': path, 'photo_focus_x': null, 'photo_focus_y': null};
    if (id != null) {
      await sb.from('game_animals').update(row).eq('id', id);
    } else {
      await sb.from('game_animals').upsert({'species': species, 'tag': tag, 'on_farm': false}, onConflict: 'species,tag', ignoreDuplicates: true);
      await sb.from('game_animals').update(row).eq('species', species).eq('tag', tag);
    }
  }

  /// Where the head is on the animal's photo (each -1..1): the crop centre.
  Future<void> setFocus(String id, double x, double y) =>
      sb.from('game_animals').update({'photo_focus_x': x, 'photo_focus_y': y}).eq('id', id);

  /// Deletes the animal's photo; the most recent other photo of it (if any)
  /// takes its place.
  Future<void> removePhoto(GameAnimal a) async {
    final path = a.photo!;
    await sb.storage.from(photoBucket).remove([path]);
    await sb.from('game_photos').delete().eq('path', path);
    final rest = await sb.from('game_photos').select('path').eq('species', a.species).eq('tag', a.tag).order('added_at', ascending: false).limit(1);
    await sb
        .from('game_animals')
        .update({'photo': (rest as List).isEmpty ? null : rest.first['path'], 'photo_focus_x': null, 'photo_focus_y': null}).eq('id', a.id!);
  }

  /// The most recently added photo of [tag], if any.
  Future<String?> latestPhoto(String species, String tag) async {
    final rows = await sb.from('game_photos').select('path').eq('species', species).eq('tag', tag).order('added_at', ascending: false).limit(1);
    return (rows as List).isEmpty ? null : rows.first['path'] as String;
  }

  /// A photo's bytes (for the bloodline book).
  Future<Uint8List> downloadPhoto(String path) => sb.storage.from(photoBucket).download(path);

  /// Links to show the photos at [paths] (a day long).
  Future<Map<String, String>> photoUrls(List<String> paths) async {
    if (paths.isEmpty) return {};
    final signed = await sb.storage.from(photoBucket).createSignedUrlsResult(paths, 60 * 60 * 24);
    return {for (final s in signed.whereType<SignedUrlSuccess>()) s.path: s.signedUrl};
  }
}
