import '../../core/supabase_client.dart';
import '../delivery/delivery_models.dart';
import '../delivery/delivery_repository.dart';
import '../diesel/diesel_models.dart';
import '../diesel/diesel_repository.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import '../hours/hours_repository.dart';
import '../hours/hours_models.dart';
import '../tuckshop/tuckshop_repository.dart';
import 'capture_models.dart';

/// Hub side of the capture app: the "Captured -- to approve" lists and the
/// phone register. Approving an entry writes it into the real module tables
/// through each module's own repository, exactly as if it had been captured
/// in the hub.
class CaptureRepository {
  /// Filtered here rather than with a realtime `.eq('status', ...)`: a
  /// filtered stream never hears about a row that stops matching (e.g. once
  /// approved), so it would linger in the list. The newest 500 rows is far
  /// more than will ever be waiting at once.
  Stream<List<CaptureEntry>> watchPending(List<String> modules) => sb
      .from('capture_entries')
      .stream(primaryKey: ['id'])
      .order('captured_at', ascending: false)
      .limit(500)
      .map((rows) => rows
          .map(CaptureEntry.fromJson)
          .where((e) => e.status == 'pending' && modules.contains(e.module))
          .toList()
        ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt)));

  Future<List<CaptureEntry>> fetchRecentReviewed(List<String> modules, {int limit = 30}) async {
    final rows = await sb
        .from('capture_entries')
        .select()
        .inFilter('module', modules)
        .inFilter('status', ['approved', 'rejected'])
        .order('reviewed_at', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => CaptureEntry.fromJson(r as Map<String, dynamic>)).toList();
  }

  Stream<List<CaptureDevice>> watchDevices() =>
      sb.from('capture_devices').stream(primaryKey: ['id']).order('name').map((r) => r.map(CaptureDevice.fromJson).toList());

  Future<void> updateDevice(String id, {String? name, List<String>? modules, bool? active, bool? approved}) => sb.from('capture_devices').update({
        'name': ?name,
        'modules': ?modules,
        'active': ?active,
        'approved': ?approved,
      }).eq('id', id);

  /// Removing a phone also deletes its capture_entries (history and anything
  /// still waiting) -- approved entries already live in the real records.
  Future<void> deleteDevice(String id) => sb.from('capture_devices').delete().eq('id', id);

  Future<int> pendingCountForDevice(String id) async {
    final rows = await sb.from('capture_entries').select('id').eq('device_id', id).eq('status', 'pending');
    return (rows as List).length;
  }

  Future<void> reject(CaptureEntry entry, {required String reviewedBy, String? reason}) => sb.from('capture_entries').update({
        'status': 'rejected',
        'reject_reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        'reviewed_by': reviewedBy,
      }).eq('id', entry.id).eq('status', 'pending');

  /// Claims the entry (so two managers can't apply it twice), writes it into
  /// the real tables, then marks it approved. If writing fails the claim is
  /// released and the error rethrown, leaving the entry pending.
  /// [kgRatePerKg] is required for picking (kg) entries -- the rate isn't
  /// captured on the phone.
  Future<void> approve(CaptureEntry entry, {required String reviewedBy, double? kgRatePerKg}) async {
    final claimed = await sb
        .from('capture_entries')
        .update({'status': 'approving'})
        .eq('id', entry.id)
        .eq('status', 'pending')
        .select('id');
    if ((claimed as List).isEmpty) {
      throw StateError('This entry was already handled by someone else.');
    }
    try {
      await _apply(entry, kgRatePerKg: kgRatePerKg);
    } catch (_) {
      await sb.from('capture_entries').update({'status': 'pending'}).eq('id', entry.id);
      rethrow;
    }
    await sb.from('capture_entries').update({
      'status': 'approved',
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      'reviewed_by': reviewedBy,
    }).eq('id', entry.id);
  }

  Future<void> _apply(CaptureEntry entry, {double? kgRatePerKg}) async {
    final p = entry.payload;
    final note = 'Captured on ${entry.deviceName ?? 'phone'}';
    switch (entry.module) {
      case CaptureModule.dieselUsage:
        final vehicles = await DieselRepository().watchVehicles().first;
        final activities = await DieselRepository().watchActivities().first;
        final vehicle = vehicles.where((v) => v.id == p['vehicle_id']).firstOrNull;
        final activity = activities.where((a) => a.id == p['activity_id']).firstOrNull;
        await DieselRepository().logUsage(
          DieselUsage(
            id: '',
            tankId: p['tank_id'] as String,
            date: p['date'] as String,
            litres: (p['litres'] as num).toDouble(),
            equipment: vehicle?.name ?? p['vehicle_name'] as String?,
            asset: vehicle?.asset,
            hours: p['reading'] as String? ?? '',
            hourKmUnit: vehicle?.unit ?? p['unit'] as String? ?? 'hours',
            activity: activity?.name ?? p['activity_name'] as String?,
            eligible: activity?.eligible ?? false,
            notes: note,
            employeeId: p['employee_id'] as String?,
            createdAt: entry.capturedAt,
          ),
          keepCreatedAt: true,
        );
      case CaptureModule.dieselPurchase:
        await DieselRepository().logPurchase(
          DieselPurchase(
            id: '',
            tankId: p['tank_id'] as String,
            date: p['date'] as String,
            litres: (p['litres'] as num).toDouble(),
            supplier: p['supplier'] as String? ?? '',
            invoiceNote: p['delivery_note'] as String? ?? '',
            notes: note,
            createdAt: entry.capturedAt,
          ),
          keepCreatedAt: true,
        );
      case CaptureModule.hours:
        final repo = HoursRepository();
        final daySettings = await repo.fetchSettings();
        final employees = await EmployeesRepository().watchEmployees().first;
        double rateFor(String id) => employees.where((e) => e.id == id).firstOrNull?.ratePerHour ?? 0;
        final lines = (p['entries'] as List).cast<Map<String, dynamic>>();
        final date = p['date'] as String;
        // A total since the last pay isn't one day's hours: no overtime
        // split (the daily threshold covers the whole total).
        final settings = p['since_last_pay'] == true
            ? HoursSettings(
                dailyThreshold: lines.map((l) => (l['hours'] as num).toDouble()).fold<double>(daySettings.dailyThreshold, (a, b) => a > b ? a : b),
                otMultiplier: daySettings.otMultiplier,
              )
            : daySettings;
        if (p['mode'] == 'group') {
          await repo.logGroup(
            members: [
              for (final l in lines)
                (employeeId: l['employee_id'] as String, hours: (l['hours'] as num).toDouble(), rate: rateFor(l['employee_id'] as String)),
            ],
            date: date,
            settings: settings,
            groupName: p['group_name'] as String? ?? '',
            farmId: p['farm_id'] as String?,
          );
        } else {
          for (final l in lines) {
            await repo.logIndividual(
              employeeId: l['employee_id'] as String,
              date: date,
              hours: (l['hours'] as num).toDouble(),
              rate: rateFor(l['employee_id'] as String),
              settings: settings,
              farmId: p['farm_id'] as String?,
            );
          }
        }
      case CaptureModule.kg:
        if (kgRatePerKg == null || kgRatePerKg <= 0) throw ArgumentError('Enter the rate per kg.');
        final lines = (p['entries'] as List).cast<Map<String, dynamic>>();
        await HoursRepository().logKg(
          employeeKg: {for (final l in lines) l['employee_id'] as String: (l['kg'] as num).toDouble()},
          date: p['date'] as String,
          ratePerKg: kgRatePerKg,
          farmId: p['farm_id'] as String?,
        );
      case CaptureModule.tuckshop:
        final repo = TuckshopRepository();
        final employees = await EmployeesRepository().watchEmployees().first;
        final employee = employees.where((e) => e.id == p['employee_id']).firstOrNull;
        if (employee == null) throw StateError('${p['employee_name']} is no longer in the employee list.');
        final date = p['date'] as String;
        if (p['manual_total'] != null) {
          await repo.logManualPurchase(
            employee: employee,
            from: date,
            to: date,
            total: (p['manual_total'] as num).toDouble(),
            farmId: p['farm_id'] as String,
          );
        } else {
          for (final l in (p['lines'] as List).cast<Map<String, dynamic>>()) {
            // Re-read each time: every sale uses up stock batches (FIFO), so
            // the next line must see what's left.
            final items = await repo.watchItems().first;
            final item = items.where((i) => i.id == l['item_id']).firstOrNull;
            if (item == null) throw StateError('${l['item_name']} is no longer in the tuck shop stock list.');
            await repo.logItemPurchase(item: item, employee: employee, qty: (l['qty'] as num).toDouble(), date: date);
          }
        }
      case CaptureModule.delivery:
        final produce = ProduceType.values.byName(p['produce_type'] as String);
        final truck = ActiveTruck(produceType: produce, date: DateTime.parse(p['date'] as String));
        truck.target = (p['target'] as num?)?.toInt() ?? kDefaultTarget;
        (p['pallets'] as Map?)?.forEach((k, v) => truck.pallets[k as String] = (v as num).toInt());
        for (final mp in (p['mixed_pallets'] as List?) ?? const []) {
          truck.mixedPallets.add({for (final e in (mp as Map).entries) e.key as String: (e.value as num).toInt()});
        }
        (p['peppers'] as Map?)?.forEach((k, v) => truck.peppers[k as String] = (v as num).toInt());
        (p['butternuts'] as Map?)?.forEach((k, v) => truck.butternuts[k as String] = (v as num).toInt());
        // Lands in Packaging > Records as a pending note, to get its reg,
        // transport and agent added and be approved like any other truck.
        await DeliveryRepository().saveNote(truck);
      case CaptureModule.employee:
        await _applyEmployee(p);
      case CaptureModule.payCheck:
        // A farm manager's Payslips check: tariff/rent/loan changes and new
        // extra pay, as if typed in the hub.
        final employees = EmployeesRepository();
        for (final c in ((p['changes'] as List?) ?? const []).cast<Map>()) {
          await employees.updatePay(
            c['employee_id'] as String,
            ratePerHour: (c['rate_per_hour'] as num?)?.toDouble(),
            rentDeduction: (c['rent_deduction'] as num?)?.toDouble(),
            loanDeduction: (c['loan_deduction'] as num?)?.toDouble(),
          );
        }
        // Haaskraal tuck shop debt typed in on the phone: what's owing there
        // becomes that amount.
        final list = await employees.watchEmployees().first;
        for (final c in ((p['changes'] as List?) ?? const []).cast<Map>()) {
          if (c['tuckshop_debt'] == null || c['tuckshop_farm_id'] == null) continue;
          await TuckshopRepository().setUnpaidDebt(
            employeeId: c['employee_id'] as String,
            employeeFarmId: list.where((e) => e.id == c['employee_id']).firstOrNull?.farmId,
            farmId: c['tuckshop_farm_id'] as String,
            amount: (c['tuckshop_debt'] as num).toDouble(),
            date: entry.capturedAt.toIso8601String().substring(0, 10),
            note: 'Payslips check: ${c['tuckshop_farm_name'] ?? 'tuck shop'} debt set to R ${(c['tuckshop_debt'] as num).toStringAsFixed(2)}',
          );
        }
        final hours = HoursRepository();
        // Hours since the last pay corrected on the phone: the difference is
        // added as one entry on that day (no overtime split -- it's a total).
        for (final c in ((p['changes'] as List?) ?? const []).cast<Map>()) {
          if (c['hours_since_last_pay'] == null) continue;
          final diff = (c['hours_since_last_pay'] as num).toDouble() - ((c['hours_was'] as num?)?.toDouble() ?? 0);
          if (diff.abs() < 0.001) continue;
          final day = await hours.fetchSettings();
          await hours.logIndividual(
            employeeId: c['employee_id'] as String,
            date: c['hours_up_to'] as String? ?? entry.capturedAt.toIso8601String().substring(0, 10),
            hours: diff,
            rate: list.where((e) => e.id == c['employee_id']).firstOrNull?.ratePerHour ?? 0,
            settings: HoursSettings(dailyThreshold: diff.abs() > day.dailyThreshold ? diff.abs() : day.dailyThreshold, otMultiplier: day.otMultiplier),
            farmId: p['farm_id'] as String?,
          );
        }
        for (final x in ((p['extras'] as List?) ?? const []).cast<Map>()) {
          await hours.addExtra(
            employeeId: x['employee_id'] as String,
            farmId: p['farm_id'] as String?,
            date: x['date'] as String,
            description: x['description'] as String,
            hours: (x['hours'] as num?)?.toDouble(),
            rate: (x['rate'] as num?)?.toDouble(),
            amount: (x['amount'] as num).toDouble(),
          );
        }
      default:
        throw ArgumentError('Unknown entry type ${entry.module}');
    }
  }
}

/// New worker / changed details / worker left, from the phone's Employee
/// details task. Only the fields the phone filled in are changed.
Future<void> _applyEmployee(Map<String, dynamic> p) async {
  final repo = EmployeesRepository();
  final employees = await repo.watchEmployees().first;
  String? str(String k) => (p[k] as String?)?.trim().isEmpty ?? true ? null : (p[k] as String).trim();
  final id = str('id_or_passport');
  if (id != null && employees.any((e) => e.id != p['employee_id'] && (e.idOrPassport ?? '').replaceAll(' ', '') == id.replaceAll(' ', ''))) {
    throw StateError('Someone in the employee list already has ID/passport $id.');
  }
  switch (p['action']) {
    case 'add':
      await repo.addEmployee(Employee(
        id: '',
        firstName: str('name') ?? '',
        lastName: '',
        idOrPassport: id,
        fullNames: str('full_names'),
        surname: str('surname'),
        farmId: str('farm_id'),
      ));
    case 'change' || 'remove':
      final e = employees.where((e) => e.id == p['employee_id']).firstOrNull;
      if (e == null) throw StateError('${p['employee_name']} is no longer in the employee list.');
      if (p['action'] == 'remove') {
        await repo.deleteEmployee(e.id);
      } else {
        await repo.updateEmployee(
          e.id,
          Employee(
            id: e.id,
            firstName: str('name') ?? e.firstName,
            lastName: str('name') == null ? e.lastName : '',
            idOrPassport: id ?? e.idOrPassport,
            fullNames: str('full_names') ?? e.fullNames,
            surname: str('surname') ?? e.surname,
            currentGroupId: e.currentGroupId,
            farmId: str('farm_id') ?? e.farmId,
            paymentMethod: e.paymentMethod,
            bankName: e.bankName,
            bankAccountNo: e.bankAccountNo,
            phoneNumber: e.phoneNumber,
            atmAccessCode: e.atmAccessCode,
          ),
        );
      }
    default:
      throw ArgumentError('Unknown employee action ${p['action']}');
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
