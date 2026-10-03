import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// Every row of [table], kept live -- like `.stream()`, but paged, so a
/// table past the server's 1000-row page still comes through in full
/// (`.stream()` only ever gets the first 1000). Any change to the table
/// reloads it (a burst of changes, e.g. an approval adding many rows, is
/// reloaded once).
/// Every row of [table] once (paged past the server's 1000-row limit).
Future<List<Map<String, dynamic>>> fetchAllRows(String table, {required String orderBy, String key = 'id'}) async {
  final rows = <Map<String, dynamic>>[];
  for (var from = 0;; from += 1000) {
    var q = sb.from(table).select().order(orderBy);
    if (key != orderBy) q = q.order(key);
    final page = await q.range(from, from + 999);
    rows.addAll((page as List).cast<Map<String, dynamic>>());
    if (page.length < 1000) return rows;
  }
}

/// [key]: the table's unique column, for a stable order across pages ("id";
/// the chart of accounts has none -- its key is "code").
Stream<List<Map<String, dynamic>>> watchAllRows(String table, {required String orderBy, String key = 'id'}) {
  late StreamController<List<Map<String, dynamic>>> out;
  RealtimeChannel? channel;
  Timer? debounce;
  var loading = false;
  var again = false;

  Future<void> load() async {
    if (loading) {
      again = true;
      return;
    }
    loading = true;
    try {
      do {
        again = false;
        final rows = <Map<String, dynamic>>[];
        for (var from = 0;; from += 1000) {
          var q = sb.from(table).select().order(orderBy);
          if (key != orderBy) q = q.order(key);
          final page = await q.range(from, from + 999);
          rows.addAll((page as List).cast<Map<String, dynamic>>());
          if (page.length < 1000) break;
        }
        if (!out.isClosed) out.add(rows);
      } while (again);
    } catch (e, st) {
      if (!out.isClosed) out.addError(e, st);
    } finally {
      loading = false;
    }
  }

  out = StreamController<List<Map<String, dynamic>>>(
    onListen: () {
      channel = sb
          .channel('all-rows-$table-${DateTime.now().microsecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            callback: (_) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 600), load);
            },
          )
          .subscribe();
      load();
    },
    onCancel: () async {
      debounce?.cancel();
      final c = channel;
      if (c != null) await sb.removeChannel(c);
      await out.close();
    },
  );
  return out.stream;
}
