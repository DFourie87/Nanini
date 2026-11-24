import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/photo_orientation.dart';
import 'package:nanini_app/capture_app/timesheet_reader.dart';

// A JPEG's start and end only (the picture itself doesn't matter here).
final bare = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, 0xFF, 0xDA, 0x00, 0x02, 0xFF, 0xD9]);

void main() {
  test('a photo turned by its orientation note: added when it has none, changed when it has one', () {
    expect(jpegOrientation(bare), isNull);
    final quarter = jpegTurned(bare, 90)!;
    expect(jpegOrientation(quarter), 6);
    expect(quarter.length, bare.length + 36);
    // Already turned (a phone's portrait photo, 6): a further quarter is upside down, three quarters upright.
    expect(jpegOrientation(jpegTurned(quarter, 90)!), 3);
    expect(jpegOrientation(jpegTurned(quarter, 270)!), 1);
    expect(jpegOrientation(jpegTurned(quarter, 180)!), 8);
    expect(jpegTurned(quarter, 90)!.length, quarter.length); // changed in place
    expect(jpegTurned(Uint8List.fromList([1, 2, 3, 4]), 90), isNull); // not a JPEG
  });

  test('a half written as a small 1 over a 2 is .5; 12 side by side stays 12', () {
    // 8, then a 1 above a 2 (with the line between) to its right.
    final eightHalf = [const OcrBox('8', 10, 20, w: 8, h: 16), const OcrBox('1', 22, 12, w: 4, h: 7), const OcrBox('-', 22, 20, w: 6, h: 1), const OcrBox('2', 22, 27, w: 5, h: 7)];
    expect(sheetCellRaw(eightHalf), '8.5');
    expect(sheetCellText(sheetCellRaw(eightHalf)), '8.5');
    expect(sheetCellText(sheetCellRaw([const OcrBox('1', 22, 12, w: 4, h: 7), const OcrBox('2', 22, 27, w: 5, h: 7)])), '0.5');
    expect(sheetCellRaw([const OcrBox('1', 10, 20, w: 6, h: 14), const OcrBox('2', 18, 20, w: 7, h: 14)]), '12');
    expect(sheetCellRaw([const OcrBox('9', 10, 20, w: 8, h: 14)]), '9');
    expect(sheetCellText('8½'), '8.5');
  });

  test('right way up: the printed numbers counted', () {
    expect(sheetNumbersIn([const OcrBox('12', 0, 0), const OcrBox('Surname', 0, 0), const OcrBox('7', 0, 0), const OcrBox('2026', 0, 0)]), 2);
  });
}
