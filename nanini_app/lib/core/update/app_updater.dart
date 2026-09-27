import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Build number baked in by CI (`--dart-define=APP_BUILD=<run number>`, see
/// .github/workflows/build-apk.yml). 0 on local builds, which never offer
/// an update.
const kAppBuild = int.fromEnvironment('APP_BUILD');

const _releaseBase = 'https://github.com/DFourie87/Nanini/releases/latest/download';

/// The app's updater, set in main() (null in tests: no update banner).
AppUpdater? appUpdater;

/// In-app updates: every CI build publishes version.json next to the APKs;
/// when it names a newer build than this one, the app offers to download
/// its APK and hands it to Android's installer (MainActivity.kt). Signed
/// with the same key, it installs over this app and keeps its data.
class AppUpdater extends ChangeNotifier {
  AppUpdater(this.apkName, {this.currentBuild = kAppBuild});

  /// The release file for this app: app-release.apk or nanini-capture.apk.
  final String apkName;

  /// This app's build (a parameter only so tests can pretend).
  final int currentBuild;

  static const _channel = MethodChannel('nanini/update');

  int? latestBuild;

  /// 0..1 while downloading, null otherwise.
  double? progress;
  String? error;
  DateTime? _checkedAt;

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

  /// Downloads the new APK and opens Android's "Install / Update" screen.
  Future<void> install() async {
    if (downloading) return;
    error = null;
    progress = 0;
    notifyListeners();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final dir = await _channel.invokeMethod<String>('updatesDir');
      final file = File('$dir/$apkName');
      final res = await (await client.getUrl(Uri.parse('$_releaseBase/$apkName'))).close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw 'The update is not on the server right now (${res.statusCode}). Try again in a few minutes.';
      final total = res.contentLength;
      var got = 0;
      final sink = file.openWrite();
      try {
        // Gives up if the download stalls for half a minute.
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) {
            final p = got / total;
            if (p - (progress ?? 0) >= 0.01) {
              progress = p;
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got != total) throw 'The download was cut off. Try again.';
      final r = await _channel.invokeMethod<String>('install', {'path': file.path});
      if (r == 'permission') error = 'Allow this app to install updates (switch it on), then come back and tap UPDATE again.';
    } catch (e) {
      error = e is String ? e : 'Could not download the update. Check the internet and try again.';
      debugPrint('Update failed: $e');
    } finally {
      client.close();
      progress = null;
      notifyListeners();
    }
  }
}
