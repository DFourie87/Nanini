import 'package:excel/excel.dart';

import '../../core/formatters.dart';
import 'pallet_stock.dart';

/// The pallet reconciliation with an agent as an .xlsx to send to them: a
/// heading, a summary (returned, collected, paid for, still at the agent)
/// and every movement with the balance after it.
List<int> palletReconciliationXlsx(PalletReconciliation r, {required String preparedOn}) {
  final x = Excel.createExcel();
  final sheetName = 'Pallet reconciliation';
  x.rename(x.getDefaultSheet() ?? 'Sheet1', sheetName);
  final sh = x[sheetName];
  final rust = ExcelColor.fromHexString('FF9A4A24');
  final grey = ExcelColor.fromHexString('FF616161');
  final shade = ExcelColor.fromHexString('FFFBF6EF');
  final totalShade = ExcelColor.fromHexString('FFF3E7D8');
  final line = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('FFBDBDBD'));
  final period = '${r.from == null ? 'the first movement' : fmtDateDisplay(r.from)} to ${fmtDateDisplay(r.to)}';
  // Pallets collected that Nanini paid for: their own column, only when there are any.
  final bought = r.paidByNanini != 0;
  final cols = bought ? 8 : 7;
  var row = 0;

  void put(int col, CellValue? v, {bool bold = false, ExcelColor? color, int? size, bool right = false, ExcelColor? fill, bool border = false}) {
    sh.updateCell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      v,
      cellStyle: CellStyle(
        bold: bold,
        fontColorHex: color ?? ExcelColor.black,
        fontSize: size,
        horizontalAlign: right ? HorizontalAlign.Right : HorizontalAlign.Left,
        backgroundColorHex: fill ?? ExcelColor.none,
        leftBorder: border ? line : null,
        rightBorder: border ? line : null,
        topBorder: border ? line : null,
        bottomBorder: border ? line : null,
      ),
    );
  }

  void text(String v, {bool bold = false, ExcelColor? color, int? size}) {
    put(0, TextCellValue(v), bold: bold, color: color, size: size);
    row++;
  }

  // Heading.
  text('Pallet movement reconciliation', bold: true, color: rust, size: 16);
  text('between Nanini Boerdery and ${r.agent}', bold: true, size: 12);
  text('Period: $period');
  text('Prepared by Nanini Boerdery (Nanini 121 CC) on ${fmtDateDisplay(preparedOn)}', color: grey);
  row++;

  // Summary.
  text('Summary', bold: true, color: rust, size: 12);
  for (final (label, value, bold) in [
    ('Pallets sent to ${r.agent} with produce (delivery notes)', r.returned, false),
    ('Less: empty pallets collected from ${r.agent}', r.collected, false),
    if (bought) ('Less: pallets paid for by Nanini', r.paidByNanini, false),
    ('Less: pallets paid for by ${r.agent} (pallet invoices)', r.paidFor, false),
    ('Balance: pallets still at ${r.agent}', r.balance, true),
  ]) {
    put(0, TextCellValue(label), bold: bold, fill: bold ? totalShade : null, border: true);
    for (var c = 1; c < cols - 1; c++) {
      put(c, null, fill: bold ? totalShade : null, border: true);
    }
    put(cols - 1, IntCellValue(value), bold: bold, right: true, fill: bold ? totalShade : null, border: true);
    row++;
  }
  row++;

  // Movements.
  text('Movements', bold: true, color: rust, size: 12);
  final head = ['Date', 'Reference', 'Description', 'Collected', if (bought) 'Paid for by Nanini', 'Returned', 'Paid for by agent', 'Balance at agent'];
  for (var c = 0; c < head.length; c++) {
    put(c, TextCellValue(head[c]), bold: true, right: c >= 3, fill: shade, border: true);
  }
  row++;
  if (r.lines.isEmpty) {
    put(0, TextCellValue('No pallet movements in this period.'), color: grey);
    row++;
  }
  CellValue? n(int v) => v == 0 ? null : IntCellValue(v);
  for (final l in r.lines) {
    final nums = [n(l.collected), if (bought) n(l.paidByNanini), n(l.returned), n(l.paidFor), IntCellValue(l.balance)];
    put(0, TextCellValue(fmtDateDisplay(l.date)), border: true);
    put(1, TextCellValue(l.reference), border: true);
    put(2, TextCellValue(l.description), border: true);
    for (var i = 0; i < nums.length; i++) {
      put(3 + i, nums[i], right: true, border: true);
    }
    row++;
  }
  final totals = [r.collected, if (bought) r.paidByNanini, r.returned, r.paidFor, r.balance];
  put(0, TextCellValue('Total'), bold: true, fill: totalShade, border: true);
  put(1, null, fill: totalShade, border: true);
  put(2, null, fill: totalShade, border: true);
  for (var i = 0; i < totals.length; i++) {
    put(3 + i, IntCellValue(totals[i]), bold: true, right: true, fill: totalShade, border: true);
  }
  row += 2;

  text('Collected: empty pallets collected from the agent (a minus: returned to the agent empty).'
      '${bought ? ' Paid for by Nanini: pallets Nanini paid the agent for.' : ''}'
      ' Returned: pallets sent to the agent with produce on our delivery notes. Paid for by agent: pallets the agent paid for instead of returning them.',
      color: grey);
  text('Balance at agent = returned - collected${bought ? ' - paid for by Nanini' : ''} - paid for by agent.'
      '${r.from == null ? '' : ' Movements before ${fmtDateDisplay(r.from)} are not included.'}',
      color: grey);
  text('Please confirm the balance, or let us know of any difference.', bold: true);

  sh.setColumnWidth(0, 14);
  sh.setColumnWidth(1, 18);
  sh.setColumnWidth(2, 52);
  for (var c = 3; c < cols; c++) {
    sh.setColumnWidth(c, 15);
  }
  return x.encode()!;
}
