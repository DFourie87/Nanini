import '../../core/supabase_client.dart';
import 'delivery_models.dart';

class DeliveryRepository {
  Stream<List<DeliveryNote>> watchNotes() =>
      sb.from('delivery_notes').stream(primaryKey: ['id']).order('created_at').map((r) => r.map(DeliveryNote.fromJson).toList());

  Stream<List<PalletPurchase>> watchPurchases() => sb
      .from('delivery_pallet_purchases')
      .stream(primaryKey: ['id'])
      .order('recorded_at')
      .map((r) => r.map(PalletPurchase.fromJson).toList());

  Future<List<MarketAgent>> fetchMarketAgents() async {
    final rows = await sb.from('delivery_market_agents').select().order('name');
    var agents = (rows as List).map((r) => MarketAgent.fromJson(r as Map<String, dynamic>)).toList();
    if (agents.isEmpty) {
      final seeded = await sb
          .from('delivery_market_agents')
          .insert(kDefaultMarketAgents.map((a) => {'name': a.$1, 'attention': a.$2, 'market': a.$3}).toList())
          .select();
      agents = (seeded as List).map((r) => MarketAgent.fromJson(r as Map<String, dynamic>)).toList();
    }
    return agents;
  }

  Future<void> addMarketAgent({required String name, String? attention, String? market}) =>
      sb.from('delivery_market_agents').insert({'name': name, 'attention': attention, 'market': market});

  Future<void> updateMarketAgent(String id, {required String name, String? attention, String? market}) => sb
      .from('delivery_market_agents')
      .update({'name': name, 'attention': attention, 'market': market}).eq('id', id);

  Future<void> deleteMarketAgent(String id) => sb.from('delivery_market_agents').delete().eq('id', id);

  /// YY + month (no leading zero) + this month's sequence (no leading zero),
  /// e.g. the 3rd note in September 2026 -> "26" + "9" + "3" = 2693.
  Future<int> _nextNoteNumber(DateTime date) async {
    final monthStart = DateTime(date.year, date.month, 1);
    final monthEnd = DateTime(date.year, date.month + 1, 1);
    final rows = await sb
        .from('delivery_notes')
        .select('id')
        .gte('note_date', monthStart.toIso8601String().split('T').first)
        .lt('note_date', monthEnd.toIso8601String().split('T').first);
    final seq = (rows as List).length + 1;
    return int.parse('${date.year % 100}${date.month}$seq');
  }

  Future<DeliveryNote> saveNote(ActiveTruck truck, {required String reg, String? transportCompany, MarketAgent? agent}) async {
    final produceTypeStr = truck.produceType.name;
    final noteNumber = await _nextNoteNumber(truck.date);
    final row = {
      'note_number': noteNumber,
      'reg': reg,
      'transport_company': transportCompany,
      'agent_name': agent?.name,
      'agent_attention': agent?.attention,
      'agent_market': agent?.market,
      'note_date': truck.date.toIso8601String().split('T').first,
      'target': truck.produceType == ProduceType.potato ? truck.target : null,
      'field': truck.field ?? '',
      'pallets': truck.produceType == ProduceType.potato ? truck.pallets : {},
      'mixed_pallets': truck.produceType == ProduceType.potato ? truck.mixedPallets : [],
      'produce_type': produceTypeStr,
      'produce_detail': truck.produceType == ProduceType.pepper
          ? truck.peppers
          : truck.produceType == ProduceType.butternut
              ? truck.butternuts
              : null,
      'total': switch (truck.produceType) {
        ProduceType.potato => truck.totalPallets,
        ProduceType.pepper => truck.totalPepperBoxes,
        ProduceType.butternut => truck.totalButternutBags,
      },
    };
    final data = await sb.from('delivery_notes').insert(row).select().single();
    return DeliveryNote.fromJson(data);
  }

  Future<void> deleteNote(String id) => sb.from('delivery_notes').delete().eq('id', id);

  Future<void> logPalletPurchase({required MarketAgent agent, required int qty, required String date}) =>
      sb.from('delivery_pallet_purchases').insert({'agent_name': agent.name, 'qty': qty, 'purchase_date': date});

  Future<void> deletePalletPurchase(String id) => sb.from('delivery_pallet_purchases').delete().eq('id', id);
}
