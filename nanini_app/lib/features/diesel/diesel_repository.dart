import '../../core/formatters.dart';
import '../../core/supabase_client.dart';
import 'diesel_models.dart';

class DieselRepository {
  Stream<List<DieselTank>> watchTanks() =>
      sb.from('diesel_tanks').stream(primaryKey: ['id']).order('created_at').map((r) => r.map(DieselTank.fromJson).toList());

  Stream<List<DieselVehicle>> watchVehicles() =>
      sb.from('diesel_vehicles').stream(primaryKey: ['id']).order('name').map((r) => r.map(DieselVehicle.fromJson).toList());

  Stream<List<DieselActivity>> watchActivities() =>
      sb.from('diesel_activities').stream(primaryKey: ['id']).order('sort_order').map((r) => r.map(DieselActivity.fromJson).toList());

  Stream<List<DieselPurchase>> watchPurchases() => sb
      .from('diesel_purchases')
      .stream(primaryKey: ['id'])
      .order('purchase_date')
      .map((r) => r.map(DieselPurchase.fromJson).toList());

  Stream<List<DieselUsage>> watchUsage() =>
      sb.from('diesel_usage').stream(primaryKey: ['id']).order('usage_date').map((r) => r.map(DieselUsage.fromJson).toList());

  Stream<List<DieselAdjustment>> watchAdjustments() => sb
      .from('diesel_adjustments')
      .stream(primaryKey: ['id'])
      .order('adjustment_date')
      .map((r) => r.map(DieselAdjustment.fromJson).toList());

  // A plain fetch, not a realtime stream: this row only changes once a day
  // (the scheduled bulletin fetch), so there's nothing to subscribe to --
  // and a long-lived stream just risks going stale across tab switches.
  Future<DieselPriceForecast?> fetchDieselPriceForecast() async {
    final row = await sb.from('diesel_price_forecast').select().eq('id', 1).maybeSingle();
    return row == null ? null : DieselPriceForecast.fromJson(row);
  }

  Future<void> ensureDefaultActivities() async {
    final rows = await sb.from('diesel_activities').select();
    if ((rows as List).isEmpty) {
      await sb.from('diesel_activities').insert([
        for (final a in kDefaultDieselActivities) {'name': a.$1, 'eligible': a.$2, 'sort_order': a.$3},
      ]);
    }
  }

  Future<void> addTank({required String name, required double capacity, required double initialLevel}) =>
      sb.from('diesel_tanks').insert({'name': name, 'capacity': capacity, 'initial_level': initialLevel});

  Future<void> adjustTank({required String tankId, required double newLevel, String? note}) => sb.from('diesel_adjustments').insert({
        'tank_id': tankId,
        'new_level': newLevel,
        'note': note,
        'adjustment_date': todayStr(),
      });

  Future<void> addVehicle({required String name, String? asset, String? vin}) =>
      sb.from('diesel_vehicles').insert({'name': name, 'asset': asset, 'vin': vin});

  Future<void> updateVehicle(String id, {required String name, String? asset, String? vin}) =>
      sb.from('diesel_vehicles').update({'name': name, 'asset': asset, 'vin': vin}).eq('id', id);

  Future<void> deleteVehicle(String id) => sb.from('diesel_vehicles').delete().eq('id', id);

  Future<void> addActivity({required String name, required bool eligible}) =>
      sb.from('diesel_activities').insert({'name': name, 'eligible': eligible, 'sort_order': 999});

  Future<void> logUsage(DieselUsage draft) => sb.from('diesel_usage').insert({
        'tank_id': draft.tankId,
        'usage_date': draft.date,
        'litres': draft.litres,
        'equipment': draft.equipment,
        'asset': draft.asset ?? '',
        'hours': draft.hours ?? '',
        'activity': draft.activity,
        'eligible': draft.eligible,
        'notes': draft.notes ?? '',
        'employee_id': draft.employeeId,
      });

  Future<void> logPurchase(DieselPurchase draft) => sb.from('diesel_purchases').insert({
        'tank_id': draft.tankId,
        'purchase_date': draft.date,
        'litres': draft.litres,
        'invoice': draft.invoiceNote ?? '',
        'supplier': draft.supplier ?? '',
        'notes': draft.notes ?? '',
        'photo': draft.photo,
      });

  Future<void> addInvoiceDetails(String purchaseId, {double? cost, String? invoiceNo, String? invoiceFile}) =>
      sb.from('diesel_purchases').update({
        'cost': ?cost,
        'invoice_no': ?invoiceNo,
        'invoice_file': ?invoiceFile,
      }).eq('id', purchaseId);
}

/// Event-sourced tank level: replay initial level + all purchases (+),
/// usage (-), and adjustments (absolute reset) in chronological order.
/// Mirrors the web app's `tankLevel()` exactly — never stored directly.
double computeTankLevel(
  DieselTank tank, {
  required List<DieselPurchase> purchases,
  required List<DieselUsage> usage,
  required List<DieselAdjustment> adjustments,
}) {
  final events = <(DateTime, double Function(double))>[];
  for (final p in purchases.where((p) => p.tankId == tank.id)) {
    events.add((p.createdAt, (level) => level + p.litres));
  }
  for (final u in usage.where((u) => u.tankId == tank.id)) {
    events.add((u.createdAt, (level) => level - u.litres));
  }
  for (final a in adjustments.where((a) => a.tankId == tank.id)) {
    events.add((a.createdAt, (level) => a.newLevel));
  }
  events.sort((a, b) => a.$1.compareTo(b.$1));

  var level = tank.initialLevel;
  for (final e in events) {
    level = e.$2(level);
  }
  return level < 0 ? 0 : level;
}
