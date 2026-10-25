import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/game_breeding/game_bloodline_screen.dart';
import 'package:nanini_app/features/game_breeding/game_breeding_models.dart';
import 'package:nanini_app/features/game_breeding/game_breeding_repository.dart';

class _Repo extends GameBreedingRepository {
  final asked = <String>[];

  @override
  Future<Map<String, String>> photoUrls(List<String> paths) async {
    asked.addAll(paths);
    return {};
  }
  @override
  Stream<List<GameAnimal>> watchAnimals(String species) => Stream.value([
        GameAnimal(species: 'Buffalo', tag: 'PO20', sex: 'F', born: '2015', owner: 'Nanini', sire: 'Pafuri', dam: 'O20', photo: 'Buffalo/PO20.jpg'),
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
    final repo = _Repo();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GameBloodlineScreen(repo: repo, species: 'Buffalo'))));
    await tester.pumpAndSettle();
    // The photos' links are fetched once, for the animals that have one.
    expect(repo.asked, ['Buffalo/PO20.jpg']);

    // Our book: cows, bulls, calves; its ancestors folded away; not Eljuro's.
    expect(find.text('Nanini Boerdery'), findsWidgets);
    expect(find.text('4 on the farm'), findsOneWidget);
    expect(find.text('Cows (1)'), findsOneWidget);
    expect(find.text('Bulls (2)'), findsOneWidget);
    expect(find.text('Calves (sex not known yet) (1)'), findsOneWidget);
    expect(find.text('Ancestors in the pedigrees (1)'), findsOneWidget);
    expect(find.textContaining('Kyle × R65'), findsNothing);
    // A cross is marked: outside the African breeding plan.
    expect(find.text('Cross'), findsOneWidget);
    // Grouped as cows and bulls already: no sex signs.
    expect(find.textContaining('♀'), findsNothing);
    expect(find.textContaining('♂'), findsNothing);
    // A cow's page lists her calves; tapping one opens its page.
    await tester.tap(find.text('PO20').first);
    await tester.pumpAndSettle();
    expect(find.text('Calves (2)'), findsOneWidget);
    expect(find.text('by Shingwedzi · bull'), findsOneWidget);
    await tester.tap(find.text('by Shingwedzi · bull'));
    await tester.pumpAndSettle();
    expect(find.text('SPO20'), findsWidgets);
    expect(find.text('Male'), findsOneWidget); // SPO20's page, not PO20's
    expect(find.textContaining(RegExp(r'^Calves \(\d')), findsNothing); // a bull: no calves list
    await tester.tapAt(const Offset(450, 20)); // close the sheet
    await tester.pumpAndSettle();

    // Eljuro's book: its own animals.
    await tester.tap(find.text('Eljuro Beleggings'));
    await tester.pumpAndSettle();
    expect(find.text('1 on the farm'), findsOneWidget);
    expect(find.textContaining('Kyle × R65'), findsOneWidget);
    await tester.tap(find.text('Nanini Boerdery').first);
    await tester.pumpAndSettle();

    // Mating guide: this book's cows; the % and the advice; and checking an outside animal.
    await tester.tap(find.text('Mating guide'));
    await tester.pumpAndSettle();
    expect(find.text('25.0%'), findsOneWidget);
    expect(find.text('Avoid *'), findsOneWidget);
    expect(find.text('* SPO20: Her son'), findsOneWidget);
    expect(find.text("Shared ancestors: She is SPO20's dam"), findsOneWidget);
    expect(find.text('3.1%'), findsNothing); // Kr65-19 is in Eljuro's book
    expect(find.text('Check an animal (to buy or new)'), findsOneWidget);

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
