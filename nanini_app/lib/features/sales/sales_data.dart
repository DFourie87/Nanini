import 'dart:math';
import 'package:flutter/foundation.dart';
import '../delivery/delivery_models.dart';
import '../delivery/delivery_repository.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

/// Everything the Sales app shows, loaded once when it opens (and again on
/// refresh) and kept while moving between its tabs. New market reports only
/// arrive once a day, so nothing is listened to live -- that kept reloading
/// the screens every few seconds.
class SalesData extends ChangeNotifier {
  SalesData(this.repo, {DeliveryRepository? delivery}) : deliveryRepo = delivery ?? DeliveryRepository() {
    refresh();
  }

  final SalesRepository repo;
  final DeliveryRepository deliveryRepo;

  List<SalesReport>? reports;
  List<DeliveryNote>? notes;
  DateTime? loadedAt;
  bool loading = false;
  Object? error;

  /// Line items by report id, fetched as they're needed.
  final _items = <String, List<SalesLineItem>>{};
  final _fetching = <String>{};
  final _failed = <String>{};
  bool _disposed = false;

  Future<void> refresh() async {
    loading = true;
    error = null;
    _notify();
    try {
      final r = await repo.fetchReports();
      final n = await deliveryRepo.fetchNotes();
      reports = r;
      notes = n;
      _items.clear();
      _failed.clear();
      loadedAt = DateTime.now();
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      _notify();
    }
  }

  /// The line items of these reports, or null while some are still being
  /// fetched (which starts here).
  List<SalesLineItem>? itemsFor(List<String> reportIds) {
    final missing = reportIds.where((id) => !_items.containsKey(id)).toList();
    if (missing.isEmpty) return [for (final id in reportIds) ..._items[id]!];
    final toFetch = missing.where((id) => !_fetching.contains(id) && !_failed.contains(id)).toList();
    if (toFetch.isNotEmpty) _fetch(toFetch);
    return missing.every(_failed.contains) ? [for (final id in reportIds) ...?_items[id]] : null;
  }

  Future<void> _fetch(List<String> ids) async {
    _fetching.addAll(ids);
    try {
      for (var i = 0; i < ids.length; i += 100) {
        final chunk = ids.sublist(i, min(i + 100, ids.length));
        final rows = await repo.fetchLineItemsForReports(chunk);
        for (final id in chunk) {
          _items[id] = [];
        }
        for (final li in rows) {
          (_items[li.reportId ?? ''] ??= []).add(li);
        }
      }
    } catch (e) {
      // Not retried by itself (that would loop); the refresh button does.
      _failed.addAll(ids.where((id) => !_items.containsKey(id)));
      error = e;
    } finally {
      _fetching.removeAll(ids);
      _notify();
    }
  }

  /// A report typed in or edited here: reload just that.
  Future<void> reloadAfterChange() => refresh();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
