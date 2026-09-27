import 'dart:async';
import 'package:flutter/foundation.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import '../tuckshop/tuckshop_models.dart';
import '../tuckshop/tuckshop_repository.dart';
import 'hours_models.dart';
import 'hours_repository.dart';

/// Everything the Work and Summary tabs work from, kept live. Subscribed
/// once for the Hours app (not per rebuild), so switching steps and tabs
/// doesn't reload anything.
class HoursData extends ChangeNotifier {
  HoursData(this.repo) {
    _subs = [
      repo.watchEntries().listen((v) => _set(() => entries = v), onError: _error),
      repo.watchKgEntries().listen((v) => _set(() => kgEntries = v), onError: _error),
      repo.watchPayslips().listen((v) => _set(() => payslips = v), onError: _error),
      employeesRepo.watchEmployees().listen((v) => _set(() => employees = v), onError: _error),
      tuckshopRepo.watchPurchases().listen((v) => _set(() => purchases = v), onError: _error),
      tuckshopRepo.watchItems().listen((v) => _set(() => items = v), onError: _error),
    ];
    employeesRepo.fetchFarms().then((f) => _set(() => farms = f), onError: _error);
  }

  /// For widget tests: fixed lists, no database.
  @visibleForTesting
  HoursData.forTest(
    this.repo, {
    required List<Employee> this.employees,
    required List<HoursEntry> this.entries,
    List<KgEntry> this.kgEntries = const [],
    List<TuckshopPurchase> this.purchases = const [],
    List<Payslip> this.payslips = const [],
    this.farms = const [],
  }) : _subs = const [];

  final HoursRepository repo;
  final employeesRepo = EmployeesRepository();
  final tuckshopRepo = TuckshopRepository();
  late final List<StreamSubscription<Object?>> _subs;
  bool _disposed = false;

  List<HoursEntry>? entries;
  List<KgEntry>? kgEntries;
  List<Payslip>? payslips;
  List<Employee>? employees;
  List<TuckshopPurchase>? purchases;
  List<TuckshopItem> items = [];
  List<Farm> farms = [];
  Object? error;

  bool get loaded => entries != null && kgEntries != null && payslips != null && employees != null && purchases != null;

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
