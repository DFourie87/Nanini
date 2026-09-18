import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_user.dart';
import 'auth_repository.dart';

/// Who is using the app right now. Persists *who's logged in* across app
/// restarts (so people don't have to log in every time they open the app),
/// but never persists the PIN — that's kept in memory only for the current
/// run, and re-confirmed (once per run) the first time an admin action is
/// attempted. See docs/sql/app_users_auth.sql for why: every admin
/// RPC call re-verifies the PIN server-side, so the client needs it on hand.
class Session extends ChangeNotifier {
  static const _prefsKey = 'nanini_session_user';

  final _repo = AuthRepository();

  AppUser? currentUser;
  String? _pin;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get isLoggedIn => currentUser != null;
  bool get isAdmin => currentUser?.isAdmin ?? false;

  /// The current admin's PIN, if confirmed this run — for admin RPC calls.
  String? get adminPin => isAdmin ? _pin : null;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        currentUser = AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        currentUser = null;
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<bool> login(String username, String pin) async {
    final user = await _repo.login(username, pin);
    if (user == null) return false;
    currentUser = user;
    _pin = pin; // kept in memory only
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(user.toJson()));
    notifyListeners();
    return true;
  }

  /// Re-confirms the current admin's PIN (e.g. after a restart wiped the
  /// in-memory copy) and caches it for the rest of this run.
  Future<bool> confirmAdminPin(String pin) async {
    if (currentUser == null) return false;
    final user = await _repo.login(currentUser!.username, pin);
    if (user == null || !user.isAdmin) return false;
    _pin = pin;
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    currentUser = null;
    _pin = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }
}
