import '../supabase_client.dart';
import 'app_user.dart';

class ManagedUser extends AppUser {
  ManagedUser({
    required super.id,
    required super.username,
    required super.displayName,
    required super.role,
    super.modules,
    required this.active,
    required this.createdAt,
  });

  final bool active;
  final DateTime createdAt;

  factory ManagedUser.fromJson(Map<String, dynamic> j) => ManagedUser(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['display_name'] as String,
        role: j['role'] as String,
        modules: ((j['modules'] as List?) ?? const []).map((e) => e as String).toList(),
        active: j['active'] as bool,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// All PIN verification happens server-side in Postgres (SECURITY DEFINER
/// functions) — see docs/sql/app_users_auth.sql. The client never sees a
/// pin_hash, only the RPC results.
class AuthRepository {
  Future<AppUser?> login(String username, String pin) async {
    final rows = await sb.rpc('login', params: {'p_username': username, 'p_pin': pin});
    final list = rows as List;
    if (list.isEmpty) return null;
    return AppUser.fromJson(list.first as Map<String, dynamic>);
  }

  Future<String> createUser({
    required String adminUsername,
    required String adminPin,
    required String newUsername,
    required String displayName,
    required String newPin,
    required String role,
    List<String> modules = const [],
  }) async {
    final id = await sb.rpc('create_app_user', params: {
      'p_admin_username': adminUsername,
      'p_admin_pin': adminPin,
      'p_new_username': newUsername,
      'p_display_name': displayName,
      'p_new_pin': newPin,
      'p_role': role,
      'p_modules': modules,
    });
    return id as String;
  }

  /// Admin-only: change an existing user's role and/or which hub tiles a
  /// staff account can see.
  Future<void> updateAccess({
    required String adminUsername,
    required String adminPin,
    required String targetId,
    required String role,
    required List<String> modules,
  }) {
    return sb.rpc('update_app_user_access', params: {
      'p_admin_username': adminUsername,
      'p_admin_pin': adminPin,
      'p_target_id': targetId,
      'p_role': role,
      'p_modules': modules,
    });
  }

  Future<List<ManagedUser>> listUsers({required String adminUsername, required String adminPin}) async {
    final rows = await sb.rpc('list_app_users', params: {'p_admin_username': adminUsername, 'p_admin_pin': adminPin});
    return (rows as List).map((r) => ManagedUser.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> setActive({required String adminUsername, required String adminPin, required String targetId, required bool active}) {
    return sb.rpc('set_app_user_active', params: {
      'p_admin_username': adminUsername,
      'p_admin_pin': adminPin,
      'p_target_id': targetId,
      'p_active': active,
    });
  }

  Future<bool> changeOwnPin({required String username, required String oldPin, required String newPin}) async {
    final result = await sb.rpc('change_own_pin', params: {'p_username': username, 'p_old_pin': oldPin, 'p_new_pin': newPin});
    return result as bool;
  }
}
