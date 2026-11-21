import '../../core/live_rows.dart';
import '../../core/supabase_client.dart';
import 'term_loan_models.dart';

/// The term loan's statements, lines and opening balances
/// (docs/sql/term_loan.sql; scripts/import_term_loan.py reads the PDFs).
class TermLoanRepository {
  Future<List<TermLoanStatement>> fetchStatements() async => (await fetchAllRows(
    'term_loan_statements',
    orderBy: 'statement_date',
  )).where((r) => r['account_no'] == kTermLoanAccount).map(TermLoanStatement.fromJson).toList();

  Future<List<TermLoanLine>> fetchLines() async => (await fetchAllRows('term_loan_lines', orderBy: 'line_date')).map(TermLoanLine.fromJson).toList();

  /// Financial year start (yyyy-MM-dd) -> the opening balance entered.
  Future<Map<String, double>> fetchOpenings() async => {
    for (final r in await sb.from('term_loan_opening').select().eq('account_no', kTermLoanAccount)) r['year_start'] as String: (r['balance'] as num).toDouble(),
  };

  Future<void> saveOpening(String yearStart, double balance) =>
      sb.from('term_loan_opening').upsert({'account_no': kTermLoanAccount, 'year_start': yearStart, 'balance': balance});

  /// A transaction the statement left out, added by hand to [statementId].
  Future<void> addLine({required String statementId, required String date, required String description, required double amount}) =>
      sb.from('term_loan_lines').insert({'statement_id': statementId, 'line_date': date, 'description': description, 'amount': amount, 'manual': true});

  Future<void> deleteLine(String id) => sb.from('term_loan_lines').delete().eq('id', id).eq('manual', true);

  /// Marks what went to Xero: the lines, and each month's interest as sent.
  Future<void> markSent(List<TermLoanXeroItem> items) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final lineIds = [
      for (final i in items)
        if (i.line != null) i.line!.id,
    ];
    if (lineIds.isNotEmpty) await sb.from('term_loan_lines').update({'xero_sent_at': now}).inFilter('id', lineIds);
    for (final i in items) {
      if (i.month != null) {
        await sb.from('term_loan_statements').update({'xero_sent_at': now, 'xero_interest_sent': i.amount}).eq('id', i.month!.statement.id);
      }
    }
  }
}
