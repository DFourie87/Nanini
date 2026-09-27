import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/supabase_client.dart';
import '../core/widgets/dialog_error.dart';
import '../features/capture/capture_models.dart';
import 'ref_data.dart';

const kCaptureAppVersion = 'capture-1';

/// Everything the capture app keeps on the phone -- its identity, the
/// entries waiting to be sent, what was already sent (with the hub's
/// approve/reject answer), and the lists it picks from (people, tanks,
/// vehicles...). All of it survives the app being closed, so capturing
/// works with no signal at all; [sync] runs whenever the phone is on Wi-Fi.
class CaptureStore extends ChangeNotifier {
  static const _kDevice = 'capture.device';
  static const _kQueue = 'capture.queue';
  static const _kSent = 'capture.sent';
  static const _kRef = 'capture.ref';
  static const _kLastSync = 'capture.lastSync';
  static const _kTruckDraft = 'capture.truckDraft';
  static const _maxSent = 80;

  SharedPreferences? _prefs;
  bool loaded = false;

  CaptureStore();

  /// For widget tests: no phone storage, no network.
  @visibleForTesting
  CaptureStore.forTest(this.ref) : loaded = true;

  String? deviceId;
  String deviceName = '';
  List<String> tasks = CaptureTask.all;
  bool deviceActive = true;
  bool deviceApproved = false;

  List<CaptureEntry> queue = [];
  List<CaptureEntry> sent = [];
  RefData ref = RefData.empty();
  DateTime? lastSync;

  bool syncing = false;
  bool onWifi = false;
  String? lastError;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _timer;

  bool get isSetUp => deviceId != null;

  Future<void> load() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    final dev = _readJson(_kDevice);
    if (dev is Map) {
      deviceId = dev['id'] as String?;
      deviceName = dev['name'] as String? ?? '';
      tasks = ((dev['tasks'] as List?) ?? CaptureTask.all).cast<String>();
      deviceActive = dev['active'] as bool? ?? true;
      deviceApproved = dev['approved'] as bool? ?? false;
    }
    queue = _readEntries(_kQueue);
    sent = _readEntries(_kSent);
    final refJson = _readJson(_kRef);
    if (refJson is Map<String, dynamic>) ref = RefData.fromJson(refJson);
    final ls = prefs.getString(_kLastSync);
    lastSync = ls == null ? null : DateTime.tryParse(ls);
    loaded = true;
    notifyListeners();

    final initial = await Connectivity().checkConnectivity();
    onWifi = initial.contains(ConnectivityResult.wifi);
    _connSub = Connectivity().onConnectivityChanged.listen((r) {
      final wifi = r.contains(ConnectivityResult.wifi);
      final changed = wifi != onWifi;
      onWifi = wifi;
      notifyListeners();
      if (wifi && changed) sync();
    });
    // Keep trying while the app is open, in case Wi-Fi was up but the
    // internet behind it wasn't.
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => sync());
    sync();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Object? _readJson(String key) {
    final raw = _prefs?.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  List<CaptureEntry> _readEntries(String key) {
    final list = _readJson(key);
    if (list is! List) return [];
    final out = <CaptureEntry>[];
    for (final j in list) {
      try {
        out.add(CaptureEntry.fromJson((j as Map).cast<String, dynamic>()));
      } catch (_) {}
    }
    return out;
  }

  Future<void> _saveDevice() async => _prefs?.setString(
        _kDevice,
        jsonEncode({'id': deviceId, 'name': deviceName, 'tasks': tasks, 'active': deviceActive, 'approved': deviceApproved}),
      );
  Future<void> _saveQueue() async => _prefs?.setString(_kQueue, jsonEncode(queue.map((e) => e.toJson()).toList()));
  Future<void> _saveSent() async => _prefs?.setString(_kSent, jsonEncode(sent.map((e) => e.toJson()).toList()));

  Future<void> setUp(String name) async {
    deviceId = const Uuid().v4();
    deviceName = name.trim();
    await _saveDevice();
    notifyListeners();
    sync();
  }

  /// Saves a new entry on the phone (instantly, no signal needed) and sends
  /// it straight away if on Wi-Fi.
  Future<void> add(String module, Map<String, dynamic> payload, String summary) async {
    queue.add(CaptureEntry(
      id: const Uuid().v4(),
      module: module,
      payload: payload,
      summary: summary,
      capturedAt: DateTime.now(),
    ));
    await _saveQueue();
    notifyListeners();
    sync();
  }

  // --- Packaging truck being loaded (kept across app restarts) ---
  Map<String, dynamic>? get truckDraft {
    final j = _readJson(_kTruckDraft);
    return j is Map ? j.cast<String, dynamic>() : null;
  }

  Future<void> saveTruckDraft(Map<String, dynamic>? draft) async {
    if (draft == null) {
      await _prefs?.remove(_kTruckDraft);
    } else {
      await _prefs?.setString(_kTruckDraft, jsonEncode(draft));
    }
  }

  /// Sends waiting entries, refreshes the pick-lists and fetches the hub's
  /// answer on sent entries. Wi-Fi only (never uses mobile data).
  Future<void> sync() async {
    if (syncing || deviceId == null) return;
    final conn = await Connectivity().checkConnectivity();
    onWifi = conn.contains(ConnectivityResult.wifi);
    if (!onWifi) {
      notifyListeners();
      return;
    }
    syncing = true;
    lastError = null;
    notifyListeners();
    try {
      await _registerDevice();
      // A new phone waits for an admin to approve it in the hub; its
      // entries stay safely on the phone until then.
      if (deviceApproved && deviceActive) {
        await _upload();
        await _downloadRef();
        await _refreshSentStatus();
      }
      lastSync = DateTime.now();
      await _prefs?.setString(_kLastSync, lastSync!.toIso8601String());
    } catch (e) {
      // Kept readable: shown on the home screen so a real problem (e.g. the
      // office database refusing) isn't mistaken for a bad Wi-Fi signal.
      lastError = friendlyDbError(e);
      debugPrint('Capture sync failed: $e');
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  // Everything below goes through the capture_* database functions only
  // (docs/sql/lockdown_1_accounts.sql) -- the phone has no direct access to
  // any table. The phone's random id is its key.

  Future<void> _registerDevice() async {
    final d = await sb.rpc('capture_register', params: {
      'p_device_id': deviceId,
      'p_name': deviceName,
      'p_app_version': kCaptureAppVersion,
    }) as Map<String, dynamic>;
    deviceName = d['name'] as String? ?? deviceName;
    tasks = ((d['modules'] as List?) ?? CaptureTask.all).cast<String>();
    deviceActive = d['active'] as bool? ?? true;
    deviceApproved = d['approved'] as bool? ?? false;
    await _saveDevice();
  }

  Future<void> _upload() async {
    if (queue.isEmpty) return;
    final batch = [...queue];
    await sb.rpc('capture_submit', params: {
      'p_device_id': deviceId,
      'p_entries': [
        for (final e in batch)
          {
            'id': e.id,
            'module': e.module,
            'payload': e.payload,
            'summary': e.summary,
            'captured_at': e.capturedAt.toUtc().toIso8601String(),
          },
      ],
    });
    final sentIds = batch.map((e) => e.id).toSet();
    queue.removeWhere((e) => sentIds.contains(e.id));
    sent = [...batch.reversed, ...sent];
    if (sent.length > _maxSent) sent = sent.sublist(0, _maxSent);
    await _saveQueue();
    await _saveSent();
  }

  Future<void> _downloadRef() async {
    final json = await sb.rpc('capture_reference', params: {'p_device_id': deviceId}) as Map<String, dynamic>;
    ref = RefData.fromJson(json);
    await _prefs?.setString(_kRef, jsonEncode(ref.toJson()));
  }

  Future<void> _refreshSentStatus() async {
    if (sent.isEmpty) return;
    final rows = await sb.rpc('capture_statuses', params: {'p_device_id': deviceId, 'p_ids': sent.map((e) => e.id).toList()});
    final byId = {for (final r in (rows as List).cast<Map<String, dynamic>>()) r['id'] as String: r};
    sent = [
      for (final e in sent)
        if (byId[e.id] case final r?)
          CaptureEntry(
            id: e.id,
            module: e.module,
            payload: e.payload,
            summary: e.summary,
            capturedAt: e.capturedAt,
            status: r['status'] as String? ?? e.status,
            rejectReason: r['reject_reason'] as String?,
          )
        else
          e,
    ];
    await _saveSent();
  }
}
