import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:shared_preferences/shared_preferences.dart';
import 'resumable_download.dart';

/// Build number baked in by CI (`--dart-define=APP_BUILD=<run number>`, see
/// .github/workflows/build-apk.yml). 0 on local builds, which never offer
/// an update.
const kAppBuild = int.fromEnvironment('APP_BUILD');

// The public Nanini-releases repository (builds only), so this code
// repository can be private.
const _releaseBase = 'https://github.com/DFourie87/Nanini-releases/releases/latest/download';

/// The app's updater, set in main() (null in tests: no update banner).
AppUpdater? appUpdater;

/// In-app updates: every CI build publishes version.json next to the APKs;
/// when it names a newer build than this one, the app offers to download
/// its APK and hands it to Android's installer (MainActivity.kt). Signed
/// with the same key, it installs over this app and keeps its data.
///
/// The download is done by Android's DownloadManager: it carries on with the
/// app in the background or the screen off, picks up again after the signal
/// drops, and shows progress in the notifications. Where that's not
/// available, the app downloads it itself ([downloadResumable]).
class AppUpdater extends ChangeNotifier {
  AppUpdater(this.apkName, {this.currentBuild = kAppBuild, this.wifiOnly = false});

  /// The release file for this app: app-release.apk or nanini-capture.apk.
  final String apkName;

  /// This app's build (a parameter only so tests can pretend).
  final int currentBuild;

  /// Nanini Capture never uses mobile data.
  final bool wifiOnly;

  static const _channel = MethodChannel('nanini/update');
  static const _kDownload = 'update.download'; // "<build>:<download id>"

  int? latestBuild;

  /// 0..1 while downloading, null otherwise.
  double? progress;

  /// While downloading: e.g. "Weak signal -- carries on by itself".
  String? note;
  String? error;

  /// Downloaded and waiting to be installed.
  String? readyPath;

  DateTime? _checkedAt;
  Timer? _poll;
  bool _ticking = false;
  bool _launched = false;

  bool get available => currentBuild > 0 && (latestBuild ?? 0) > currentBuild;
  bool get downloading => progress != null;

  /// Looks for a newer build; at most every 30 minutes unless [force].
  Future<void> check({bool force = false}) async {
    if (currentBuild == 0 || !Platform.isAndroid) return;
    final last = _checkedAt;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 30)) return;
    _checkedAt = DateTime.now();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final res = await (await client.getUrl(Uri.parse('$_releaseBase/version.json'))).close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return;
      }
      final j = jsonDecode(await res.transform(utf8.decoder).join());
      final b = j is Map ? j['build'] : null;
      final n = b is num ? b.toInt() : int.tryParse('$b');
      if (n != null && n != latestBuild) {
        latestBuild = n;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    } finally {
      client.close();
    }
  }

  /// Back in the app (or just opened): picks up a download that was running,
  /// and offers to install one that finished while away.
  Future<void> resume() async {
    if (currentBuild == 0 || !Platform.isAndroid) return;
    final path = readyPath;
    if (path != null) {
      if (!_launched) await _launch(path);
      return;
    }
    if (_poll != null) return;
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_kDownload)?.split(':');
      if (saved == null || saved.length != 2) return;
      final build = int.tryParse(saved[0]) ?? 0;
      final id = int.parse(saved[1]);
      if (build <= currentBuild) {
        await _forget(id); // that one is already installed
        return;
      }
      progress ??= 0;
      notifyListeners();
      _watch(id);
    } catch (e) {
      debugPrint('Update resume: $e');
    }
  }

  /// UPDATE / INSTALL: downloads the new APK (or installs the one already
  /// downloaded) and opens Android's "Install / Update" screen.
  Future<void> install() async {
    final path = readyPath;
    if (path != null) return _launch(path);
    if (downloading) return;
    error = null;
    note = null;
    progress = 0;
    notifyListeners();
    int id;
    try {
      id = await _startOrReuse();
    } catch (e) {
      debugPrint('DownloadManager unavailable, downloading in the app: $e');
      return _downloadInApp();
    }
    _watch(id);
  }

  Future<int> _startOrReuse() async {
    final prefs = await SharedPreferences.getInstance();
    final build = latestBuild ?? 0;
    final saved = prefs.getString(_kDownload)?.split(':');
    if (saved != null && saved.length == 2) {
      final id = int.parse(saved[1]);
      if (saved[0] == '$build') {
        final s = await _status(id);
        if (s['status'] != 'failed' && s['status'] != 'missing') return id; // still going
      }
      await _channel.invokeMethod<void>('cancelDownload', {'id': id});
    }
    final id = await _channel.invokeMethod<int>('download', {'url': '$_releaseBase/$apkName', 'fileName': apkName, 'wifiOnly': wifiOnly});
    await prefs.setString(_kDownload, '$build:$id');
    return id!;
  }

  Future<Map<String, Object?>> _status(int id) async =>
      ((await _channel.invokeMethod<Map<Object?, Object?>>('downloadStatus', {'id': id})) ?? const {}).cast<String, Object?>();

  void _watch(int id) {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _tick(id));
    _tick(id);
  }

  Future<void> _tick(int id) async {
    if (_ticking) return;
    _ticking = true;
    try {
      final s = await _status(id);
      final got = (s['got'] as num?)?.toDouble() ?? 0;
      final total = (s['total'] as num?)?.toDouble() ?? 0;
      if (total > 0) progress = (got / total).clamp(0, 1);
      switch (s['status']) {
        case 'pending':
          note = wifiOnly ? 'Waiting for Wi-Fi…' : 'Starting…';
        case 'running':
          note = null;
        case 'paused':
          note = wifiOnly ? 'Waiting for Wi-Fi -- carries on by itself' : 'Weak signal -- carries on by itself';
        case 'done':
          _stop();
          await _forget(null);
          readyPath = s['path'] as String?;
          progress = null;
          note = null;
          final path = readyPath;
          // Only open the installer with the app in front; otherwise when
          // it's opened again (see resume).
          if (path != null && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) await _launch(path);
        default: // failed / missing
          _stop();
          await _forget(null);
          progress = null;
          note = null;
          error = 'The download did not finish. Tap UPDATE to try again.';
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Update status: $e');
    } finally {
      _ticking = false;
    }
  }

  void _stop() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _forget(int? cancelId) async {
    if (cancelId != null) await _channel.invokeMethod<void>('cancelDownload', {'id': cancelId}).catchError((_) {});
    await (await SharedPreferences.getInstance()).remove(_kDownload);
  }

  Future<void> _launch(String path) async {
    _launched = true;
    try {
      final r = await _channel.invokeMethod<String>('install', {'path': path});
      error = r == 'permission' ? 'Allow this app to install updates (switch it on), then come back and tap INSTALL.' : null;
    } catch (e) {
      error = 'Could not open the installer. Tap INSTALL to try again.';
      debugPrint('Update install: $e');
    }
    notifyListeners();
  }

  /// Fallback where Android's DownloadManager isn't available: the app
  /// downloads it itself, resuming after drops (only while it's open).
  Future<void> _downloadInApp() async {
    try {
      final dir = await _channel.invokeMethod<String>('updatesDir');
      final build = latestBuild ?? 0;
      // Kept per build, so a half-done download is continued next time but
      // never mixed with a newer build's file.
      final part = File('$dir/$apkName.$build.part');
      for (final old in Directory(dir!).listSync().whereType<File>()) {
        if (old.path.endsWith('.part') && old.path != part.path) old.deleteSync();
      }
      await downloadResumable(
        url: Uri.parse('$_releaseBase/$apkName'),
        dest: part,
        onProgress: (got, total) {
          if (total <= 0) return;
          final p = got / total;
          if (p - (progress ?? 0) >= 0.01 || p >= 1 || note != null) {
            progress = p;
            note = null;
            notifyListeners();
          }
        },
        onRetry: (attempt, e) {
          debugPrint('Update download, try $attempt: $e');
          note = 'Weak signal -- still trying (keep the app open)';
          notifyListeners();
        },
      );
      readyPath = part.renameSync('$dir/$apkName').path;
      progress = null;
      note = null;
      await _launch(readyPath!);
    } catch (e) {
      error = 'Could not download the update. Check the internet and tap UPDATE again -- it carries on where it stopped.';
      debugPrint('Update failed: $e');
    } finally {
      progress = null;
      note = null;
      notifyListeners();
    }
  }
}
