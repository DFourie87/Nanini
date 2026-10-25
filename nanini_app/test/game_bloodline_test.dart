import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/game_breeding/game_bloodline_screen.dart';
import 'package:nanini_app/features/game_breeding/game_breeding_models.dart';
import 'package:nanini_app/features/game_breeding/game_breeding_repository.dart';

class _Repo extends GameBreedingRepository {
  @override
  Stream<List<GameAnimal>> watchAnimals(String species) => Stream.value([
        GameAnimal(species: 'Buffalo', tag: 'PO20', sex: 'F', born: '2015', owner: 'Nanini', sire: 'Pafuri', dam: 'O20'),
        GameAnimal(species: 'Buffalo', tag: 'SPO20', sex: 'M', owner: 'Nanini', sire: 'Shingwedzi', dam: 'PO20'),
        GameAnimal(species: 'Buffalo', tag: 'Eben', name: 'Eben', sex: 'M', owner: 'Nanini'),
        GameAnimal(species: 'Buffalo', tag: 'Kr65-19', sex: 'F', born: '2019', owner: 'Eljuro', sire: 'Kyle', dam: 'R65', horns: '32"', microchip: '000'),
        GameAnimal(species: 'Buffalo', tag: 'BPO20', owner: 'Nanini', sire: 'B363', dam: 'PO20', subspecies: 'Cross (East African × African)'),
        GameAnimal(species: 'Buffalo', tag: 'Shingwedzi', name: 'Shingwedzi', sex: 'M', onFarm: false, sire: 'J66', dam: 'Y64'),
      ]);

  @override
  Stream<List<GameEvent>> watchEvents() => Stream.value(const []);

  @override
  Future<List<GameMating>> fetchMatings(String species) async => [
        GameMating(cowTag: 'PO20', bullTag: 'Eben', calfInbreeding: 0, advice: 'best'),
        GameMating(cowTag: 'PO20', bullTag: 'SPO20', calfInbreeding: 25, advice: 'avoid', shared: "She is SPO20's dam", note: 'Her son'),
        GameMating(cowTag: 'Kr65-19', bullTag: 'Eben', calfInbreeding: 0, advice: 'best'),
        GameMating(cowTag: 'Kr65-19', bullTag: 'SPO20', calfInbreeding: 3.1, advice: 'best', shared: 'Tag 65; Kyle'),
      ];
}

void main() {
  testWidgets('Bloodline: the herd, the mating guide and the family tree from the register', (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GameBloodlineScreen(repo: _Repo(), species: 'Buffalo'))));
    await tester.pumpAndSettle();

    // Herd: cows, bulls, calves; ancestors folded away; Eljuro's marked.
    expect(find.text('5 on the farm'), findsOneWidget);
    expect(find.text('Cows (2)'), findsOneWidget);
    expect(find.text('Bulls (2)'), findsOneWidget);
    expect(find.text('Calves (sex not known yet) (1)'), findsOneWidget);
    expect(find.text('Ancestors in the pedigrees (1)'), findsOneWidget);
    expect(find.text('Eljuro'), findsWidgets);
    expect(find.textContaining('Kyle × R65'), findsOneWidget);
    // A cross is marked: outside the African breeding plan.
    expect(find.text('Cross'), findsOneWidget);
    // Only Eljuro's.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Eljuro'));
    await tester.pumpAndSettle();
    expect(find.text('1 on the farm'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();

    // Mating guide: our cows first; the % and the advice.
    await tester.tap(find.text('Mating guide'));
    await tester.pumpAndSettle();
    expect(find.text('25.0%'), findsOneWidget);
    expect(find.text('Avoid *'), findsOneWidget);
    expect(find.text('* SPO20: Her son'), findsOneWidget);
    expect(find.text('3.1%'), findsOneWidget);
    expect(find.text("Shared ancestors: She is SPO20's dam"), findsOneWidget);
    expect(tester.getTopLeft(find.text('PO20').first).dy, lessThan(tester.getTopLeft(find.text('Kr65-19')).dy));

    // Family tree: SPO20 back through PO20 to Pafuri, and Shingwedzi to J66.
    await tester.tap(find.text('Family tree'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SPO20').last);
    await tester.pumpAndSettle();
    for (final t in ['Shingwedzi', 'J66', 'Y64', 'PO20', 'Pafuri', 'O20']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
  });
}
