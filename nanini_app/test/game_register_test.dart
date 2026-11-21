import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/game_register/game_register_models.dart';
import 'package:nanini_app/features/game_register/game_register_repository.dart';
import 'package:nanini_app/features/game_register/game_register_screen.dart';
import 'package:nanini_app/features/game_register/game_register_xlsx.dart';

// Made-up counts.
GameCount g(String year, String farm, String species, int head, double value, int ord) =>
    GameCount(id: '$year$farm$species', yearStart: year, farm: farm, species: species, head: head, value: value, ord: ord);

final counts = [
  g('2025-03-01', 'PLAAS A', 'Kudu', 20, 4000, 1),
  g('2025-03-01', 'PLAAS B', 'Eland', 10, 6500, 2),
  g('2026-03-01', 'PLAAS A', 'Kudu', 18, 4000, 1),
  g('2026-03-01', 'PLAAS A', 'Zebra', 5, 4000, 2),
  g('2026-03-01', 'PLAAS B', 'Eland', 12, 6500, 3),
];

void main() {
  test('a year: per farm, the totals and the fair value movement on last year', () {
    final y = GameYear('2026-03-01', counts.where((c) => c.yearStart == '2026-03-01').toList(), counts.where((c) => c.yearStart == '2025-03-01').toList());
    expect(y.farms, ['PLAAS A', 'PLAAS B']);
    expect((y.farmTotal('PLAAS A'), y.farmHead('PLAAS A')), (92000.0, 23));
    expect(y.total, 92000 + 78000);
    expect(y.fairValueMovement, 170000 - 145000);
    expect(y.lastHead('PLAAS A', 'Kudu'), 20);
    expect(y.lastHead('PLAAS A', 'Zebra'), isNull);
    final x = Excel.decodeBytes(gameRegisterXlsx(y, preparedOn: '2026-11-21'));
    final rows = x['Game register'].rows.map((r) => r.map((c) => c?.value?.toString() ?? '').join('|')).toList();
    expect(rows.any((r) => r.startsWith('Kudu|18|4000|72000|20')), isTrue);
    expect(rows.any((r) => r.startsWith('||Fair value movement (billike waarde)|25000')), isTrue);
  });

  testWidgets('the screen: a new year started from last year\'s list, a count changed, the Excel', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    final saved = <String, Uint8List>{};
    await tester.pumpWidget(
      MaterialApp(
        home: GameRegisterScreen(
          repo: repo,
          today: DateTime(2027, 3, 5),
          save: (n, b) async {
            saved[n] = b;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Count at 28 Feb 2028'), findsOneWidget); // the year now: from 1 Mar 2027
    // Last year (to 28 Feb 2027) is the 2026 list: pick the year the 2026 list is last year of.
    await tester.tap(find.byKey(const Key('game_year')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Count at 28 Feb 2027').last);
    await tester.pumpAndSettle();
    expect(find.text('Kudu'), findsOneWidget);
    await tester.tap(find.byKey(const Key('game_PLAAS A_Kudu')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('game_edit_head')), '25');
    await tester.tap(find.byKey(const Key('game_edit_save')));
    await tester.pumpAndSettle();
    expect(repo.rows.firstWhere((r) => r.species == 'Kudu' && r.yearStart == '2026-03-01').head, 25);
    await tester.tap(find.byKey(const Key('game_excel')));
    await tester.pumpAndSettle();
    expect(saved.keys, ['Game register 2027.xlsx']);

    // The new year: started from last year's list.
    await tester.tap(find.byKey(const Key('game_year')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Count at 28 Feb 2028').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('game_from_last_year')));
    await tester.pumpAndSettle();
    expect(repo.rows.where((r) => r.yearStart == '2027-03-01').map((r) => r.species).toSet(), {'Kudu', 'Zebra', 'Eland'});
    expect(tester.takeException(), isNull);
  });
}

class _Repo extends GameRegisterRepository {
  final rows = [...counts];
  @override
  Future<List<GameCount>> fetchAll() async => rows;
  @override
  Future<({int females, int males})?> buffaloOnFarm() async => (females: 3, males: 1);
  @override
  Future<void> save(GameCount c) async {
    rows.removeWhere((r) => r.yearStart == c.yearStart && r.farm == c.farm && r.species == c.species);
    rows.add(
      GameCount(id: '${c.yearStart}${c.farm}${c.species}', yearStart: c.yearStart, farm: c.farm, species: c.species, head: c.head, value: c.value, ord: c.ord),
    );
  }

  @override
  Future<void> saveAll(List<GameCount> list) async {
    for (final c in list) {
      await save(c);
    }
  }
}
