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
      tuckshopRepo.watchPurchases().listen((v) => _set(() => purchases = v), onError: _error),
      tuckshopRepo.watchItems().listen((v) => _set(() => items = v), onError: _error),
      // Extra pay needs docs/sql/pay_extras.sql; until then it's just empty.
      repo.watchExtras().listen((v) => _set(() => extras = v), onError: (Object e) => debugPrint('pay_extras: $e')),
    ];
    _watchEmployees();
    employeesRepo.fetchFarms().then((f) => _set(() => farms = f), onError: _error);
  }

  StreamSubscription<List<Employee>>? _employeesSub;

  void _watchEmployees() {
    _employeesSub?.cancel();
    _employeesSub = employeesRepo.watchEmployees().listen((v) => _set(() => employees = v), onError: _error);
  }

  /// Tariff, rent, loan or UIF changed in Summary: saved, shown at once, and
  /// the employee list fetched afresh -- the live feed can miss a change
  /// (the hub left open, its connection dropped), and then went on showing
  /// the old amount as if it wasn't saved. Fails when the database changed
  /// nothing.
  Future<void> savePay(String id, {double? ratePerHour, double? rentDeduction, double? loanDeduction, bool? uifDeduct}) async {
    final saved = await employeesRepo.updatePay(id, ratePerHour: ratePerHour, rentDeduction: rentDeduction, loanDeduction: loanDeduction, uifDeduct: uifDeduct);
    if (saved == null) throw StateError('Not saved: the database changed nothing for this worker. Close Employees, open it again and try once more.');
    _set(() => employees = [for (final e in employees ?? const <Employee>[]) e.id == id ? saved : e]);
    if (_live) _watchEmployees();
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
    this.extras = const [],
  }) : _subs = const [],
        _live = false;

  final HoursRepository repo;
  final employeesRepo = EmployeesRepository();
  final tuckshopRepo = TuckshopRepository();
  late final List<StreamSubscription<Object?>> _subs;
  bool _live = true;
  bool _disposed = false;

  List<HoursEntry>? entries;
  List<KgEntry>? kgEntries;
  List<Payslip>? payslips;
  List<Employee>? employees;
  List<TuckshopPurchase>? purchases;
  List<TuckshopItem> items = [];
  List<PayExtra> extras = [];
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
    _employeesSub?.cancel();
    super.dispose();
  }
}
