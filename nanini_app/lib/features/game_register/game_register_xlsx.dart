import 'package:excel/excel.dart';

import '../../core/formatters.dart';
import 'game_register_models.dart';

/// The game register as an .xlsx, as the working papers' Wild sheet: per
/// farm each species, head, value per head and total; the total and the
/// fair value movement (billike waarde) on last year.
List<int> gameRegisterXlsx(GameYear y, {required String preparedOn}) {
  final x = Excel.createExcel();
  const sheetName = 'Game register';
  x.rename(x.getDefaultSheet() ?? 'Sheet1', sheetName);
  final sh = x[sheetName];
  final rust = ExcelColor.fromHexString('FF9A4A24');
  final grey = ExcelColor.fromHexString('FF616161');
  final totalShade = ExcelColor.fromHexString('FFF3E7D8');
  final line = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('FFBDBDBD'));
  var row = 0;

  void put(int col, CellValue? v, {bool bold = false, ExcelColor? color, int? size, ExcelColor? fill, bool border = false, bool money = false}) {
    sh.updateCell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      v,
      cellStyle: CellStyle(
        bold: bold,
        fontColorHex: color ?? ExcelColor.black,
        fontSize: size,
        horizontalAlign: money ? HorizontalAlign.Right : HorizontalAlign.Left,
        backgroundColorHex: fill ?? ExcelColor.none,
        numberFormat: money ? const CustomNumericNumFormat(formatCode: '#,##0;(#,##0);-') : NumFormat.standard_0,
        leftBorder: border ? line : null,
        rightBorder: border ? line : null,
        topBorder: border ? line : null,
        bottomBorder: border ? line : null,
      ),
    );
  }

  final year = DateTime.parse(y.yearStart).year + 1;
  put(0, TextCellValue('Nanini 121 CC -- game register $year'), bold: true, color: rust, size: 16);
  row++;
  put(0, TextCellValue('Game counted at 28 February $year, at its value per head. Prepared on ${fmtDateDisplay(preparedOn)}.'), color: grey);
  row += 2;
  for (final f in y.farms) {
    put(0, TextCellValue(f.toUpperCase()), bold: true, color: rust);
    row++;
    for (final (i, h) in ['Species', 'Head', 'Value per head', 'Total', 'Last year (head)'].indexed) {
      put(i, TextCellValue(h), bold: true, fill: totalShade, border: true);
    }
    row++;
    for (final r in y.of(f)) {
      put(0, TextCellValue(r.species), border: true);
      put(1, IntCellValue(r.head), border: true);
      put(2, DoubleCellValue(r.value), border: true, money: true);
      put(3, DoubleCellValue(r.total), border: true, money: true);
      final last = y.lastHead(f, r.species);
      put(4, last == null ? null : IntCellValue(last), border: true, color: grey);
      row++;
    }
    put(0, TextCellValue('Total'), bold: true, fill: totalShade, border: true);
    put(1, IntCellValue(y.farmHead(f)), bold: true, fill: totalShade, border: true);
    put(2, null, fill: totalShade, border: true);
    put(3, DoubleCellValue(y.farmTotal(f)), bold: true, fill: totalShade, border: true, money: true);
    put(4, null, fill: totalShade, border: true);
    row += 2;
  }
  for (final (label, value, bold) in [
    ('Total', y.total, true),
    if (y.fairValueMovement != null) ('Last year', y.lastTotal, false),
    if (y.fairValueMovement != null) ('Fair value movement (billike waarde)', y.fairValueMovement!, true),
  ]) {
    put(2, TextCellValue(label), bold: bold);
    put(3, DoubleCellValue(value), bold: bold, money: true);
    row++;
  }
  sh.setColumnWidth(0, 28);
  sh.setColumnWidth(1, 10);
  sh.setColumnWidth(2, 16);
  sh.setColumnWidth(3, 16);
  sh.setColumnWidth(4, 16);
  return x.encode()!;
}
