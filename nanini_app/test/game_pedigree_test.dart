import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/game_breeding/game_bloodline_book.dart';
import 'package:nanini_app/features/game_breeding/game_breeding_models.dart';
import 'package:nanini_app/features/game_breeding/game_breeding_repository.dart';
import 'package:nanini_app/features/game_breeding/game_mating_check.dart';

GameAnimal an(String tag, {String? sex, String? sire, String? dam, String owner = 'Nanini', bool onFarm = true, String? horns, String? photo, String? notes}) =>
    GameAnimal(species: 'Buffalo', tag: tag, sex: sex, sire: sire, dam: dam, owner: onFarm ? owner : null, onFarm: onFarm, horns: horns, photo: photo, notes: notes);

final herd = [
  an('PO20', sex: 'F', sire: 'Pafuri', dam: 'Tag O20', horns: '32 1/8"', photo: 'Buffalo/PO20.jpg', notes: 'Dam of SPO20'),
  an('SPO20', sex: 'M', sire: 'Shingwedzi', dam: 'PO20'),
  an('Eben', sex: 'M', sire: 'Admiraal', dam: 'Tag 72', horns: '48"'),
  an('138', sex: 'F', sire: 'Tornado', dam: 'Cow Nr.16'),
  an('2T138', sex: 'F', sire: 'Tornado', dam: '138'),
  an('Kr65-19', sex: 'F', sire: 'Kyle', dam: 'R65', owner: 'Eljuro'),
  an('Shingwedzi', sex: 'M', sire: 'J66', dam: 'Y64', onFarm: false, horns: '49 2/8"'),
  an('Tornado', sex: 'M', sire: 'J66', dam: 'Y64', onFarm: false, horns: '49 5/8"'),
  an('Pafuri', sex: 'M', sire: 'J1', dam: 'Tag 65', onFarm: false),
  an('Kyle', sex: 'M', dam: 'Tag 66', onFarm: false),
  an('J66', sex: 'M', dam: 'Tag 66', onFarm: false),
  an('R65', sex: 'F', dam: 'Tag 65', onFarm: false),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ped = Pedigree(parentsByTag(herd, const []));

  test('Inbreeding from the pedigrees, as the inbreeding doc worked it out', () {
    expect(ped.kinship('PO20', 'SPO20'), 0.25); // her son
    expect(ped.inbreeding('2T138'), 0.25); // father × daughter
    expect(ped.kinship('PO20', 'Eben'), 0); // outcross
    expect(ped.kinship('138', 'SPO20'), closeTo(0.0625, 1e-9)); // Tornado and Shingwedzi full brothers
    expect(ped.shared('138', 'SPO20'), ['J66', 'Y64']);
    // Kyle and J66 share only their dam Tag 66.
    expect(ped.kinship('Kyle', 'J66'), 0.125);
  });

  test('The better photo: good enough for the book, or no smaller than the current one', () {
    expect(GameBreedingRepository.betterPhoto(1800, 1200, oldW: 900, oldH: 600), isTrue);
    // About as good (80%+ of the current one): the latest wins.
    expect(GameBreedingRepository.betterPhoto(640, 480, oldW: 900, oldH: 600), isTrue);
    expect(GameBreedingRepository.betterPhoto(600, 400, oldW: 900, oldH: 600), isFalse);
    expect(GameBreedingRepository.betterPhoto(640, 480), isTrue); // nothing to compare
    expect(GameBreedingRepository.betterPhoto(500, 400, oldW: 400, oldH: 300), isTrue);
  });

  testWidgets('Check an animal: an outside cow against our bulls, nothing stored', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: GameMatingCheckScreen(animals: herd, parents: parentsByTag(herd, const []), book: 'Nanini')));
    expect(find.text('Enter the sire or the dam to see the result.'), findsOneWidget);
    // A Shingwedzi daughter (as typed on a catalogue): SPO20's paternal half sister.
    await tester.enterText(find.widgetWithText(TextField, 'Sire'), 'Shingwedzi 49 2/8"');
    await tester.pumpAndSettle();
    expect(find.text('In the register – its own pedigree counts'), findsOneWidget);
    expect(find.text('12.5%'), findsOneWidget); // with SPO20
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Outcross'), findsOneWidget); // with Eben
    expect(find.textContaining('Shared: Shingwedzi'), findsOneWidget);
    // An unknown dam with a known grandsire: Tornado.
    await tester.enterText(find.widgetWithText(TextField, 'Dam'), 'Cow 7');
    await tester.pumpAndSettle();
    expect(find.text('Not in the register'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, "Dam's sire (optional)"), 'Tornado');
    await tester.pumpAndSettle();
    // Own inbreeding: Shingwedzi × a daughter of his full brother Tornado (uncle × niece): 1/8.
    expect(find.textContaining("own inbreeding: 12.5%"), findsOneWidget);
    // Eljuro's animals aren't in our book's check.
    expect(find.text('Kr65-19'), findsNothing);
  });

  test('Bloodline book: the whole book, and one animal\'s page', () async {
    final doc = await buildBloodlineBook(owner: 'Nanini', animals: herd, photo: (_) async => null, today: DateTime(2026, 10, 25));
    final bytes = await doc.save();
    // A cover and a page each for PO20, 138, 2T138, Eben, SPO20 (not Eljuro's, not ancestors).
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length, 6);
    final one = await (await buildBloodlineBook(owner: 'Nanini', animals: herd, photo: (_) async => null, only: herd.first)).save();
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(one)).length, 1);
    // Each herd's own logo (the only image here: no photos); none for another owner's.
    final image = RegExp(r'/Subtype\s*/Image');
    expect(image.hasMatch(String.fromCharCodes(bytes)), isTrue);
    final eljuro = await (await buildBloodlineBook(owner: 'Eljuro', animals: herd, photo: (_) async => null)).save();
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(eljuro)).length, greaterThan(1));
    expect(image.hasMatch(String.fromCharCodes(eljuro)), isTrue);
    final other = await (await buildBloodlineBook(owner: 'Someone', animals: [...herd, an('X1', sex: 'F', owner: 'Someone')], photo: (_) async => null)).save();
    expect(image.hasMatch(String.fromCharCodes(other)), isFalse);
    final out = Platform.environment['BOOK_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  test("A cow's calves: the register's, and births logged in the app, oldest first", () {
    final cow = GameAnimal(species: 'Buffalo', tag: 'PO20', sex: 'F', owner: 'Nanini');
    final animals = [
      cow,
      GameAnimal(species: 'Buffalo', tag: 'SPO20', sex: 'M', born: '2021', sire: 'Shingwedzi', dam: 'PO20'),
      GameAnimal(species: 'Buffalo', tag: 'BPO20', born: '2019', sire: 'B363', dam: 'PO20', status: 'sold'),
      GameAnimal(species: 'Buffalo', tag: 'Kr65-19', sex: 'F', dam: 'R65'),
    ];
    final events = [
      GameEvent(species: 'Buffalo', tagNumber: 'EPO20', eventType: GameEventType.birth, eventDate: '2026-10-01', sireTag: 'Eben', damTag: 'PO20'),
      GameEvent(species: 'Buffalo', tagNumber: 'SPO20', eventType: GameEventType.birth, eventDate: '2021-03-01', sireTag: 'Shingwedzi', damTag: 'PO20'),
    ];
    final calves = calvesOf(cow, animals, events);
    expect(calves.map((c) => c.tag), ['BPO20', 'SPO20', 'EPO20']);
    expect(calves.last.sire, 'Eben');
    expect(calves.last.born, '2026-10-01');
  });
}
