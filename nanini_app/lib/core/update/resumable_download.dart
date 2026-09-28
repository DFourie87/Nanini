import 'dart:async';
import 'dart:io';
import 'dart:math';

/// Downloads [url] into [dest] over a weak signal: when the connection
/// stalls or drops, it doesn't start over -- it asks the server for just the
/// rest (an HTTP Range request) and carries on where it stopped. A partial
/// [dest] from an earlier try (even an earlier app session) is continued too.
///
/// Redirects (GitHub hands the file over from another server) are followed
/// here rather than by [HttpClient], so the Range header reaches the server
/// that actually has the file.
Future<void> downloadResumable({
  required Uri url,
  required File dest,
  void Function(int got, int total)? onProgress,
  void Function(int attempt, Object error)? onRetry,
  int maxAttempts = 40,
  Duration stallTimeout = const Duration(seconds: 30),
  Duration Function(int attempt)? backoff,
}) async {
  for (var attempt = 1;; attempt++) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      if (await _fetchRest(client, url, dest, stallTimeout, onProgress)) return;
      throw const HttpException('The download was cut off');
    } catch (e) {
      if (attempt >= maxAttempts) rethrow;
      onRetry?.call(attempt, e);
      await Future<void>.delayed((backoff ?? _backoff)(attempt));
    } finally {
      client.close(force: true);
    }
  }
}

Duration _backoff(int attempt) => Duration(seconds: min(2 * attempt, 10));

/// One try: fetches whatever [dest] is still missing. True once complete.
Future<bool> _fetchRest(HttpClient client, Uri url, File dest, Duration stall, void Function(int, int)? onProgress) async {
  var got = await dest.exists() ? await dest.length() : 0;

  HttpClientResponse? res;
  var target = url;
  for (var hop = 0; hop < 6; hop++) {
    final req = await client.getUrl(target).timeout(stall);
    req.followRedirects = false;
    if (got > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$got-');
    final r = await req.close().timeout(stall);
    if (r.isRedirect || (r.statusCode >= 300 && r.statusCode < 400)) {
      final location = r.headers.value(HttpHeaders.locationHeader);
      await r.drain<void>().catchError((_) {});
      if (location == null) throw const HttpException('Redirect without a location');
      target = target.resolve(location);
      continue;
    }
    res = r;
    break;
  }
  if (res == null) throw const HttpException('Too many redirects');

  final (int total, FileMode mode) = switch (res.statusCode) {
    // Server sent the whole file (no Range support, or nothing yet): start over.
    200 => (res.contentLength, FileMode.write),
    206 => () {
        final (start, size) = _contentRange(res!);
        if (start != got) throw const HttpException('Server resumed at the wrong place');
        return (size ?? (res.contentLength >= 0 ? got + res.contentLength : -1), FileMode.append);
      }(),
    // Asked for bytes past the end: we already have everything (or the file
    // changed -- then start again).
    416 => () {
        final (_, size) = _contentRange(res!);
        if (size != null && size == got) return (got, FileMode.append);
        dest.deleteSync();
        throw const HttpException('Partial download no longer matches');
      }(),
    _ => throw HttpException('Server said ${res.statusCode}'),
  };
  if (mode == FileMode.write) got = 0;
  if (res.statusCode == 416) {
    onProgress?.call(got, total);
    return true;
  }

  final sink = dest.openWrite(mode: mode);
  try {
    await for (final chunk in res.timeout(stall)) {
      sink.add(chunk);
      got += chunk.length;
      onProgress?.call(got, total);
    }
  } finally {
    await sink.close();
  }
  return total < 0 || got >= total;
}

/// "bytes 100-999/1000" -> (100, 1000); "bytes */1000" -> (null, 1000).
(int?, int?) _contentRange(HttpClientResponse res) {
  final m = RegExp(r'bytes\s+(?:(\d+)-\d+|\*)/(\d+|\*)').firstMatch(res.headers.value(HttpHeaders.contentRangeHeader) ?? '');
  if (m == null) return (null, null);
  return (m.group(1) == null ? null : int.parse(m.group(1)!), int.tryParse(m.group(2)!));
}
