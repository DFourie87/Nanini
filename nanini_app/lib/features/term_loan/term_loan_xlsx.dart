import 'package:excel/excel.dart';

import '../../core/formatters.dart';
import 'term_loan_models.dart';

/// The term loan working paper for a financial year as an .xlsx: the lead
/// schedule (opening, paid in, drawn, interest and charges, closing) and the
/// statements month by month, each line with the balance after it and the
/// statement's capital and prepaid amount.
List<int> termLoanWorkingPaperXlsx(TermLoanYear y, {required String preparedOn}) {
  final x = Excel.createExcel();
  const sheetName = 'Term loan';
  x.rename(x.getDefaultSheet() ?? 'Sheet1', sheetName);
  final sh = x[sheetName];
  final rust = ExcelColor.fromHexString('FF9A4A24');
  final grey = ExcelColor.fromHexString('FF616161');
  final red = ExcelColor.fromHexString('FFC62828');
  final shade = ExcelColor.fromHexString('FFFBF6EF');
  final totalShade = ExcelColor.fromHexString('FFF3E7D8');
  final line = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('FFBDBDBD'));
  var row = 0;

  void put(
    int col,
    CellValue? v, {
    bool bold = false,
    ExcelColor? color,
    int? size,
    bool right = false,
    ExcelColor? fill,
    bool border = false,
    bool money = false,
  }) {
    sh.updateCell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      v,
      cellStyle: CellStyle(
        bold: bold,
        fontColorHex: color ?? ExcelColor.black,
        fontSize: size,
        horizontalAlign: right || money ? HorizontalAlign.Right : HorizontalAlign.Left,
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

  final yearName = 'Year ${DateTime.parse(y.yearStart).year + 1}: ${fmtDateDisplay(y.yearStart)} to ${fmtDateDisplay(y.yearEnd)}';
  text('Nanini 121 CC -- ABSA term loan $kTermLoanAccount', bold: true, color: rust, size: 16);
  text('Working paper, $yearName', bold: true, size: 12);
  text('Balance: the prepaid amount (Arrear/Advance) less the outstanding capital, as on each statement. Plus: more paid in than owed.', color: grey);
  text('Prepared from the ABSA statements on ${fmtDateDisplay(preparedOn)}', color: grey);
  row++;

  // Lead schedule.
  text('Lead schedule', bold: true, color: rust, size: 12);
  final last = y.months.isEmpty ? null : y.months.last.statement;
  for (final (label, value, bold) in [
    ('Opening balance ${fmtDateDisplay(y.yearStart)}${y.openingEntered ? ' (financial statements)' : ' (last statement before the year)'}', y.opening, false),
    ('Paid into the loan', y.paidIn, false),
    ('Drawn from the loan', y.drawn, false),
    ('Interest and charges (net of interest on the prepaid amount)', y.interest, false),
    ('Balance per statement ${last == null ? '' : fmtDateDisplay(last.date)}', y.closing, true),
  ]) {
    put(0, TextCellValue(label), bold: bold, fill: bold ? totalShade : null, border: true);
    for (var c = 1; c < 5; c++) {
      put(c, null, fill: bold ? totalShade : null, border: true);
    }
    put(5, amount(value), bold: bold, fill: bold ? totalShade : null, border: true, money: true);
    row++;
  }
  if (last != null) {
    for (final (label, value) in [
      ('Outstanding capital ${fmtDateDisplay(last.date)}', -last.capital),
      ('Prepaid (Arrear/Advance) ${fmtDateDisplay(last.date)}', last.advance),
      if (last.amountPayable != null) ('Next instalment ${fmtDateDisplay(last.payableDate)} (from the prepaid amount)', last.amountPayable),
    ]) {
      put(0, TextCellValue(label), color: grey, border: true);
      for (var c = 1; c < 5; c++) {
        put(c, null, border: true);
      }
      put(5, amount(value), color: grey, border: true, money: true);
      row++;
    }
  }
  final xo = y.xeroOpening;
  if (xo != null) {
    put(0, TextCellValue('Xero $kTermLoanXeroAccount opening balance 31/08/2026 (should be)'), color: grey);
    put(5, amount(xo), color: grey, money: true);
    row++;
  }
  row++;

  // Statements.
  text('Statements', bold: true, color: rust, size: 12);
  final head = ['Date', 'Description', 'Paid in / (drawn)', 'Interest and charges', 'Shown only', 'Balance', 'Capital', 'Prepaid', 'Note'];
  for (var c = 0; c < head.length; c++) {
    put(c, TextCellValue(head[c]), bold: true, fill: totalShade, border: true, right: c >= 2 && c <= 7);
  }
  row++;
  put(0, TextCellValue(fmtDateDisplay(y.yearStart)), border: true);
  put(1, TextCellValue('Opening balance'), bold: true, border: true);
  for (var c = 2; c < 9; c++) {
    put(c, c == 5 ? amount(y.opening) : null, bold: c == 5, border: true, money: c == 5);
  }
  row++;
  for (final m in y.months) {
    final s = m.statement;
    var bal = m.opening;
    put(
      0,
      TextCellValue('Statement ${fmtDateDisplay(s.date)}${s.from == null ? '' : ' (${fmtDateDisplay(s.from)} to ${fmtDateDisplay(s.to)})'}'),
      bold: true,
      fill: shade,
    );
    for (var c = 1; c < 9; c++) {
      put(c, null, fill: shade);
    }
    row++;
    final all = [...m.money, ...m.info]..sort((a, b) => a.date.compareTo(b.date));
    for (final l in all) {
      final counts = m.money.contains(l);
      if (counts) bal += l.amount;
      put(0, TextCellValue(fmtDateDisplay(l.date)), border: true);
      put(1, TextCellValue(l.description), border: true);
      put(2, counts ? amount(l.amount) : null, border: true, money: true);
      put(3, null, border: true);
      put(4, counts ? null : amount(l.amount), color: grey, border: true, money: true);
      put(5, counts ? amount((bal * 100).roundToDouble() / 100) : null, border: true, money: true);
      put(6, null, border: true);
      put(7, null, border: true);
      put(8, TextCellValue(l.manual ? 'Added: not on the statement' : (counts ? '' : 'In the interest below')), color: grey, border: true);
      row++;
    }
    put(0, TextCellValue(fmtDateDisplay(s.date)), border: true);
    put(1, TextCellValue('Interest and charges (net), the rest of the change'), border: true);
    put(2, null, border: true);
    put(3, amount(m.interest), border: true, money: true, color: m.looksShort ? red : null);
    put(4, null, border: true);
    put(5, amount(s.balance), bold: true, border: true, money: true);
    put(6, amount(-s.capital), color: grey, border: true, money: true);
    put(7, amount(s.advance), color: grey, border: true, money: true);
    put(
      8,
      TextCellValue(m.looksShort ? 'More than a month\'s interest: a payment or drawing left off the statement?' : 'Balance per statement'),
      color: m.looksShort ? red : grey,
      border: true,
    );
    row++;
  }
  put(1, TextCellValue('Totals and closing balance'), bold: true, fill: totalShade, border: true);
  put(0, null, fill: totalShade, border: true);
  put(2, amount(y.paidIn + y.drawn), bold: true, fill: totalShade, border: true, money: true);
  put(3, amount(y.interest), bold: true, fill: totalShade, border: true, money: true);
  put(4, null, fill: totalShade, border: true);
  put(5, amount(y.closing), bold: true, fill: totalShade, border: true, money: true);
  for (var c = 6; c < 9; c++) {
    put(c, null, fill: totalShade, border: true);
  }

  // The statements' interest, as in the working papers (Termyn lening).
  if (y.months.any((m) => m.statement.interestPortion != null)) {
    row += 2;
    text('Interest per statement', bold: true, color: rust, size: 12);
    const ih = ['Statement', 'Interest portion', 'Benefit on interest', 'Interest on statement (net)'];
    for (var c = 0; c < ih.length; c++) {
      put(c, TextCellValue(ih[c]), bold: true, fill: totalShade, border: true, right: c > 0);
    }
    row++;
    for (final m in y.months) {
      final s = m.statement;
      put(0, TextCellValue(fmtDateDisplay(s.date)), border: true);
      put(1, amount(s.interestPortion), border: true, money: true);
      put(2, amount(s.interestBenefit), border: true, money: true);
      put(3, amount(s.interestNet), border: true, money: true);
      row++;
    }
    put(0, TextCellValue('Total'), bold: true, fill: totalShade, border: true);
    put(1, amount(y.interestPortion), bold: true, fill: totalShade, border: true, money: true);
    put(2, amount(y.interestBenefit), bold: true, fill: totalShade, border: true, money: true);
    put(3, amount(y.interestNet), bold: true, fill: totalShade, border: true, money: true);
    row++;
  }

  sh.setColumnWidth(0, 30);
  sh.setColumnWidth(1, 44);
  for (var c = 2; c < 8; c++) {
    sh.setColumnWidth(c, 17);
  }
  sh.setColumnWidth(8, 60);
  return x.encode()!;
}
