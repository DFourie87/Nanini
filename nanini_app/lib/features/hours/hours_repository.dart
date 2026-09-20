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

  Future<void> logIndividual({required String employeeId, required String date, required double hours, required double rate, required HoursSettings settings}) {
    final calc = PayCalc.calc(hours, rate, settings.dailyThreshold);
    return sb.from('hours_entries').insert({
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
    });
  }

  Future<void> logGroup({
    required List<({String employeeId, double hours, double rate})> members,
    required String date,
    required HoursSettings settings,
    required String groupName,
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
    return sb.from('hours_entries').insert(rows);
  }

  Future<void> logKg({required Map<String, double> employeeKg, required String date, required double ratePerKg}) {
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
    return sb.from('kg_entries').insert(rows);
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

  Stream<List<Payslip>> watchPayslips() =>
      sb.from('payslips').stream(primaryKey: ['id']).order('paid_date').map((r) => r.map(Payslip.fromJson).toList());

  /// Persists one payslip per employee and tags every tuck shop purchase it
  /// swept up as deducted (payslip_id) so it's never pulled into a later
  /// run. One insert per employee rather than a bulk insert so each
  /// payslip's generated id can be matched back to its own purchases.
  Future<void> runPayroll(List<(Payslip, List<String>)> drafts) async {
    for (final (payslip, purchaseIds) in drafts) {
      final saved = await sb.from('payslips').insert(payslip.toInsert()).select().single();
      if (purchaseIds.isNotEmpty) {
        await sb.from('tuckshop_purchases').update({'payslip_id': saved['id']}).inFilter('id', purchaseIds);
      }
    }
  }
}
