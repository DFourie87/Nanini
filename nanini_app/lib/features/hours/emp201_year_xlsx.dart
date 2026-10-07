import 'package:excel/excel.dart';
import '../employees/employees_models.dart';
import 'emp201_year.dart';
import 'emp201_year_sheet.dart';

/// [months] of [taxYear] as an .xlsx file: one sheet, laid out as the
/// preview ([emp201YearSheet]) -- the same parts one under the other.
List<int> emp201YearXlsx(int taxYear, List<Emp201YearMonth> months, {List<Farm> farms = const []}) {
  final x = Excel.createExcel();
  final name = 'EMP201 $taxYear';
  x.rename(x.getDefaultSheet() ?? 'Sheet1', name);
  final sh = x[name];
  final rust = ExcelColor.fromHexString('FF9A4A24');
  final grey = ExcelColor.fromHexString('FF616161');
  final line = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('FFBDBDBD'));
  final fills = {SheetShade.heading: ExcelColor.fromHexString('FFFBF6EF'), SheetShade.total: ExcelColor.fromHexString('FFF3E7D8')};
  final tones = {SheetTone.red: ExcelColor.fromHexString('FFC62828'), SheetTone.green: ExcelColor.fromHexString('FF2E7D32')};
  var row = 0;
  var widest = 0;
  void text(String v, {bool bold = false, ExcelColor? color, int? size}) {
    sh.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row), TextCellValue(v),
        cellStyle: CellStyle(bold: bold, fontColorHex: color ?? ExcelColor.black, fontSize: size));
    row++;
  }

  for (final s in emp201YearSheet(taxYear, months, farms: farms)) {
    text(s.title, bold: true, color: rust, size: 13);
    text(s.note, color: grey);
    for (final t in s.tables) {
      row++;
      if (t.heading != null) text(t.heading!, bold: true, color: rust);
      for (final r in t.rows) {
        for (var c = 0; c < r.cells.length; c++) {
          final cell = r.cells[c];
          final style = CellStyle(
            bold: cell.bold,
            fontColorHex: tones[cell.tone] ?? ExcelColor.black,
            backgroundColorHex: fills[r.shade] ?? ExcelColor.none,
            horizontalAlign: cell.left ? HorizontalAlign.Left : HorizontalAlign.Right,
            leftBorder: line,
            rightBorder: line,
            topBorder: line,
            bottomBorder: line,
            numberFormat: cell.number == null ? NumFormat.standard_0 : (cell.integer ? NumFormat.standard_1 : NumFormat.standard_2),
          );
          final CellValue? v = cell.text != null
              ? TextCellValue(cell.text!)
              : cell.number == null
                  ? null
                  : (cell.integer ? IntCellValue(cell.number!.round()) : DoubleCellValue(cell.number!));
          sh.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row), v, cellStyle: style);
        }
        if (r.cells.length > widest) widest = r.cells.length;
        row++;
      }
    }
    row += 2;
  }
  sh.setColumnWidth(0, 26);
  sh.setColumnWidth(1, 14);
  sh.setColumnWidth(2, 16);
  for (var c = 3; c < widest; c++) {
    sh.setColumnWidth(c, 11);
  }
  return x.encode()!;
}
