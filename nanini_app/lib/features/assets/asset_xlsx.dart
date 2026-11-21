import 'package:excel/excel.dart';

import '../../core/formatters.dart';
import 'asset_models.dart';

/// The asset register for a financial year as an .xlsx, laid out as the
/// working papers: by group, each asset's cost (start, bought, sold, end),
/// accumulated depreciation (start, the year's, on sales, end) and book
/// values, with group totals, the grand total and the totals per account.
List<int> assetRegisterXlsx(String yearStart, List<AssetYearLine> lines, {required String preparedOn}) {
  final x = Excel.createExcel();
  const sheetName = 'Asset register';
  x.rename(x.getDefaultSheet() ?? 'Sheet1', sheetName);
  final sh = x[sheetName];
  final rust = ExcelColor.fromHexString('FF9A4A24');
  final grey = ExcelColor.fromHexString('FF616161');
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

  CellValue amount(double v) => DoubleCellValue(v);

  void text(String v, {bool bold = false, ExcelColor? color, int? size}) {
    put(0, TextCellValue(v), bold: bold, color: color, size: size);
    row++;
  }

  final year = DateTime.parse(yearStart).year + 1;
  text('Nanini 121 CC -- asset register', bold: true, color: rust, size: 16);
  text('Year $year: ${fmtDateDisplay(yearStart)} to ${fmtDateDisplay(toDateStr(DateTime(year, 3, 0)))}', bold: true, size: 12);
  text(
    'Depreciation: straight line on cost, by the month from the month bought (or as set by hand, marked *). Prepared on ${fmtDateDisplay(preparedOn)}.',
    color: grey,
  );
  row++;

  const head = [
    'No.',
    'Description',
    'Date',
    'Cost start',
    'Bought',
    'Sold',
    'Cost end',
    'Acc. dep. start',
    'Depreciation',
    'Dep. on sales',
    'Acc. dep. end',
    'Book value start',
    'Book value end',
    'Rate %',
  ];
  List<double> sums(Iterable<AssetYearLine> ls) => [
    for (final f in <double Function(AssetYearLine)>[
      (l) => l.costStart,
      (l) => l.bought,
      (l) => l.sold,
      (l) => l.costEnd,
      (l) => l.accumStart,
      (l) => l.depreciation,
      (l) => l.accumSold,
      (l) => l.accumEnd,
      (l) => l.bookStart,
      (l) => l.bookEnd,
    ])
      ls.fold(0.0, (s, l) => s + f(l)),
  ];

  void totalRow(String label, List<double> v, {ExcelColor? fill}) {
    put(0, null, fill: fill, border: true);
    put(1, TextCellValue(label), bold: true, fill: fill, border: true);
    put(2, null, fill: fill, border: true);
    for (var i = 0; i < v.length; i++) {
      put(3 + i, amount((v[i] * 100).roundToDouble() / 100), bold: true, fill: fill, border: true, money: true);
    }
    put(13, null, fill: fill, border: true);
    row++;
  }

  for (final c in AssetCategory.values) {
    final ls = [
      for (final l in lines)
        if (l.asset.category == c) l,
    ];
    if (ls.isEmpty) continue;
    put(0, TextCellValue(c.letter), bold: true, color: rust);
    put(1, TextCellValue('${c.label.toUpperCase()} -- ${c.costAccount}${c.depAccount == null ? '' : ' / ${c.depAccount}'}'), bold: true, color: rust);
    row++;
    for (var i = 0; i < head.length; i++) {
      put(i, TextCellValue(head[i]), bold: true, fill: totalShade, border: true);
    }
    row++;
    for (final l in ls) {
      final a = l.asset;
      put(0, a.number == null ? null : IntCellValue(a.number!), border: true);
      put(1, TextCellValue('${a.description}${a.disposedDate == null ? '' : ' (sold ${fmtDateDisplay(a.disposedDate)})'}'), border: true);
      put(2, TextCellValue(a.purchaseDate == null ? '' : fmtDateDisplay(a.purchaseDate)), border: true);
      final v = [l.costStart, l.bought, l.sold, l.costEnd, l.accumStart, l.depreciation, l.accumSold, l.accumEnd, l.bookStart, l.bookEnd];
      for (var i = 0; i < v.length; i++) {
        put(3 + i, amount(v[i]), border: true, money: true);
      }
      put(13, TextCellValue('${a.rate == a.rate.roundToDouble() ? a.rate.toInt() : a.rate}${l.overridden ? ' *' : ''}'), border: true);
      row++;
    }
    totalRow('Total', sums(ls), fill: shade);
    row++;
  }
  totalRow('TOTAL', sums(lines), fill: totalShade);
  row++;

  // Per account, to agree to the trial balance.
  text('Per account', bold: true, color: rust, size: 12);
  final cost = <String, double>{};
  final acc = <String, double>{};
  for (final l in lines) {
    cost[l.asset.category.costAccount] = (cost[l.asset.category.costAccount] ?? 0) + l.costEnd;
    final d = l.asset.category.depAccount;
    if (d != null) acc[d] = (acc[d] ?? 0) + l.accumEnd;
  }
  for (final (label, value) in [
    for (final e in cost.entries) ('${e.key} cost', e.value),
    for (final e in acc.entries) ('${e.key} accumulated depreciation', -e.value),
    ('$kDepreciationAccount depreciation for the year', lines.fold(0.0, (s, l) => s + l.depreciation)),
  ]) {
    put(1, TextCellValue(label), border: true);
    put(3, amount((value * 100).roundToDouble() / 100), border: true, money: true);
    row++;
  }

  sh.setColumnWidth(0, 6);
  sh.setColumnWidth(1, 46);
  sh.setColumnWidth(2, 12);
  for (var c = 3; c < 13; c++) {
    sh.setColumnWidth(c, 15);
  }
  sh.setColumnWidth(13, 8);
  return x.encode()!;
}
