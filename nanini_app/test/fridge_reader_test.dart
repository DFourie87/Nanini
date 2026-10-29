import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/fridge_reader.dart';
import 'package:nanini_app/capture_app/ref_data.dart';
import 'package:nanini_app/capture_app/timesheet_reader.dart';
import 'package:nanini_app/features/capture/fridge_sheet_capture.dart';

// A page photographed a little skew: table (u = points from the table's left
// edge, v = line) -> photo pixels (about 2.2 pixels a point).
(double, double) _photo(double u, double v) => (300 + 2.2 * u + 3 * v, 400 - 0.05 * u + 48.4 * v);

OcrBox _at(String text, double u, double v, {double h = 18}) {
  final (x, y) = _photo(u, v);
  return OcrBox(text, x, y, w: 11.0 * text.length, h: h);
}

/// A word printed left-aligned, starting at [left] (points).
OcrBox _left(String text, double left, double v) => _at(text, left + 11.0 * text.length / 2 / 2.2, v);

RefData _ref() => RefData(
      farms: const [RefItem('farmlimp-2222', 'Farm Limpopodraai - Stockpoort')],
      people: const [
        RefPerson(id: 'emp00000-aaaa', name: 'Lucas', surname: 'Moyo'),
        RefPerson(id: 'emp00001-bbbb', name: 'Lackson', surname: 'Dube'),
        RefPerson(id: 'emp00002-cccc', name: 'Tendai', surname: 'Ncube'),
      ],
      groups: const [],
      tanks: const [],
      vehicles: const [],
      activities: const [],
      shopItems: const [
        RefShopItem(id: 'itemwors-1', name: 'Wors', price: 45, stock: 30),
        RefShopItem(id: 'itemchic-2', name: 'Chicken pieces', price: 60, stock: 20),
      ],
    );

void main() {
  const qr = 'NFS2|2026-11|2026-10-31|2026-11-27|farmlimp|itemwors,itemchic|1/3|emp00000,emp00001';

  test('The QR code: the sheet, its items and the printed workers', () {
    final c = FridgeCode.parse(qr);
    expect(c.items, ['itemwors', 'itemchic']);
    expect(c.ids, ['emp00000', 'emp00001']);
    expect(c.first, '2026-10-31');
    expect(c.firstRow, 1);
    expect(FridgeCode.parse(qr.replaceFirst('1/3', '2/3')).firstRow, 21);
    expect(() => FridgeCode.parse('NTS2|2026-10|2026-09-26|2026-10-30|f|-|1/2|a'), throwsA(isA<SheetReadProblem>()));
    expect(() => FridgeCode.parse(null), throwsA(isA<SheetReadProblem>()));
  });

  test('The columns where the printed sheet has them (measured on the PDF)', () {
    final l = FridgeLayout(2);
    expect(l.nameLeft, closeTo(116.4, 0.5));
    expect(l.itemLeft(0), closeTo(209.0, 0.5));
    expect(l.totalLeft(0), closeTo(454.9, 0.5));
    expect(l.itemLeft(1), closeTo(495.4, 0.5));
    expect(l.totalCentre(1), closeTo(761.7, 0.5));
    expect(l.right, closeTo(782, 0.5));
  });

  test('Marks counted from what the recognition makes of them', () {
    expect(fridgeMarks(''), 0);
    expect(fridgeMarks('|||'), 3);
    expect(fridgeMarks('IIl1'), 4);
    expect(fridgeMarks('||||/'), 5);
    expect(fridgeMarks('H|'), 3);
    expect(fridgeMarks('M'), 3);
    expect(fridgeMarks('|-|.|'), 3);
    // A number written instead of marks.
    expect(fridgeMarks('7'), 7);
    expect(fridgeMarks('12'), 12);
    expect(fridgeMarks('11'), 2);
  });

  test('A Total box as a count', () {
    expect(fridgeTotalText(''), '');
    expect(fridgeTotalText('7'), '7');
    expect(fridgeTotalText('l2'), '12');
    expect(fridgeTotalText('O'), '0');
    expect(fridgeTotalText('-'), '');
    expect(fridgeTotalText('#'), '?');
  });

  test('The count as read: the total written, else the marks; unclear when they differ', () {
    expect(fridgeCount(4, '4'), 4);
    expect(fridgeCount(4, ''), 4);
    expect(fridgeCount(0, '6'), 6);
    expect(fridgeCount(0, ''), isNull);
    expect(fridgeCountUnclear(4, '4'), isFalse);
    expect(fridgeCountUnclear(0, '6'), isFalse);
    expect(fridgeCountUnclear(4, '5'), isTrue);
    expect(fridgeCountUnclear(4, '?'), isTrue);
  });

  test('A page photographed skew: each mark lands in its worker and item', () {
    final code = FridgeCode.parse(qr);
    final words = <OcrBox>[
      // Printed: the headings, the row numbers, the names (as measured on the PDF).
      _at('#', 9, FridgeLayout.headerRow),
      _left('Surname', 21, FridgeLayout.headerRow),
      _left('Name', 119.4, FridgeLayout.headerRow),
      _at('Total', 475.2, FridgeLayout.headerRow),
      _at('Total', 761.7, FridgeLayout.headerRow),
      for (var r = 0; r < kFridgeSheetRows; r++) _at('${r + 1}', 9, r.toDouble()),
      _left('Moyo', 21, 0),
      _left('Lucas', 119.4, 0),
      _left('Dube', 21, 1),
      _left('Lackson', 119.4, 1),
    ];
    final symbols = <OcrBox>[
      // Lucas: 4 wors marks, total 4; 2 chicken marks, no total.
      for (var k = 0; k < 4; k++) _at('|', 230 + 12.0 * k, 0.05),
      _at('4', 470, 0),
      _at('I', 520, -0.1), _at('l', 532, 0.1),
      // Lackson: marks read as "H|" (3), total written 5 -- to check.
      _at('H', 240, 1), _at('|', 255, 1.05),
      _at('5', 475, 1),
      // A new worker written on line 3: recognised by name and surname; 6 chicken (total only).
      for (final (k, ch) in 'Ncube'.split('').indexed) _at(ch, 24 + 8.0 * k, 2),
      for (final (k, ch) in 'Tendai'.split('').indexed) _at(ch, 122 + 8.0 * k, 2),
      _at('6', 760, 2),
      // A speck in the gap between lines: nowhere.
      _at('|', 300, 3.5),
    ];
    final read = readFridgeSheet(code: code, words: words, symbols: symbols, ref: _ref());
    expect(read['farm_id'], 'farmlimp-2222');
    expect((read['items'] as List).map((i) => (i as Map)['id']), ['itemwors-1', 'itemchic-2']);
    final rows = (read['rows'] as List).cast<Map<String, dynamic>>();
    expect(rows.map((r) => r['row']), [1, 2, 3]);
    List<Map> counts(int i) => (rows[i]['counts'] as List).cast<Map>();
    expect(rows[0]['employee_id'], 'emp00000-aaaa');
    expect(counts(0)[0], {'marks': 4, 'total': '4'});
    expect(counts(0)[1], {'marks': 2, 'total': ''});
    expect(counts(1)[0], {'marks': 3, 'total': '5'});
    expect(counts(1)[1], {'marks': 0, 'total': ''});
    expect(rows[2]['written_name'], 'Ncube Tendai');
    expect(rows[2]['employee_id'], 'emp00002-cccc');
    expect(counts(2)[1], {'marks': 0, 'total': '6'});
    expect(read['notes'], startsWith('1 box '));

    // As the hub reads it back.
    final r = FridgeRead.fromPayload({'read': read})!;
    expect(r.items.map((i) => i.name), ['Wors', 'Chicken pieces']);
    expect(r.rows[1].counts[0], (marks: 3, total: '5'));
    expect(r.purchaseNote, 'Fridge sheet Farm Limpopodraai - Stockpoort from 2026-10-31, page 1/3');
  });

  test('No landmarks found (blurry, cut off), or a farm the phone does not know: take it again', () {
    final code = FridgeCode.parse(qr);
    expect(() => readFridgeSheet(code: code, words: [_at('|', 230, 0)], ref: _ref()), throwsA(isA<SheetReadProblem>()));
    expect(() => readFridgeSheet(code: FridgeCode.parse(qr.replaceFirst('farmlimp', 'farmxxxx')), words: const [], ref: _ref()), throwsA(isA<SheetReadProblem>()));
  });

  test('The purchases go in on the day of the photo, not after the sheet\'s last day', () {
    expect(fridgeSaleDate(DateTime(2026, 11, 25, 15), '2026-11-27'), '2026-11-25');
    expect(fridgeSaleDate(DateTime(2026, 11, 30, 8), '2026-11-27'), '2026-11-27');
  });
}
