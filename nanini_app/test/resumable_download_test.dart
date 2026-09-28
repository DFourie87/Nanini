import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/update/resumable_download.dart';

/// A file server that behaves like a weak farm signal: it redirects first
/// (like GitHub), then drops or stalls the first few transfers part-way.
class _FlakyServer {
  _FlakyServer(this.bytes, {this.drops = 0, this.stalls = 0});
  final Uint8List bytes;
  int drops;
  int stalls;
  final ranges = <String?>[];
  late HttpServer server;

  Uri get url => Uri.parse('http://127.0.0.1:${server.port}/latest/app.apk');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/latest/app.apk') {
        req.response.statusCode = HttpStatus.found;
        req.response.headers.set(HttpHeaders.locationHeader, '/files/app.apk');
        await req.response.close();
        return;
      }
      final range = req.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      final start = range == null ? 0 : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      final res = req.response;
      if (start >= bytes.length) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${bytes.length}');
        await res.close();
        return;
      }
      res.statusCode = range == null ? HttpStatus.ok : HttpStatus.partialContent;
      if (range != null) res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-${bytes.length - 1}/${bytes.length}');
      res.contentLength = bytes.length - start;
      final cut = start + (bytes.length - start) ~/ 3;
      if (drops > 0) {
        drops--;
        final socket = await res.detachSocket();
        socket.add(bytes.sublist(start, cut));
        await socket.flush();
        socket.destroy(); // signal lost
        return;
      }
      if (stalls > 0) {
        stalls--;
        res.add(bytes.sublist(start, cut));
        await res.flush();
        return; // never finishes: the phone must notice and ask again
      }
      res.add(bytes.sublist(start));
      await res.close();
    });
  }
}

void main() {
  final bytes = Uint8List.fromList(List.generate(300000, (i) => i % 251));
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dl'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('dropped connections resume where they stopped, not from 0', () async {
    final s = _FlakyServer(bytes, drops: 2);
    await s.start();
    final dest = File('${dir.path}/app.apk.part');
    final retries = <int>[];
    await downloadResumable(url: s.url, dest: dest, onRetry: (a, _) => retries.add(a), backoff: (_) => Duration.zero);
    expect(dest.readAsBytesSync(), bytes);
    expect(retries, [1, 2]);
    expect(s.ranges.first, isNull); // first try: the whole file
    expect(s.ranges.skip(1).every((r) => r != null && r != 'bytes=0-'), isTrue); // then only the rest
    await s.server.close(force: true);
  });

  test('a stalled transfer is noticed and continued', () async {
    final s = _FlakyServer(bytes, stalls: 1);
    await s.start();
    final dest = File('${dir.path}/app.apk.part');
    await downloadResumable(url: s.url, dest: dest, stallTimeout: const Duration(milliseconds: 500), backoff: (_) => Duration.zero);
    expect(dest.readAsBytesSync(), bytes);
    expect(s.ranges.length, 2);
    expect(s.ranges.last, startsWith('bytes='));
    await s.server.close(force: true);
  });

  test('a partial file from before is continued; a complete one is kept', () async {
    final s = _FlakyServer(bytes);
    await s.start();
    final dest = File('${dir.path}/app.apk.part')..writeAsBytesSync(bytes.sublist(0, 1000));
    await downloadResumable(url: s.url, dest: dest, backoff: (_) => Duration.zero);
    expect(dest.readAsBytesSync(), bytes);
    expect(s.ranges.single, 'bytes=1000-');
    // Already complete: nothing more to fetch.
    await downloadResumable(url: s.url, dest: dest, backoff: (_) => Duration.zero);
    expect(dest.readAsBytesSync(), bytes);
    await s.server.close(force: true);
  });

  test('gives up after the last attempt', () async {
    final s = _FlakyServer(bytes, drops: 99);
    await s.start();
    final dest = File('${dir.path}/app.apk.part');
    await expectLater(
      downloadResumable(url: s.url, dest: dest, maxAttempts: 3, backoff: (_) => Duration.zero),
      throwsA(anything),
    );
    await s.server.close(force: true);
  });
}
