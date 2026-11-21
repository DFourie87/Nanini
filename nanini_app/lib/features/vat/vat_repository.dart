import '../../core/live_rows.dart';
import '../../core/supabase_client.dart';
import '../suppliers/suppliers_models.dart';
import '../suppliers/suppliers_repository.dart';
import '../xero/xero_export.dart' show xeroFixedAsset;
import 'vat_models.dart';

/// The VAT control's figures: the account sales and supplier invoices from
/// the hub, and what is kept by hand (docs/sql/vat_control.sql).
class VatRepository {
  /// The account sales from [from] to [to], with their pallets paid for.
  Future<List<VatSale>> fetchSales(String from, String to) async {
    final rows = <Map<String, dynamic>>[];
    for (var at = 0; ; at += 1000) {
      final page = await sb
          .from('sales_reports')
          .select('id, report_date, category, gross_total, vat, vat_on_sales')
          .gte('report_date', from)
          .lte('report_date', to)
          .order('id')
          .range(at, at + 999);
      rows.addAll((page as List).cast<Map<String, dynamic>>());
      if (page.length < 1000) break;
    }
    final pallets = <String, double>{};
    final ids = [for (final r in rows) r['id'] as String];
    for (var i = 0; i < ids.length; i += 100) {
      try {
        final part = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
        for (final d in await sb.from('sales_deductions').select('report_id, amount, vat').eq('kind', 'pallets').inFilter('report_id', part)) {
          final id = d['report_id'] as String;
          pallets[id] = (pallets[id] ?? 0) - ((d['amount'] as num).toDouble() + ((d['vat'] as num?)?.toDouble() ?? 0));
        }
      } catch (_) {
        break; // no deductions table yet
      }
    }
    double n(Object? v) => (v as num?)?.toDouble() ?? 0;
    return [
      for (final r in rows)
        (
          date: r['report_date'] as String,
          crop: _crop(r['category'] as String?),
          gross: n(r['gross_total']),
          vatOnSales: n(r['vat_on_sales']),
          deductionsVat: n(r['vat']),
          pallets: pallets[r['id']] ?? 0,
        ),
    ];
  }

  /// The supplier invoices' lines from [from] to [to].
  Future<List<VatPurchase>> fetchPurchases(String from, String to) async {
    final repo = SuppliersRepository();
    final suppliers = await repo.fetchSuppliers();
    final docs = await repo.fetchDocs();
    final payments = await repo.fetchPayments();
    Future<List<Map<String, dynamic>>> rows(String table, String orderBy, [String key = 'id']) async {
      try {
        return await fetchAllRows(table, orderBy: orderBy, key: key);
      } catch (_) {
        return const [];
      }
    }

    final chart = (await rows('gl_accounts', 'code', 'code')).map(GlAccount.fromJson).toList();
    final docLines = (await rows('supplier_doc_lines', 'doc_id')).map(DocLine.fromJson).toList();
    final rules = (await rows('supplier_gl_rules', 'item')).map(GlRule.fromJson).toList();
    final accounts = [for (final s in suppliers) SupplierAccount(s, docs, payments)];
    return [
      for (final l in purchasesFor(accounts, docLines, rules, from, to, chart: chart))
        if ((l.vat ?? 0) != 0) (date: l.doc.date, vat: l.vat!, capital: xeroFixedAsset(l.account ?? '')),
    ];
  }

  Future<List<VatManual>> fetchManual() async => [for (final r in await sb.from('vat_periods').select()) VatManual.fromJson(r)];

  Future<void> saveManual(VatManual m) => sb.from('vat_periods').upsert(m.toRow());

  /// Financial year start -> the sales per the financial statements.
  Future<Map<String, double>> fetchFsSales() async => {
    for (final r in await sb.from('vat_years').select()) r['year_start'] as String: (r['fs_sales'] as num).toDouble(),
  };

  Future<void> saveFsSales(String yearStart, double? amount) =>
      amount == null ? sb.from('vat_years').delete().eq('year_start', yearStart) : sb.from('vat_years').upsert({'year_start': yearStart, 'fs_sales': amount});
}

String _crop(String? category) {
  final c = (category ?? '').trim();
  if (c.isEmpty) return 'Other';
  return c[0].toUpperCase() + c.substring(1);
}
