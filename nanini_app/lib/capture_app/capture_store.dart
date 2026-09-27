import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/supabase_client.dart';
import '../features/capture/capture_models.dart';
import '../features/tuckshop/tuckshop_models.dart';
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
        jsonEncode({'id': deviceId, 'name': deviceName, 'tasks': tasks, 'active': deviceActive}),
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
      await _upload();
      await _downloadRef();
      await _refreshSentStatus();
      lastSync = DateTime.now();
      await _prefs?.setString(_kLastSync, lastSync!.toIso8601String());
    } catch (e) {
      lastError = e.toString();
      debugPrint('Capture sync failed: $e');
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _registerDevice() async {
    // Insert once; after that only touch last_seen_at so a name or task list
    // changed in the hub isn't overwritten by the phone.
    await sb.from('capture_devices').upsert({'id': deviceId, 'name': deviceName}, onConflict: 'id', ignoreDuplicates: true);
    await sb.from('capture_devices').update({
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      'app_version': kCaptureAppVersion,
    }).eq('id', deviceId!);
    final row = await sb.from('capture_devices').select().eq('id', deviceId!).maybeSingle();
    if (row != null) {
      final d = CaptureDevice.fromJson(row);
      deviceName = d.name;
      tasks = d.modules;
      deviceActive = d.active;
      await _saveDevice();
    }
  }

  Future<void> _upload() async {
    if (queue.isEmpty) return;
    final batch = [...queue];
    await sb.from('capture_entries').upsert(
      [
        for (final e in batch)
          {
            'id': e.id,
            'device_id': deviceId,
            'device_name': deviceName,
            'module': e.module,
            'payload': e.payload,
            'summary': e.summary,
            'captured_at': e.capturedAt.toUtc().toIso8601String(),
          },
      ],
      onConflict: 'id',
      // Re-sending after a dropped connection must never reset an entry the
      // hub already approved or rejected.
      ignoreDuplicates: true,
    );
    final sentIds = batch.map((e) => e.id).toSet();
    queue.removeWhere((e) => sentIds.contains(e.id));
    sent = [...batch.reversed, ...sent];
    if (sent.length > _maxSent) sent = sent.sublist(0, _maxSent);
    await _saveQueue();
    await _saveSent();
  }

  Future<void> _downloadRef() async {
    final results = await Future.wait([
      sb.from('farms').select('id, name').order('name'),
      sb.from('employees').select('id, first_name, last_name, farm_id, current_group_id').order('first_name'),
      sb.from('employee_groups').select('id, name, farm_id').order('name'),
      sb.from('diesel_tanks').select('id, name').order('name'),
      sb.from('diesel_vehicles').select('id, name, unit').order('name'),
      sb.from('diesel_activities').select('id, name, sort_order').order('sort_order'),
      sb.from('tuckshop_items').select().eq('archived', false).order('name'),
      sb.from('tuckshop_batches').select(),
    ]);
    final batches = (results[7] as List).map((r) => TuckshopBatch.fromJson(r as Map<String, dynamic>)).toList();
    final shopItems = [
      for (final r in (results[6] as List).cast<Map<String, dynamic>>())
        () {
          final item = TuckshopItem.fromJson(r).withBatches(batches.where((b) => b.itemId == r['id']).toList());
          return {'id': item.id, 'name': item.name, 'farm_id': item.farmId, 'price': item.sellPrice, 'stock': item.totalStock};
        }(),
    ];
    ref = RefData(
      farms: [for (final r in (results[0] as List).cast<Map<String, dynamic>>()) RefItem(r['id'] as String, r['name'] as String)],
      people: [
        for (final r in (results[1] as List).cast<Map<String, dynamic>>())
          RefPerson(
            id: r['id'] as String,
            name: '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim(),
            farmId: r['farm_id'] as String?,
            groupId: r['current_group_id'] as String?,
          ),
      ],
      groups: [
        for (final r in (results[2] as List).cast<Map<String, dynamic>>()) RefItem(r['id'] as String, r['name'] as String, farmId: r['farm_id'] as String?),
      ],
      tanks: [for (final r in (results[3] as List).cast<Map<String, dynamic>>()) RefItem(r['id'] as String, r['name'] as String)],
      vehicles: [
        for (final r in (results[4] as List).cast<Map<String, dynamic>>()) RefItem(r['id'] as String, r['name'] as String, unit: r['unit'] as String?),
      ],
      activities: [for (final r in (results[5] as List).cast<Map<String, dynamic>>()) RefItem(r['id'] as String, r['name'] as String)],
      shopItems: [
        for (final r in shopItems)
          RefShopItem(
            id: r['id'] as String,
            name: r['name'] as String,
            farmId: r['farm_id'] as String?,
            price: (r['price'] as num).toDouble(),
            stock: (r['stock'] as num).toDouble(),
          ),
      ],
    );
    await _prefs?.setString(_kRef, jsonEncode(ref.toJson()));
  }

  Future<void> _refreshSentStatus() async {
    if (sent.isEmpty) return;
    final rows = await sb.from('capture_entries').select('id, status, reject_reason').inFilter('id', sent.map((e) => e.id).toList());
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
