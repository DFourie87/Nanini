import '../../core/live_rows.dart';
import '../../core/supabase_client.dart';
import '../sales/potato_fields.dart';
import 'bag_stock.dart';
import 'delivery_models.dart';
import 'pallet_stock.dart';

class DeliveryRepository {
  /// All notes, once (paged past the server's 1000-row page).
  Future<List<DeliveryNote>> fetchNotes() async {
    final notes = <DeliveryNote>[];
    for (var from = 0;; from += 1000) {
      final rows = await sb.from('delivery_notes').select().order('created_at').range(from, from + 999);
      for (final row in rows as List) {
        try {
          notes.add(DeliveryNote.fromJson(row as Map<String, dynamic>));
        } catch (_) {}
      }
      if (rows.length < 1000) return notes;
    }
  }

  // Read in full and reloaded on any change (watchAllRows): a dropped live
  // connection (phone asleep, weak signal) doesn't empty the screens.
  Stream<List<DeliveryNote>> watchNotes() => watchAllRows('delivery_notes', orderBy: 'created_at').map((rows) {
        final notes = <DeliveryNote>[];
        for (final row in rows) {
          try {
            notes.add(DeliveryNote.fromJson(row));
          } catch (_) {
            // Skip a malformed row rather than breaking the whole list.
          }
        }
        return notes;
      });

  Stream<List<PalletPurchase>> watchPurchases() =>
      watchAllRows('delivery_pallet_purchases', orderBy: 'recorded_at').map((r) => r.map(PalletPurchase.fromJson).toList());

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

  /// Every customer and delivery recipient to choose from on a note
  /// ([customerChoices]); just the recipients if the customers can't be read.
  Future<List<MarketAgent>> fetchCustomerChoices() async {
    final recipients = await fetchMarketAgents();
    try {
      final rows = await sb.from('customers').select('id,name').order('name');
      return customerChoices([for (final r in rows as List) (r['id'] as String, r['name'] as String)], recipients);
    } catch (_) {
      return recipients;
    }
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

  /// Logs a full truck as a pending delivery note -- reg, transport company,
  /// field and market agent aren't known yet at this point; those are added
  /// (and the note approved for printing) later from the Records tab.
  Future<DeliveryNote> saveNote(ActiveTruck truck) async {
    final produceTypeStr = truck.produceType.name;
    final noteNumber = await _nextNoteNumber(truck.date);
    final row = {
      'note_number': noteNumber,
      'note_date': truck.date.toIso8601String().split('T').first,
      'farm': truck.farm,
      'target': truck.produceType == ProduceType.potato ? truck.target : null,
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
      'status': 'pending',
    };
    final data = await sb.from('delivery_notes').insert(row).select().single();
    return DeliveryNote.fromJson(data);
  }

  /// Adds the details a pending note is missing (field, transport company,
  /// truck reg, market agent) and approves it, making it available to print.
  Future<void> approveNote(
    String id, {
    String? reg,
    String? transportCompany,
    bool isSelfTransport = false,
    String? field,
    MarketAgent? agent,
    String? farm,
    String? noteDate,
    String? agentExtra,
  }) =>
      sb.from('delivery_notes').update({
        // Only sent when typed: works before delivery_note_extra_line.sql.
        'agent_extra': ?agentExtra,
        // The date printed on the note (yyyy-MM-dd), when corrected.
        'note_date': ?noteDate,
        'reg': reg,
        'transport_company': isSelfTransport ? null : transportCompany,
        'is_self_transport': isSelfTransport,
        'field': field ?? '',
        'agent_name': agent?.name,
        'agent_attention': agent?.attention,
        'agent_market': agent?.market,
        'farm': farm,
        'status': 'approved',
      }).eq('id', id);

  Future<void> deleteNote(String id) => sb.from('delivery_notes').delete().eq('id', id);

  /// Pallets collected at an agent, an adjustment or a floor count
  /// (docs/sql/pallets_floor.sql adds kind and description).
  Future<void> addPalletEntry({required String agentName, required int qty, required String date, PalletEntryKind kind = PalletEntryKind.collected, String? description}) =>
      sb.from('delivery_pallet_purchases').insert({
        'agent_name': agentName,
        'qty': qty,
        'purchase_date': date,
        if (kind != PalletEntryKind.collected) 'kind': kind.name,
        'description': ?description,
      });

  /// Pallets the agents paid for (Green Network's pallet invoices, read with
  /// their account sales into sales_deductions), under the agent's customer
  /// name; [] before docs/sql/sales_deductions.sql is run.
  Future<List<PalletsPaidFor>> fetchPalletsPaidFor() async {
    try {
      final rows = await sb.from('sales_deductions').select('label, amount, vat, sales_reports(agent, report_date)').eq('kind', 'pallets');
      final customers = await sb.from('customers').select('name, agent');
      final names = {for (final c in customers as List) c['agent'] as String: c['name'] as String};
      return [
        for (final r in rows as List)
          if (palletCount(r['label'] as String? ?? '') != null)
            PalletsPaidFor(
              agentName: names[r['sales_reports']?['agent']] ?? (r['sales_reports']?['agent'] as String? ?? ''),
              qty: palletCount(r['label'] as String)!,
              date: r['sales_reports']?['report_date'] as String? ?? '',
              document: palletInvoiceNumber(r['label'] as String) ?? (r['label'] as String),
              amount: -((r['amount'] as num?)?.toDouble() ?? 0) - ((r['vat'] as num?)?.toDouble() ?? 0),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Potato pallets packed but not sent (entered in Sales > Summary).
  Future<List<UnsentPallets>> fetchUnsentPallets() async {
    final rows = await sb.from('potato_unsent_pallets').select().order('packed_date');
    return [for (final r in rows as List) UnsentPallets.fromJson(r as Map<String, dynamic>)];
  }

  /// Bags and boxes bought (Packaging > Bags/Boxes; docs/sql/bag_purchases.sql).
  Stream<List<BagPurchase>> watchBagPurchases() => watchAllRows('bag_purchases', orderBy: 'purchase_date').map(
        (rows) => [for (final r in rows) ?BagPurchase.fromJson(r)],
      );

  /// Bags received, an adjustment or a floor count ([kind]).
  Future<void> addBagPurchase(
          {required ProduceType produce, required String item, required int qty, required String date, BagEntryKind kind = BagEntryKind.bought, String? reference, String? description}) =>
      sb.from('bag_purchases').insert({
        'produce': produce.name,
        'item': item,
        'qty': qty,
        'purchase_date': date,
        'kind': kind.name,
        'reference': reference,
        'description': description,
      });

  Future<void> deleteBagPurchase(String id) => sb.from('bag_purchases').delete().eq('id', id);

  Future<void> deletePalletPurchase(String id) => sb.from('delivery_pallet_purchases').delete().eq('id', id);
}
