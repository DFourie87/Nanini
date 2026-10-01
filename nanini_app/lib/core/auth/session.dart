import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import '../supabase_client.dart';
import 'app_user.dart';
import 'auth_repository.dart';

/// Who is using the app right now. The login itself is a Supabase Auth
/// session (kept and refreshed by the Supabase client, so people stay logged
/// in across restarts); the user's profile (name, role, apps) is cached here
/// so the hub opens straight away, even with no signal.
class Session extends ChangeNotifier {
  static const _prefsKey = 'nanini_session_user';
  static const _mustChangePinKey = 'nanini_must_change_pin';

  final _repo = AuthRepository();
  StreamSubscription? _authSub;

  AppUser? currentUser;
  bool _loaded = false;

  /// Set when someone logged in with a PIN shorter than 6 digits: they must
  /// choose a new one before using the app.
  bool mustChangePin = false;

  bool get isLoaded => _loaded;
  bool get isLoggedIn => currentUser != null;
  bool get isAdmin => currentUser?.isAdmin ?? false;
  bool hasModule(String key) => currentUser?.hasModule(key) ?? false;
  bool can(String right) => currentUser?.can(right) ?? false;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    // No Supabase login (e.g. first run after the lockdown update): the old
    // saved user alone no longer gets any data, so ask to log in again.
    if (raw != null && sb.auth.currentSession != null) {
      try {
        currentUser = AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        mustChangePin = prefs.getBool(_mustChangePinKey) ?? false;
      } catch (_) {
        currentUser = null;
      }
    }
    _authSub = sb.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedOut && currentUser != null) _clear();
      },
      // Token refresh failing while offline is normal -- it retries.
      onError: (Object e) => debugPrint('Auth state error: $e'),
    );
    _loaded = true;
    notifyListeners();
    if (currentUser != null) _refreshProfile();
  }

  /// Picks up role/app changes made by an admin; logs out a switched-off
  /// user. Silent when offline.
  Future<void> _refreshProfile() async {
    try {
      final me = await _repo.fetchMe();
      if (me == null) {
        await logout();
        return;
      }
      currentUser = me;
      await _save(me);
      notifyListeners();
    } catch (e) {
      debugPrint('Profile refresh skipped: $e');
    }
  }

  Future<bool> login(String username, String pin) async {
    final user = await _repo.login(username, pin);
    if (user == null) return false;
    currentUser = user;
    mustChangePin = !isValidPin(pin);
    await _save(user);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mustChangePinKey, mustChangePin);
    notifyListeners();
    return true;
  }

  Future<void> pinChanged() async {
    mustChangePin = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_mustChangePinKey);
    notifyListeners();
  }

  Future<void> _save(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(user.toJson()));
  }

  Future<void> _clear() async {
    currentUser = null;
    mustChangePin = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await prefs.remove(_mustChangePinKey);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _repo.signOut();
    } catch (e) {
      debugPrint('Sign out: $e');
    }
    await _clear();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
