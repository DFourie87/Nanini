import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../core/supabase_client.dart';
import 'hours_models.dart';

class HoursRepository {
  Stream<List<HoursEntry>> watchEntries() =>
      sb.from('hours_entries').stream(primaryKey: ['id']).order('entry_date').map((r) => r.map(HoursEntry.fromJson).toList());

  Stream<List<KgEntry>> watchKgEntries() =>
      sb.from('kg_entries').stream(primaryKey: ['id']).order('entry_date').map((r) => r.map(KgEntry.fromJson).toList());

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
      sb.from('pay_extras').stream(primaryKey: ['id']).order('entry_date').map((r) => r.map(PayExtra.fromJson).toList());

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
      sb.from('payslips').stream(primaryKey: ['id']).order('paid_date').map((r) => r.map(Payslip.fromJson).toList());

  /// Persists one payslip per employee and tags every tuck shop purchase and
  /// extra pay it swept up (payslip_id) so it's never pulled into a later
  /// run. One insert per employee rather than a bulk insert so each
  /// payslip's generated id can be matched back to its own rows.
  Future<void> runPayroll(List<(Payslip, List<String> purchaseIds, List<String> extraIds)> drafts) async {
    for (final (payslip, purchaseIds, extraIds) in drafts) {
      final saved = await sb.from('payslips').insert(payslip.toInsert()).select().single();
      if (purchaseIds.isNotEmpty) {
        await sb.from('tuckshop_purchases').update({'payslip_id': saved['id']}).inFilter('id', purchaseIds);
      }
      if (extraIds.isNotEmpty) {
        await sb.from('pay_extras').update({'payslip_id': saved['id']}).inFilter('id', extraIds);
      }
    }
  }
}
