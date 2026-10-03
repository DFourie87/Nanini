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
      // The purchases report's tables: before their SQL is run, just empty.
      repo.watchGlAccounts().listen((v) => _set(() => glAccounts = v), onError: (_) => _set(() => purchasesMissing = true)),
      repo.watchDocLines().listen((v) => _set(() => docLines = v), onError: (_) => _set(() => purchasesMissing = true)),
      repo.watchGlRules().listen((v) => _set(() => glRules = v), onError: (_) => _set(() => purchasesMissing = true)),
    ];
    _loadBankDate();
  }

  /// For widget tests: fixed lists, no database.
  @visibleForTesting
  SuppliersData.forTest(this.repo,
      {required List<Supplier> this.suppliers,
      List<SupplierDoc> this.docs = const [],
      List<SupplierPayment> this.payments = const [],
      this.glAccounts = const [],
      this.docLines = const [],
      this.glRules = const [],
      this.bankDate})
      : _subs = const [];

  final SuppliersRepository repo;
  late final List<StreamSubscription<Object?>> _subs;
  bool _disposed = false;

  List<Supplier>? suppliers;

  /// The last day the bank statements imported cover: what's due is as at it.
  String? bankDate;
  List<SupplierDoc>? docs;
  List<SupplierPayment>? payments;
  List<GlAccount> glAccounts = const [];
  List<DocLine> docLines = const [];
  List<GlRule> glRules = const [];

  /// docs/sql/suppliers_purchases.sql not run yet.
  bool purchasesMissing = false;
  Object? error;

  bool get loaded => suppliers != null && docs != null && payments != null;

  List<SupplierAccount> get accounts => [for (final s in suppliers ?? const <Supplier>[]) SupplierAccount(s, docs ?? const [], payments ?? const [])];

  String accountLabel(String? code) {
    if (code == null) return 'Unallocated';
    final a = glAccounts.where((g) => g.code == code).firstOrNull;
    return a == null ? code : a.label;
  }

  void _set(VoidCallback f) {
    if (_disposed) return;
    f();
    notifyListeners();
  }

  void _error(Object e) => _set(() => error = e);

  Future<void> _loadBankDate() async {
    final d = await repo.fetchBankDate();
    _set(() => bankDate = d);
  }

  /// Reads suppliers, documents and payments again after a change made here,
  /// so it shows at once (the live updates may not reach every table).
  /// Not in tests (no database).
  Future<void> reload() async {
    if (_subs.isEmpty) return;
    _loadBankDate();
    try {
      final s = await repo.fetchSuppliers();
      final d = await repo.fetchDocs();
      final p = await repo.fetchPayments();
      _set(() {
        suppliers = s;
        docs = d;
        payments = p;
      });
    } catch (_) {
      // The live updates still come in.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
