import 'package:excel/excel.dart';

import '../../core/formatters.dart';
import 'card_models.dart';

/// A card's working paper for a financial year as an .xlsx: the lead
/// schedule (opening, paid in, spent and charged, closing) and every
/// statement, each line with the balance after it.
List<int> cardWorkingPaperXlsx(CardYear y, {required String preparedOn}) {
  final x = Excel.createExcel();
  final sheetName = y.card.label;
  x.rename(x.getDefaultSheet() ?? 'Sheet1', sheetName);
  final sh = x[sheetName];
  final rust = ExcelColor.fromHexString('FF9A4A24');
  final grey = ExcelColor.fromHexString('FF616161');
  final red = ExcelColor.fromHexString('FFC62828');
  final shade = ExcelColor.fromHexString('FFFBF6EF');
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
        numberFormat: money ? const CustomNumericNumFormat(formatCode: '#,##0.00;(#,##0.00);-') : NumFormat.standard_0,
        leftBorder: border ? line : null,
        rightBorder: border ? line : null,
        topBorder: border ? line : null,
        bottomBorder: border ? line : null,
      ),
    );
  }

  CellValue? amount(double? v) => v == null ? null : DoubleCellValue(v);

  void text(String v, {bool bold = false, ExcelColor? color, int? size}) {
    put(0, TextCellValue(v), bold: bold, color: color, size: size);
    row++;
  }

  void lead(String label, double? value, {bool bold = false, ExcelColor? color}) {
    put(0, TextCellValue(label), bold: bold, color: color, fill: bold ? totalShade : null, border: true);
    for (var c = 1; c < 4; c++) {
      put(c, null, fill: bold ? totalShade : null, border: true);
    }
    put(4, amount(value), bold: bold, color: color, fill: bold ? totalShade : null, border: true, money: true);
    row++;
  }

  text('Nanini 121 CC -- ABSA ${y.card.label.toLowerCase()} (Xero: ${y.card.xeroAccount})', bold: true, color: rust, size: 16);
  text('Working paper, year ${DateTime.parse(y.yearStart).year + 1}: ${fmtDateDisplay(y.yearStart)} to ${fmtDateDisplay(y.yearEnd)}', bold: true, size: 12);
  text('Plus: in credit / money into the card. Minus: owed to ABSA / spent or charged.', color: grey);
  text('Prepared from the ABSA statements on ${fmtDateDisplay(preparedOn)}', color: grey);
  row++;

  text('Lead schedule', bold: true, color: rust, size: 12);
  final last = y.months.isEmpty ? null : y.months.last.statement;
  lead('Opening balance ${fmtDateDisplay(y.yearStart)} (${y.openingFrom == 'entered' ? 'financial statements' : y.openingFrom})', y.opening);
  lead('Payments and credits', y.paidIn);
  lead('Spent and charged', y.spent);
  if (y.differences != 0) lead('Not explained by the lines (see the statements)', y.differences, color: red);
  lead('Balance per statement ${last == null ? '' : fmtDateDisplay(last.date)}', y.closing, bold: true);
  final xo = y.xeroOpening;
  if (xo != null) {
    put(0, TextCellValue('Xero opening balance 31/08/2026 (should be)'), color: grey);
    put(4, amount(xo), color: grey, money: true);
    row++;
  }
  row++;

  text('Statements', bold: true, color: rust, size: 12);
  const head = ['Date', 'Description', 'Reference', 'Amount', 'Balance', 'Note'];
  for (var c = 0; c < head.length; c++) {
    put(c, TextCellValue(head[c]), bold: true, fill: totalShade, border: true);
  }
  row++;
  for (final m in y.months) {
    final s = m.statement;
    put(
      0,
      TextCellValue(
        'Statement ${fmtDateDisplay(s.date)}${s.number == null ? '' : ' (no. ${s.number})'}${s.from == null ? '' : ' (${fmtDateDisplay(s.from)} to ${fmtDateDisplay(s.to)})'}',
      ),
      bold: true,
      fill: shade,
    );
    for (var c = 1; c < head.length; c++) {
      put(c, null, fill: shade);
    }
    row++;
    var bal = m.opening;
    put(1, TextCellValue('Balance before'), color: grey, border: true);
    put(4, amount(bal), color: grey, border: true, money: true);
    row++;
    for (final l in m.lines) {
      bal += l.amount;
      put(0, TextCellValue(fmtDateDisplay(l.date)), border: true);
      put(1, TextCellValue(l.description), border: true);
      put(2, TextCellValue(l.reference ?? ''), border: true);
      put(3, amount(l.amount), border: true, money: true);
      put(4, amount((bal * 100).roundToDouble() / 100), border: true, money: true);
      put(5, TextCellValue(l.manual ? 'Added: not on the statement' : ''), color: grey, border: true);
      row++;
    }
    if (m.difference != 0) {
      put(1, TextCellValue('Not explained by the lines'), color: red, border: true);
      put(3, amount(m.difference), color: red, border: true, money: true);
      put(5, TextCellValue('A line left out, or the balance brought forward is not the last closing balance'), color: red, border: true);
      row++;
    }
    put(1, TextCellValue('Balance per statement'), bold: true, border: true);
    put(4, amount(s.closing), bold: true, border: true, money: true);
    row++;
  }
  sh.setColumnWidth(0, 30);
  sh.setColumnWidth(1, 40);
  sh.setColumnWidth(2, 28);
  sh.setColumnWidth(3, 16);
  sh.setColumnWidth(4, 16);
  sh.setColumnWidth(5, 60);
  return x.encode()!;
}
