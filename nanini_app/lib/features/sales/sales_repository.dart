import '../../core/supabase_client.dart';
import 'sales_models.dart';

class SalesRepository {
  /// All reports, once (the Sales app loads on opening and on refresh --
  /// new reports only arrive once a day). Paged, so more than the server's
  /// 1000-row page still all come through.
  Future<List<SalesReport>> fetchReports() async {
    final out = <SalesReport>[];
    for (var from = 0;; from += 1000) {
      final rows = await sb.from('sales_reports').select().order('report_date').range(from, from + 999);
      out.addAll((rows as List).map((r) => SalesReport.fromJson(r as Map<String, dynamic>)));
      if (rows.length < 1000) return out;
    }
  }

  Stream<List<SalesReport>> watchReports() =>
      sb.from('sales_reports').stream(primaryKey: ['id']).order('report_date').map((r) => r.map(SalesReport.fromJson).toList());

  Future<List<SalesLineItem>> fetchLineItems(String reportId) async {
    final rows = await sb.from('sales_line_items').select().eq('report_id', reportId);
    return (rows as List).map((r) => SalesLineItem.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<SalesLineItem>> fetchLineItemsForReports(List<String> reportIds) async {
    if (reportIds.isEmpty) return [];
    final rows = await sb.from('sales_line_items').select().inFilter('report_id', reportIds);
    return (rows as List).map((r) => SalesLineItem.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<bool> reportNumberExists(String reportNumber) async {
    final rows = await sb.from('sales_reports').select('id').eq('report_number', reportNumber);
    return (rows as List).isNotEmpty;
  }

  Future<void> saveReport(SalesReport report, List<SalesLineItem> lineItems) async {
    final saved = await sb.from('sales_reports').insert(report.toInsert()).select().single();
    final reportId = saved['id'] as String;
    if (lineItems.isNotEmpty) {
      await sb.from('sales_line_items').insert(lineItems.map((li) => li.toInsert(reportId)).toList());
    }
  }

  Future<void> updateAgent(String reportId, String agent) => sb.from('sales_reports').update({'agent': agent}).eq('id', reportId);
}
