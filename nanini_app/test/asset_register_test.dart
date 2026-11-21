import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/assets/asset_models.dart';
import 'package:nanini_app/features/assets/asset_register_screen.dart';
import 'package:nanini_app/features/assets/asset_repository.dart';
import 'package:nanini_app/features/assets/asset_xlsx.dart';
import 'package:nanini_app/features/suppliers/suppliers_models.dart';

// Made-up assets, laid out as the working papers' register.
Asset asset(
  String id,
  AssetCategory c,
  String what,
  String? bought,
  double cost, {
  double? rate,
  String? opening = '2026-03-01',
  double accum = 0,
  String? sold,
  double? proceeds,
  String? depFrom,
}) => Asset(
  id: id,
  category: c,
  description: what,
  purchaseDate: bought,
  cost: cost,
  rate: rate ?? c.rate,
  openingYear: opening,
  openingAccum: accum,
  disposedDate: sold,
  disposalProceeds: proceeds,
  depFrom: depFrom,
);

final assets = [
  asset('land', AssetCategory.land, 'Farm', null, 1000000),
  asset('bakkie', AssetCategory.vehicles, 'Bakkie', '2025-06-02', 600000, accum: 90000), // 9/12 of 20% last year
  asset('old', AssetCategory.implements, 'Old plough', '2010-01-01', 5000, accum: 4990), // R10 left
  asset('tractor', AssetCategory.implements, 'Tractor', '2026-07-15', 120000, opening: null), // bought this year
  asset('sold', AssetCategory.implements, 'Trailer', '2024-03-01', 60000, accum: 24000, sold: '2026-10-05', proceeds: 40000),
];

void main() {
  test('the year: cost, depreciation by the month (from the month bought, to the month sold), never below nil', () {
    final y = {for (final l in assetYear('2026-03-01', assets, const [])) l.asset.id: l};
    expect(y['land']!.depreciation, 0);
    expect(y['bakkie']!.depreciation, 120000); // a full year
    expect(y['bakkie']!.bookEnd, 600000 - 210000);
    expect(y['old']!.depreciation, 10); // what was left
    final t = y['tractor']!;
    expect((t.costStart, t.bought), (0.0, 120000.0));
    expect(t.depreciation, 16000); // Jul to Feb: 8 months
    final s = y['sold']!;
    expect(s.depreciation, 8000); // Mar to Oct: 60 000 x 20% x 8/12
    expect((s.sold, s.accumSold, s.costEnd, s.accumEnd, s.bookEnd), (60000.0, 32000.0, 0.0, 0.0, 0.0));
    expect(s.profitOnSale, 40000 - (60000 - 32000));
    // The next year: carried on, the sold one gone, the plough done.
    final next = {for (final l in assetYear('2027-03-01', assets, const [])) l.asset.id: l};
    expect(next.containsKey('sold'), isFalse);
    expect(next['bakkie']!.accumStart, 210000);
    expect(next['old']!.depreciation, 0);
    expect(next['tractor']!.costStart, 120000);
    expect(next['tractor']!.accumStart, 16000);
    // Set by hand for a year.
    final o = [(assetId: 'bakkie', yearStart: '2026-03-01', amount: 50000.0)];
    expect(assetYear('2026-03-01', assets, o).firstWhere((l) => l.asset.id == 'bakkie').overridden, isTrue);
    expect(assetYear('2027-03-01', assets, o).firstWhere((l) => l.asset.id == 'bakkie').accumStart, 140000);
    // Earlier years than the register brought in: only what was bought then.
    expect(assetYear('2025-03-01', assets, const []), isEmpty);
  });

  test('depreciation journals: the months before Xero together, then one a month; per account', () {
    final due = journalsDue('2026-03-01', DateTime(2026, 11, 21), assets, const [], const {});
    expect(
      [for (final j in due) (j.date, j.narration)],
      [('2026-08-31', 'Depreciation Mar 2026 to Aug 2026'), ('2026-09-30', 'Depreciation Sep 2026'), ('2026-10-31', 'Depreciation Oct 2026')],
    );
    // Sep: bakkie 10 000; tractor 2 000; trailer 1 000; the plough's R10 spread over its 12 months.
    expect(due[1].byAccount, {'6100/200': 10000.0, '5510/200': 2000.0 + 1000 + 0.83});
    final later = journalsDue('2026-03-01', DateTime(2026, 11, 21), assets, const [], {
      '2026-03-01',
      '2026-04-01',
      '2026-05-01',
      '2026-06-01',
      '2026-07-01',
      '2026-08-01',
      '2026-09-01',
    });
    expect(later.single.narration, 'Depreciation Oct 2026');
    expect(depreciationJournalRows('Depreciation Oct 2026', '2026-10-31', {'6100/200': 10000, '5510/200': 2750.83}), [
      ['Depreciation Oct 2026', '31/10/2026', 'Depreciation', '3610/000', 'No VAT', '12750.83', '', '', '', ''],
      ['Depreciation Oct 2026', '31/10/2026', 'Accumulated depreciation', '6100/200', 'No VAT', '-10000.00', '', '', '', ''],
      ['Depreciation Oct 2026', '31/10/2026', 'Accumulated depreciation', '5510/200', 'No VAT', '-2750.83', '', '', '', ''],
    ]);
  });

  test('the register as Excel: by group, the totals and per account', () {
    final x = Excel.decodeBytes(assetRegisterXlsx('2026-03-01', assetYear('2026-03-01', assets, const []), preparedOn: '2026-11-21'));
    final rows = x['Asset register'].rows.map((r) => r.map((c) => c?.value?.toString() ?? '').join('|')).toList();
    expect(rows.first, startsWith('Nanini 121 CC -- asset register'));
    expect(rows.any((r) => r.startsWith('B|VEHICLES -- 6100/100 / 6100/200')), isTrue);
    expect(rows.any((r) => r.startsWith('|3610/000 depreciation for the year||144010')), isTrue);
  });

  testWidgets('the screen: a purchase on an asset account to add, the journals and the Excel register', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    final saved = <String, Uint8List>{};
    await tester.pumpWidget(
      MaterialApp(
        home: AssetRegisterScreen(
          repo: repo,
          today: DateTime(2026, 11, 21),
          save: (n, b) async {
            saved[n] = b;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Bought, not in the register yet (1)'), findsOneWidget);
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();
    expect(find.text('From Agri Dealer, INV 77 (5510/100)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('asset_edit_save')));
    await tester.pumpAndSettle();
    final added = repo.rows.last;
    expect(
      (added.description, added.cost, added.category, added.purchaseDate, added.sourceKey),
      ('Disc harrow', 80000.0, AssetCategory.implements, '2026-10-12', 'd1:l1'),
    );
    expect(find.textContaining('Bought, not in the register yet'), findsNothing);

    await tester.tap(find.byKey(const Key('asset_journal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('asset_journal_save')));
    await tester.pumpAndSettle();
    final csv = utf8.decode(saved.entries.firstWhere((e) => e.key.endsWith('.csv')).value);
    expect(csv, startsWith('*Narration,*Date'));
    expect(csv, contains('Depreciation Oct 2026,31/10/2026,Depreciation,3610/000'));
    expect(repo.journaled, containsAll(['2026-03-01', '2026-10-01']));
    expect(find.text('Depreciation in Xero: up to date'), findsOneWidget);

    await tester.tap(find.byKey(const Key('asset_excel')));
    await tester.pumpAndSettle();
    expect(saved.keys, contains('Asset register year 2027.xlsx'));
    expect(tester.takeException(), isNull);
  });
}

class _Repo extends AssetRepository {
  final rows = [...assets];
  final journaled = <String>{};

  @override
  Future<List<Asset>> fetchAssets() async => rows;
  @override
  Future<List<DepOverride>> fetchOverrides() async => const [];
  @override
  Future<Set<String>> fetchJournaled() async => journaled;
  @override
  Future<void> save(Asset a, {bool isNew = false}) async {
    if (isNew) rows.add(Asset.fromJson({...a.toRow(), 'id': 'n${rows.length}'}));
  }

  @override
  Future<void> markJournaled(List<String> months, double amount) async => journaled.addAll(months);
  @override
  Future<List<PurchaseLine>> fetchAssetPurchases(String from, String to) async {
    final supplier = Supplier.fromJson({'id': 's', 'name': 'Agri Dealer'});
    final doc = SupplierDoc.fromJson({'id': 'd1', 'supplier_id': 's', 'kind': 'invoice', 'doc_date': '2026-10-12', 'amount': 92000, 'reference': 'INV 77'});
    final line = DocLine(id: 'l1', docId: 'd1', lineNo: 1, description: 'Disc harrow', excl: 80000, vat: 12000, glAccount: '5510/100');
    return [
      PurchaseLine(
        supplier: supplier,
        doc: doc,
        line: line,
        description: 'Disc harrow',
        excl: 80000,
        vat: 12000,
        account: '5510/100',
        source: GlSource.values.first,
      ),
    ];
  }
}
