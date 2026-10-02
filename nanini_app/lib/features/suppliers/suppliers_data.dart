import 'dart:async';

import 'package:flutter/foundation.dart';

import 'suppliers_models.dart';
import 'suppliers_repository.dart';

/// Suppliers, documents and payments, kept live for both tabs.
class SuppliersData extends ChangeNotifier {
  SuppliersData(this.repo) {
    _subs = [
      repo.watchSuppliers().listen((v) => _set(() => suppliers = v), onError: _error),
      repo.watchDocs().listen((v) => _set(() => docs = v), onError: _error),
      repo.watchPayments().listen((v) => _set(() => payments = v), onError: _error),
    ];
  }

  /// For widget tests: fixed lists, no database.
  @visibleForTesting
  SuppliersData.forTest(this.repo, {required List<Supplier> this.suppliers, List<SupplierDoc> this.docs = const [], List<SupplierPayment> this.payments = const []})
      : _subs = const [];

  final SuppliersRepository repo;
  late final List<StreamSubscription<Object?>> _subs;
  bool _disposed = false;

  List<Supplier>? suppliers;
  List<SupplierDoc>? docs;
  List<SupplierPayment>? payments;
  Object? error;

  bool get loaded => suppliers != null && docs != null && payments != null;

  List<SupplierAccount> get accounts => [for (final s in suppliers ?? const <Supplier>[]) SupplierAccount(s, docs ?? const [], payments ?? const [])];

  void _set(VoidCallback f) {
    if (_disposed) return;
    f();
    notifyListeners();
  }

  void _error(Object e) => _set(() => error = e);

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
