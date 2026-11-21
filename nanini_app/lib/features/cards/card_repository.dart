import '../../core/live_rows.dart';
import '../../core/supabase_client.dart';
import 'card_models.dart';

/// The cards' statements, lines and opening balances
/// (docs/sql/card_statements.sql; scripts/import_card_statements.py reads the PDFs).
class CardRepository {
  Future<List<CardStatement>> fetchStatements(CardKind card) async =>
      (await fetchAllRows('card_statements', orderBy: 'statement_date')).where((r) => r['card'] == card.code).map(CardStatement.fromJson).toList();

  Future<List<CardLine>> fetchLines(List<String> statementIds) async {
    if (statementIds.isEmpty) return const [];
    final out = <CardLine>[];
    for (var i = 0; i < statementIds.length; i += 100) {
      final part = statementIds.sublist(i, i + 100 > statementIds.length ? statementIds.length : i + 100);
      out.addAll((await sb.from('card_lines').select().inFilter('statement_id', part) as List).map((r) => CardLine.fromJson(r as Map<String, dynamic>)));
    }
    return out;
  }

  /// Financial year start (yyyy-MM-dd) -> the opening balance entered.
  Future<Map<String, double>> fetchOpenings(CardKind card) async => {
    for (final r in await sb.from('card_opening').select().eq('card', card.code)) r['year_start'] as String: (r['balance'] as num).toDouble(),
  };

  Future<void> saveOpening(CardKind card, String yearStart, double balance) =>
      sb.from('card_opening').upsert({'card': card.code, 'year_start': yearStart, 'balance': balance});

  /// A line the statement left out, added by hand to [statementId].
  Future<void> addLine({required String statementId, required String date, required String description, required double amount}) =>
      sb.from('card_lines').insert({'statement_id': statementId, 'line_date': date, 'description': description, 'amount': amount, 'manual': true});

  Future<void> deleteLine(String id) => sb.from('card_lines').delete().eq('id', id).eq('manual', true);

  /// Marks [lineIds] as in Xero.
  Future<void> markSent(List<String> lineIds) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (var i = 0; i < lineIds.length; i += 100) {
      await sb.from('card_lines').update({'xero_sent_at': now}).inFilter('id', lineIds.sublist(i, i + 100 > lineIds.length ? lineIds.length : i + 100));
    }
  }
}
