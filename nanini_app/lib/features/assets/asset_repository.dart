import '../../core/live_rows.dart';
import '../../core/supabase_client.dart';
import '../suppliers/suppliers_models.dart';
import '../suppliers/suppliers_repository.dart';
import 'asset_models.dart';

/// The asset register (docs/sql/assets.sql), and the purchases it is added from.
class AssetRepository {
  Future<List<Asset>> fetchAssets() async => (await fetchAllRows('assets', orderBy: 'id')).map(Asset.fromJson).toList();

  Future<List<DepOverride>> fetchOverrides() async => [
    for (final r in await sb.from('asset_dep_overrides').select())
      (assetId: r['asset_id'] as String, yearStart: r['year_start'] as String, amount: (r['amount'] as num).toDouble()),
  ];

  /// The months (yyyy-MM-01) whose depreciation journal is in Xero.
  Future<Set<String>> fetchJournaled() async => {for (final r in await sb.from('asset_journals').select('month')) r['month'] as String};

  Future<void> save(Asset a, {bool isNew = false}) => isNew ? sb.from('assets').insert(a.toRow()) : sb.from('assets').update(a.toRow()).eq('id', a.id);

  Future<void> delete(String id) => sb.from('assets').delete().eq('id', id);

  /// [amount] null: the year's depreciation worked out again.
  Future<void> setOverride(String assetId, String yearStart, double? amount) => amount == null
      ? sb.from('asset_dep_overrides').delete().eq('asset_id', assetId).eq('year_start', yearStart)
      : sb.from('asset_dep_overrides').upsert({'asset_id': assetId, 'year_start': yearStart, 'amount': amount});

  Future<void> markJournaled(List<String> months, double amount) => sb.from('asset_journals').upsert([
    for (final m in months) {'month': m, 'amount': months.length == 1 ? amount : 0},
  ]);

  /// The supplier invoices' lines from [from] to [to] on a fixed asset account.
  Future<List<PurchaseLine>> fetchAssetPurchases(String from, String to) async {
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
        if (isAssetAccount(l.account)) l,
    ];
  }
}

/// A fixed asset account in the chart: land, buildings, machinery and equipment, vehicles.
bool isAssetAccount(String? account) => RegExp(r'^(55\d\d|6100)/').hasMatch(account ?? '') && !(account ?? '').endsWith('/200');

/// The key of a purchase line, so it is added to the register once.
String purchaseKey(PurchaseLine l) => '${l.doc.id}:${l.line?.id ?? 'doc'}';
