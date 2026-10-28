import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../core/live_rows.dart';
import '../../core/supabase_client.dart';
import 'hours_models.dart';

class HoursRepository {
  // Paged (watchAllRows): these tables pass the server's 1000-row page, and
  // a plain .stream() would quietly leave the newest hours out of Summary.
  Stream<List<HoursEntry>> watchEntries() =>
      watchAllRows('hours_entries', orderBy: 'entry_date').map((r) => r.map(HoursEntry.fromJson).toList());

  Stream<List<KgEntry>> watchKgEntries() =>
      watchAllRows('kg_entries', orderBy: 'entry_date').map((r) => r.map(KgEntry.fromJson).toList());

  Future<HoursSettings> fetchSettings() async {
    final row = await sb.from('hours_settings').select().eq('id', 1).maybeSingle();
    return row != null ? HoursSettings.fromJson(row) : HoursSettings();
  }

  Future<void> saveSettings(HoursSettings s) =>
      sb.from('hours_settings').upsert({'id': 1, 'daily_threshold': s.dailyThreshold, 'ot_multiplier': s.otMultiplier});

  /// Inserts with the farm worked on; a database without the farm_id column
  /// yet (docs/sql/payslips_capture.sql not run) still saves, without it.
  Future<void> _insert(String table, List<Map<String, dynamic>> rows, String? farmId) async {
    if (farmId == null) return sb.from(table).insert(rows);
    try {
      await sb.from(table).insert([for (final r in rows) {...r, 'farm_id': farmId}]);
    } on PostgrestException catch (e) {
      if (!e.message.contains('farm_id')) rethrow;
      await sb.from(table).insert(rows);
    }
  }

  /// Workers already clocked on [date] at a farm other than [farmId] -- one
  /// farm a day, as the phones check -- with where, e.g.
  /// {id: 'Farm Limpopodraai - Stockpoort 9 h'}. Hours without a farm don't count.
  Future<Map<String, String>> clockedElsewhere(List<String> employeeIds, String date, String? farmId) async {
    if (employeeIds.isEmpty || farmId == null) return {};
    final rows = ((await sb.from('hours_entries').select('employee_id, farm_id, hours').inFilter('employee_id', employeeIds).eq('entry_date', date)) as List)
        .cast<Map<String, dynamic>>();
    final farmIds = {for (final r in rows) if (r['farm_id'] != null && r['farm_id'] != farmId) r['farm_id'] as String};
    if (farmIds.isEmpty) return {};
    final names = {
      for (final f in ((await sb.from('farms').select('id, name').inFilter('id', farmIds.toList())) as List).cast<Map<String, dynamic>>())
        f['id'] as String: f['name'] as String,
    };
    return clockedElsewhereFrom(rows, farmId, names);
  }

  Future<void> logIndividual({
    required String employeeId,
    required String date,
    required double hours,
    required double rate,
    required HoursSettings settings,
    String? farmId,
  }) {
    final calc = PayCalc.calc(hours, rate, settings.dailyThreshold);
    return _insert('hours_entries', [{
      'employee_id': employeeId,
      'entry_date': date,
      'hours': hours,
      'rate': rate,
      'daily_threshold': settings.dailyThreshold,
      'ot_multiplier': settings.otMultiplier,
      'normal_hours': calc.normal,
      'ot_hours': calc.ot,
      'gross': calc.gross,
      'via': 'individual',
    }], farmId);
  }

  Future<void> logGroup({
    required List<({String employeeId, double hours, double rate})> members,
    required String date,
    required HoursSettings settings,
    required String groupName,
    String? farmId,
  }) {
    final rows = members.map((m) {
      final calc = PayCalc.calc(m.hours, m.rate, settings.dailyThreshold);
      return {
        'employee_id': m.employeeId,
        'entry_date': date,
        'hours': m.hours,
        'rate': m.rate,
        'daily_threshold': settings.dailyThreshold,
        'ot_multiplier': settings.otMultiplier,
        'normal_hours': calc.normal,
        'ot_hours': calc.ot,
        'gross': calc.gross,
        'via': 'group',
        'group_name': groupName,
      };
    }).toList();
    return _insert('hours_entries', rows, farmId);
  }

  Future<void> logKg({required Map<String, double> employeeKg, required String date, required double ratePerKg, String? farmId}) {
    final rows = employeeKg.entries
        .where((e) => e.value > 0)
        .map((e) => {
              'employee_id': e.key,
              'entry_date': date,
              'kg': e.value,
              'rate_per_kg': ratePerKg,
              'gross': e.value * ratePerKg,
              'source': 'manual',
            })
        .toList();
    return _insert('kg_entries', rows, farmId);
  }

  Future<void> deleteEntry(String id) => sb.from('hours_entries').delete().eq('id', id);

  /// A work group's tariff on these hours (not yet paid): the pay check's
  /// second line (e.g. one worker's potato hours at another rate).
  Future<void> setGroupRate(List<String> entryIds, double rate) =>
      sb.from('hours_entries').update({'special_rate': rate}).inFilter('id', entryIds);
  Future<void> deleteKgEntry(String id) => sb.from('kg_entries').delete().eq('id', id);

  /// Tuck shop spend for an employee within a date range — used as a nett-pay deduction.
  Future<double> fetchShopSpend(String employeeId, DateTime from, DateTime to) async {
    final rows = await sb
        .from('tuckshop_purchases')
        .select('revenue, sale_date')
        .eq('employee_id', employeeId)
        .gte('sale_date', from.toIso8601String().split('T').first)
        .lte('sale_date', to.toIso8601String().split('T').first);
    return (rows as List).fold<double>(0, (s, r) => s + ((r['revenue'] as num?)?.toDouble() ?? 0));
  }

  Stream<List<PayExtra>> watchExtras() =>
      watchAllRows('pay_extras', orderBy: 'entry_date').map((r) => r.map(PayExtra.fromJson).toList());

  Future<void> addExtra({
    required String employeeId,
    String? farmId,
    required String date,
    required String description,
    double? hours,
    double? rate,
    required double amount,
  }) =>
      sb.from('pay_extras').insert({
        'employee_id': employeeId,
        'farm_id': farmId,
        'entry_date': date,
        'description': description,
        'hours': hours,
        'rate': rate,
        'amount': amount,
      });

  Future<void> deleteExtra(String id) => sb.from('pay_extras').delete().eq('id', id);

  Stream<List<Payslip>> watchPayslips() =>
      watchAllRows('payslips', orderBy: 'paid_date').map((r) => r.map(Payslip.fromJson).toList());

  /// Persists one payslip per employee and tags every tuck shop purchase and
  /// extra pay it swept up (payslip_id) so it's never pulled into a later
  /// run. A loan repayment is taken off once: back to R0 after the payslip
  /// that took it, until a new amount is entered. One insert per employee rather than a bulk insert so each
  /// payslip's generated id can be matched back to its own rows.
  Future<void> runPayroll(List<(Payslip, List<String> purchaseIds, List<String> extraIds)> drafts) async {
    if (drafts.isEmpty) return;
    // Never twice: anyone already paid up to this day (or later) stops the run.
    final ids = [for (final d in drafts) d.$1.employeeId];
    final paid = await sb.from('payslips').select('employee_id').inFilter('employee_id', ids).gte('period_end', drafts.first.$1.periodEnd) as List;
    if (paid.isNotEmpty) {
      throw StateError('${paid.length} of these workers are already paid up to ${drafts.first.$1.periodEnd} -- '
          'this payroll was already run. Close and open the Summary again to see it.');
    }
    // Every payslip in one go: if one can't be saved, none is -- never a
    // half-paid run. (One insert needs the same fields on every row.)
    final rows = [for (final d in drafts) d.$1.toInsert()];
    final keys = {for (final r in rows) ...r.keys};
    for (final r in rows) {
      for (final k in keys) {
        r.putIfAbsent(k, () => k == 'extra_pay' ? 0 : null);
      }
    }
    final saved = (await sb.from('payslips').insert(rows).select('id, employee_id') as List).cast<Map<String, dynamic>>();
    final idFor = {for (final r in saved) r['employee_id'] as String: r['id'] as String};
    for (final (payslip, purchaseIds, extraIds) in drafts) {
      final id = idFor[payslip.employeeId];
      if (id == null) continue;
      if (purchaseIds.isNotEmpty) {
        await sb.from('tuckshop_purchases').update({'payslip_id': id}).inFilter('id', purchaseIds);
      }
      if (extraIds.isNotEmpty) {
        await sb.from('pay_extras').update({'payslip_id': id}).inFilter('id', extraIds);
      }
    }
    final repaid = [for (final (p, _, _) in drafts) if (p.loan > 0 && idFor.containsKey(p.employeeId)) p.employeeId];
    if (repaid.isNotEmpty) await sb.from('employees').update({'loan_deduction': 0}).inFilter('id', repaid);
  }

}

/// [HoursRepository.clockedElsewhere] from the day's hours rows: each worker's
/// hours at farms other than [farmId], per farm (taken-off hours counted).
Map<String, String> clockedElsewhereFrom(List<Map<String, dynamic>> rows, String farmId, Map<String, String> farmNames) {
  final byWorker = <String, Map<String, double>>{};
  for (final r in rows) {
    final farm = r['farm_id'] as String?;
    if (farm == null || farm == farmId) continue;
    final perFarm = byWorker.putIfAbsent(r['employee_id'] as String, () => {});
    perFarm[farm] = (perFarm[farm] ?? 0) + (r['hours'] as num).toDouble();
  }
  String h(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
  return {
    for (final w in byWorker.entries)
      if (w.value.values.any((v) => v > 0.001))
        w.key: [for (final f in w.value.entries) if (f.value > 0.001) '${farmNames[f.key] ?? 'another farm'} ${h(f.value)} h'].join(', '),
  };
}
