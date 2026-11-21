import '../../core/live_rows.dart';
import '../../core/supabase_client.dart';
import 'game_register_models.dart';

/// The game register (docs/sql/vat_control.sql), and the buffalo register to compare.
class GameRegisterRepository {
  Future<List<GameCount>> fetchAll() async => (await fetchAllRows('game_register', orderBy: 'year_start')).map(GameCount.fromJson).toList();

  Future<void> save(GameCount c) => c.id == null
      ? sb.from('game_register').upsert(c.toRow(), onConflict: 'year_start,farm,species')
      : sb.from('game_register').update(c.toRow()).eq('id', c.id!);

  Future<void> saveAll(List<GameCount> rows) => sb.from('game_register').upsert([for (final r in rows) r.toRow()], onConflict: 'year_start,farm,species');

  Future<void> delete(String id) => sb.from('game_register').delete().eq('id', id);

  /// The buffalo on the farms per the buffalo register (Game breeding): females and males alive and on a farm.
  Future<({int females, int males})?> buffaloOnFarm() async {
    try {
      var f = 0, m = 0;
      for (final r in await fetchAllRows('game_animals', orderBy: 'id')) {
        if ((r['species'] as String? ?? '').toLowerCase() != 'buffalo' || (r['status'] ?? 'alive') != 'alive' || r['on_farm'] == false) continue;
        final sex = (r['sex'] as String? ?? '').toLowerCase();
        if (sex.startsWith('f')) f++;
        if (sex.startsWith('m')) m++;
      }
      return (females: f, males: m);
    } catch (_) {
      return null;
    }
  }
}
