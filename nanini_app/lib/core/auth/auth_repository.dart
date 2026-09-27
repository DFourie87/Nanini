import 'package:supabase_flutter/supabase_flutter.dart';
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

/// Minimum PIN length -- Supabase Auth won't accept a shorter password.
const kMinPinLength = 6;

/// A PIN is digits only and at least [kMinPinLength] long.
bool isValidPin(String pin) => RegExp('^[0-9]{$kMinPinLength,}\$').hasMatch(pin);

/// The login email behind a username (never shown; see
/// docs/sql/lockdown_1_accounts.sql `app_user_email`).
String authEmailFor(String username) => '${username.trim().toLowerCase()}@users.nanini.app';

/// Username + PIN sign in to a real Supabase Auth account, so the database
/// itself knows who is asking (every table requires a logged-in, active
/// Nanini user -- see docs/sql/lockdown_2_policies.sql). Admin actions are
/// checked server-side against the logged-in user's role.
class AuthRepository {
  static bool _wrongPin(AuthApiException e) =>
      e.code == 'invalid_credentials' || e.message.toLowerCase().contains('invalid login credentials');

  /// Null when the username/PIN is wrong.
  Future<AppUser?> login(String username, String pin) async {
    try {
      await sb.auth.signInWithPassword(email: authEmailFor(username), password: pin);
    } on AuthApiException catch (e) {
      if (e.code == 'user_banned') throw const AuthException('This login has been switched off. Ask an admin.');
      if (_wrongPin(e)) return null;
      rethrow;
    }
    final me = await fetchMe();
    if (me == null) await sb.auth.signOut();
    return me;
  }

  /// The logged-in user's profile, or null if they're no longer an active user.
  Future<AppUser?> fetchMe() async {
    final rows = await sb.rpc('my_app_user') as List;
    if (rows.isEmpty) return null;
    return AppUser.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<void> signOut() => sb.auth.signOut();

  Future<String> createUser({
    required String newUsername,
    required String displayName,
    required String newPin,
    required String role,
    List<String> modules = const [],
  }) async {
    final id = await sb.rpc('admin_create_user', params: {
      'p_username': newUsername,
      'p_display_name': displayName,
      'p_pin': newPin,
      'p_role': role,
      'p_modules': modules,
    });
    return id as String;
  }

  /// Admin-only: change an existing user's role and/or which hub tiles a
  /// staff account can see.
  Future<void> updateAccess({required String targetId, required String role, required List<String> modules}) =>
      sb.rpc('admin_update_user_access', params: {'p_target_id': targetId, 'p_role': role, 'p_modules': modules});

  Future<List<ManagedUser>> listUsers() async {
    final rows = await sb.rpc('admin_list_users');
    return (rows as List).map((r) => ManagedUser.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> setActive({required String targetId, required bool active}) =>
      sb.rpc('admin_set_user_active', params: {'p_target_id': targetId, 'p_active': active});

  /// Admin-only: give a user a new PIN (e.g. they forgot theirs).
  Future<void> resetPin({required String targetId, required String pin}) =>
      sb.rpc('admin_reset_pin', params: {'p_target_id': targetId, 'p_pin': pin});

  /// Checks [oldPin] by signing in with it again, then sets [newPin].
  /// False if the old PIN was wrong.
  Future<bool> changeOwnPin({required String username, required String oldPin, required String newPin}) async {
    try {
      await sb.auth.signInWithPassword(email: authEmailFor(username), password: oldPin);
    } on AuthApiException catch (e) {
      if (_wrongPin(e)) return false;
      rethrow;
    }
    await setOwnPin(newPin);
    return true;
  }

  /// Sets the logged-in user's PIN (no old PIN check -- used right after
  /// logging in with a short PIN).
  Future<void> setOwnPin(String newPin) => sb.auth.updateUser(UserAttributes(password: newPin));
}
