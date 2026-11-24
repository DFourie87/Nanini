import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/ref_data.dart';
import 'package:nanini_app/capture_app/timesheet_reader.dart';

// A page photographed a little skew: table (u = day column, v = line) -> photo pixels.
(double, double) _photo(double u, double v) => (900 + 62 * u + 4 * v, 500 - 3 * u + 88 * v);

OcrBox _at(String text, double u, double v, {double h = 26}) {
  final (x, y) = _photo(u, v);
  return OcrBox(text, x, y, w: 14.0 * text.length, h: h);
}

RefData _ref() => RefData(
      farms: const [RefItem('farmhaas-1111', 'Farm Haaskraal - Swartwater'), RefItem('farmlimp-2222', 'Farm Limpopodraai - Stockpoort')],
      people: const [
        RefPerson(id: 'emp00000-aaaa', name: 'Lucas', surname: 'Moyo'),
        RefPerson(id: 'emp00001-bbbb', name: 'Lackson', surname: 'Dube'),
        RefPerson(id: 'emp00002-cccc', name: 'Tendai', surname: 'Ncube', idOrPassport: 'FN 123456'),
      ],
      groups: const [],
      tanks: const [],
      vehicles: const [],
      activities: const [],
      shopItems: const [],
    );

void main() {
  const qr = 'NTS2|2026-10|2026-09-26|2026-10-30|farmhaas|-|1/2|emp00000,emp00001';

  test('The QR code: the sheet, its days and the printed workers', () {
    final c = SheetCode.parse(qr);
    expect(c.days.length, 35);
    expect(c.days.first, '2026-09-26');
    expect(c.days.last, '2026-10-30');
    expect(c.ids, ['emp00000', 'emp00001']);
    expect(c.firstRow, 1);
    expect(SheetCode.parse('NTS2|2026-10|2026-09-26|2026-10-30|f|-|2/2|').firstRow, 21);
    expect(() => SheetCode.parse('NTS1|2026-11|farm|-|1/2|a'), throwsA(isA<SheetReadProblem>()));
    expect(() => SheetCode.parse(null), throwsA(isA<SheetReadProblem>()));
  });

  test('A box as hours: numbers, common misreadings, empty marks and nonsense', () {
    expect(sheetCellText(''), '');
    expect(sheetCellText('8'), '8');
    expect(sheetCellText('9,5'), '9.5');
    expect(sheetCellText('9.5'), '9.5');
    expect(sheetCellText('B'), '8');
    expect(sheetCellText('l0'), '10');
    expect(sheetCellText('½'), '0.5');
    expect(sheetCellText('-'), '');
    expect(sheetCellText('A'), '');
    expect(sheetCellText('x'), '');
    expect(sheetCellText('88'), '?');
    expect(sheetCellText('#'), '?');
  });

  test('A page photographed skew: each handwritten number lands in its box', () {
    final code = SheetCode.parse(qr);
    final layout = SheetLayout(code.days.length);
    final words = <OcrBox>[
      // Printed: the day numbers along the top, the weekday letters under them.
      for (final (i, d) in code.days.indexed) ...[
        _at('${DateTime.parse(d).day}', i.toDouble(), SheetLayout.headerRow),
        _at('MTWTFSS'[DateTime.parse(d).weekday - 1], i.toDouble(), SheetLayout.headerRow + 0.46),
      ],
      _at('Surname', -9, -1.04),
      // Row numbers down the left, and the printed names.
      for (var r = 0; r < kSheetRows; r++) _at('${r + 1}', layout.hashCentre, r.toDouble(), h: 22),
      _at('Moyo', -10.2, 0),
      _at('Lucas', -6.8, 0),
      _at('Dube', -10.2, 1),
      _at('Lackson', -6.8, 1),
    ];
    final symbols = <OcrBox>[
      // Lucas: 8 on 26 Sep, 9,5 on 28 Sep (three characters), total 17,5.
      _at('8', 0.05, 0.1),
      _at('9', 1.8, -0.05), _at(',', 2.0, 0.1), _at('5', 2.2, -0.05),
      _at('1', layout.dayCount + 0.1, 0), _at('7', layout.dayCount + 0.3, 0), _at(',', layout.dayCount + 0.45, 0.05), _at('5', layout.dayCount + 0.6, 0),
      // Lackson: B (an 8) on 1 Oct, a scribble on 2 Oct.
      _at('B', 5.1, 0.95),
      _at('#', 6, 1.05),
      // A new worker written on line 3 (row 3): name, ID matching an employee, 8 on the last day.
      for (final (k, ch) in 'Ncube'.split('').indexed) _at(ch, -10.2 + 0.4 * k, 2),
      for (final (k, ch) in 'Tendai'.split('').indexed) _at(ch, -6.9 + 0.4 * k, 2),
      for (final (k, ch) in 'FN123456'.split('').indexed) _at(ch, -3.9 + 0.4 * k, 2),
      _at('8', 34, 2),
    ];
    final read = readSheet(code: code, words: words, symbols: symbols, ref: _ref());
    expect(read['farm_id'], 'farmhaas-1111');
    expect(read['days'], hasLength(35));
    final rows = (read['rows'] as List).cast<Map<String, dynamic>>();
    expect(rows.map((r) => r['row']), [1, 2, 3]);
    final lucas = rows[0], lackson = rows[1], tendai = rows[2];
    expect(lucas['employee_id'], 'emp00000-aaaa');
    expect((lucas['hours'] as List)[0], '8');
    expect((lucas['hours'] as List)[2], '9.5');
    expect((lucas['hours'] as List).where((h) => h != ''), hasLength(2));
    expect(lucas['total'], '17.5');
    expect((lackson['hours'] as List)[5], '8');
    expect((lackson['hours'] as List)[6], '?');
    expect(tendai['written_name'], 'Ncube Tendai');
    expect(tendai['id_number'], 'FN123456');
    expect(tendai['employee_id'], 'emp00002-cccc');
    expect((tendai['hours'] as List)[34], '8');
    expect(read['notes'], '1 box not clear');
  });

  test('A sheet printed without the ID column (NTS3): names wider, a new worker found by name', () {
    final code = SheetCode.parse(qr.replaceFirst('NTS2', 'NTS3'));
    expect(code.hasIdColumn, isFalse);
    expect(SheetCode.parse(qr).hasIdColumn, isTrue); // sheets printed before still read
    final layout = SheetLayout(code.days.length, withId: false);
    expect(layout.idNumber, isNull);
    expect(layout.name, (-3.7, -0.5));
    expect(layout.surname.$1, closeTo(-7.1, 1e-9));
    final words = <OcrBox>[
      for (final (i, d) in code.days.indexed) ...[
        _at('${DateTime.parse(d).day}', i.toDouble(), SheetLayout.headerRow),
        _at('MTWTFSS'[DateTime.parse(d).weekday - 1], i.toDouble(), SheetLayout.headerRow + 0.46),
      ],
      for (var r = 0; r < kSheetRows; r++) _at('${r + 1}', layout.hashCentre, r.toDouble(), h: 22),
      _at('Moyo', -6.6, 0),
      _at('Lucas', -3.2, 0),
      _at('Dube', -6.6, 1),
      _at('Lackson', -3.2, 1),
    ];
    final symbols = <OcrBox>[
      _at('8', 0.05, 0.1),
      // A new worker written on line 3: surname and name only -- found by name.
      for (final (k, ch) in 'Ncube'.split('').indexed) _at(ch, -6.6 + 0.4 * k, 2),
      for (final (k, ch) in 'Tendai'.split('').indexed) _at(ch, -3.3 + 0.4 * k, 2),
      _at('9', 33, 2),
    ];
    final rows = (readSheet(code: code, words: words, symbols: symbols, ref: _ref())['rows'] as List).cast<Map<String, dynamic>>();
    expect(rows.map((r) => r['row']), [1, 2, 3]); // the printed workers always, then the written one
    expect((rows[0]['hours'] as List)[0], '8');
    expect(rows[1]['employee_id'], 'emp00001-bbbb');
    expect(rows[2]['written_name'], 'Ncube Tendai');
    expect(rows[2]['id_number'], '');
    expect(rows[2]['employee_id'], 'emp00002-cccc');
    expect((rows[2]['hours'] as List)[33], '9');
  });

  test('No landmarks found (blurry, cut off): take the photo again', () {
    final code = SheetCode.parse(qr);
    expect(() => readSheet(code: code, words: [_at('8', 0, 0)], ref: _ref()), throwsA(isA<SheetReadProblem>()));
    // A farm this phone doesn't know.
    expect(() => readSheet(code: SheetCode.parse(qr.replaceFirst('farmhaas', 'farmxxxx')), words: const [], ref: _ref()), throwsA(isA<SheetReadProblem>()));
  });

  test('Real photos: day and weekday read as one ("16M"), a line of handwritten 8s is not the header, the right way up scores best', () {
    // Made-up layout like a photographed sheet: the header (day with weekday)
    // at y 400, a line of handwritten hours below with more numbers than days.
    const wd = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final header = [for (var d = 1; d <= 27; d++) OcrBox('$d${wd[(d - 1) % 7]}', 1000 + 85.0 * d, 400, w: 40, h: 80)];
    final eights = [for (var i = 0; i < 40; i++) OcrBox(i.isEven ? '8' : '12', 1000 + 60.0 * i, 900, w: 30, h: 60)];
    final rows = [for (var r = 1; r <= 20; r++) OcrBox('$r', 440, 470 + 85.0 * r, w: 30, h: 45)];
    final words = [...header, ...eights, ...rows, const OcrBox('Surname', 540, 400, w: 120, h: 40)];
    expect(headerDay(const OcrBox('16M', 0, 100, w: 40, h: 80))!.text, '16');
    expect(headerDay(const OcrBox('16M', 0, 100, w: 40, h: 80))!.cy, 80);
    expect(headerDay(const OcrBox('Owen', 0, 0)), isNull);
    final code = SheetCode.parse('NTS3|2026-11|2026-11-01|2026-11-27|farmhaas|-|1/1|${List.generate(20, (i) => 'x$i').join(',')}');
    final read = readSheet(code: code, words: words, ref: _ref());
    expect((read['rows'] as List).length, 20);
    // Upside down: the numbers count down -- scores lower.
    final flipped = [for (final w in words) OcrBox(w.text, 5000 - w.cx, 3000 - w.cy, w: w.w, h: w.h)];
    expect(sheetUprightScore(words), greaterThan(sheetUprightScore(flipped)));
    expect(sheetUprightScore(words), greaterThanOrEqualTo(kUprightNumbers));
  });
}
