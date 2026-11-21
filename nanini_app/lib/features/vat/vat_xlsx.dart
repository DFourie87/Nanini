import 'package:excel/excel.dart';

import '../../core/formatters.dart';
import 'vat_models.dart';

/// The VAT control for a financial year as an .xlsx, as the working papers'
/// BTW sheet: per two-month period the supplies, output VAT, input VAT,
/// diesel refund and net VAT beside the VAT201, the declared sales agreed to
/// the financial statements, and the sales by crop and source.
List<int> vatControlXlsx(VatYear y, {required String preparedOn}) {
  final x = Excel.createExcel();
  const sheetName = 'VAT control';
  x.rename(x.getDefaultSheet() ?? 'Sheet1', sheetName);
  final sh = x[sheetName];
  final rust = ExcelColor.fromHexString('FF9A4A24');
  final grey = ExcelColor.fromHexString('FF616161');
  final red = ExcelColor.fromHexString('FFC62828');
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
        textWrapping: TextWrapping.WrapText,
      ),
    );
  }

  CellValue? amount(double? v) => v == null ? null : DoubleCellValue(v);

  void text(String v, {bool bold = false, ExcelColor? color, int? size}) {
    put(0, TextCellValue(v), bold: bold, color: color, size: size);
    row++;
  }

  final year = DateTime.parse(y.yearStart).year + 1;
  text('Nanini 121 CC -- VAT control', bold: true, color: rust, size: 16);
  text('Year $year: ${fmtDateDisplay(y.yearStart)} to ${fmtDateDisplay(toDateStr(DateTime(year, 3, 0)))}', bold: true, size: 12);
  text(
    'Supplies and input VAT from the hub (account sales, supplier invoices), with what was entered by hand; output VAT = (standard + capital) x 15/115.',
    color: grey,
  );
  text('Prepared on ${fmtDateDisplay(preparedOn)}', color: grey);
  row++;

  const head = [
    'Period',
    'Standard rate supplies (incl. VAT)',
    'Standard rate capital supplies',
    'Zero rated / exempt supplies',
    'Total output VAT',
    'Input VAT capital',
    'Input VAT standard',
    'Total input VAT',
    'Diesel refund',
    'Net VAT payable / (refundable)',
    'Per VAT201',
    'Difference',
  ];
  for (var c = 0; c < head.length; c++) {
    put(c, TextCellValue(head[c]), bold: true, fill: totalShade, border: true);
  }
  row++;
  for (final p in y.periods) {
    final v = [
      p.standard,
      p.capitalSupplies,
      p.zeroRated,
      p.outputVat,
      p.inputCapital,
      p.inputStandard,
      p.inputVat,
      p.dieselRefund,
      p.net,
      p.vat201Net,
      p.difference,
    ];
    put(0, TextCellValue(p.label), border: true);
    for (var i = 0; i < v.length; i++) {
      put(1 + i, amount(v[i]), border: true, money: true, color: i == 10 && (p.difference ?? 0).abs() > 0.5 ? red : null);
    }
    row++;
  }
  final t = [y.standard, y.capitalSupplies, y.zeroRated, y.outputVat, y.inputCapital, y.inputStandard, y.inputVat, y.dieselRefund, y.net];
  put(0, TextCellValue('TOTAL'), bold: true, fill: totalShade, border: true);
  for (var i = 0; i < t.length; i++) {
    put(1 + i, amount(t[i]), bold: true, fill: totalShade, border: true, money: true);
  }
  put(10, null, fill: totalShade, border: true);
  put(11, null, fill: totalShade, border: true);
  row += 2;

  text('Sales per the VAT returns and the financial statements', bold: true, color: rust, size: 12);
  for (final (label, value, colour) in [
    ('Total sales (excluding VAT) per the VAT returns', y.salesExcl, null),
    ('Total sales per the financial statements', y.fsSales, null),
    ('Difference', y.salesDifference, (y.salesDifference ?? 0).abs() > 0.5 ? red : null),
  ]) {
    put(0, TextCellValue(label), border: true, color: colour);
    put(3, amount(value), border: true, money: true, color: colour);
    row++;
  }
  row++;

  text('Sales', bold: true, color: rust, size: 12);
  put(0, TextCellValue(''), bold: true, fill: totalShade, border: true);
  put(1, TextCellValue('Zero rated'), bold: true, fill: totalShade, border: true);
  put(2, TextCellValue('Standard (incl. VAT)'), bold: true, fill: totalShade, border: true);
  row++;
  final zero = y.zeroByCrop;
  final std = y.standardBySource;
  final otherZero = y.periods.fold(0.0, (s, p) => s + p.manual.otherZero);
  for (final e in zero.entries) {
    put(0, TextCellValue(e.key.toUpperCase()), border: true);
    put(1, amount(e.value), border: true, money: true);
    put(2, null, border: true);
    row++;
  }
  if (otherZero != 0) {
    put(0, TextCellValue('OTHER ZERO RATED (ENTERED)'), border: true);
    put(1, amount(otherZero), border: true, money: true);
    put(2, null, border: true);
    row++;
  }
  for (final e in std.entries) {
    put(0, TextCellValue(e.key.toUpperCase()), border: true);
    put(1, null, border: true);
    put(2, amount(e.value), border: true, money: true);
    row++;
  }
  put(0, TextCellValue('Total'), bold: true, fill: totalShade, border: true);
  put(1, amount(y.zeroRated), bold: true, fill: totalShade, border: true, money: true);
  put(2, amount(y.standard), bold: true, fill: totalShade, border: true, money: true);
  row++;

  sh.setColumnWidth(0, 44);
  for (var c = 1; c < head.length; c++) {
    sh.setColumnWidth(c, 16);
  }
  return x.encode()!;
}
