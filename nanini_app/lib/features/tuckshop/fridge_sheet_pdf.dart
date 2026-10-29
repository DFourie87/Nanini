import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/formatters.dart';
import '../employees/employees_models.dart';

/// Lines per page, and empty lines at the end for new or temporary workers.
const kFridgeRows = 20, kFridgeBlankRows = 20;

/// A fridge sheet page's QR code -- read back when the sheet is photographed:
/// NFS2|month|first day|last day|farm|items|page/pages|workers (ids shortened
/// to 8 characters; the items in the columns' order).
String fridgeSheetCode({
  required DateTime month,
  required List<DateTime> days,
  required String farmId,
  required List<String> itemIds,
  required int page,
  required int pages,
  required List<Employee> rows,
}) =>
    [
      'NFS2',
      '${month.year}-${month.month.toString().padLeft(2, '0')}',
      toDateStr(days.first),
      toDateStr(days.last),
      _short(farmId),
      itemIds.map(_short).join(','),
      '$page/$pages',
      rows.map((e) => _short(e.id)).join(','),
    ].join('|');

String _short(String id) => id.length <= 8 ? id : id.substring(0, 8);
String _surname(Employee e) => ((e.surname ?? '').trim().isNotEmpty ? e.surname! : e.lastName).trim();
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// Limpopodraai's tuck shop fridge sheet (wors and chicken pieces), to print:
/// one line per worker, and per item a wide box where the worker makes a mark
/// for every one taken (when doesn't matter), with a box for the count. The
/// sheet runs from the day after the last payroll ([days].first); on pay day
/// it's photographed and read on a phone, and what's taken comes off that
/// pay. 20 empty lines for new names; a QR code and corner marks on every page.
Future<pw.Document> buildFridgeSheetPdf({
  required String farmName,
  required String farmId,
  required DateTime month,
  required List<DateTime> days,
  required List<Employee> workers,
  required List<({String id, String name})> items,
}) async {
  final doc = pw.Document();
  final logo = pw.MemoryImage((await rootBundle.load('assets/images/hub-logo-print.png')).buffer.asUint8List());
  final ink = PdfColor.fromInt(0xFF222222), muted = PdfColor.fromInt(0xFF5A5A5A);
  String dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1].substring(0, 3)}';
  final from = '${dayMonth(days.first)} ${days.first.year}';
  final monthLabel = '${_months[month.month - 1]} ${month.year}';
  final names = items.map((i) => i.name).join(' and ');

  pw.Widget cell(String t, {bool bold = false, bool left = false, double size = 8}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3),
        alignment: left ? pw.Alignment.centerLeft : pw.Alignment.center,
        child: pw.Text(t, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null, color: ink), maxLines: 1),
      );
  pw.Widget mark() => pw.Container(width: 9, height: 9, color: ink);

  final rows = <Employee?>[...workers, for (var i = 0; i < kFridgeBlankRows; i++) null];
  final pages = [for (var i = 0; i < rows.length; i += kFridgeRows) rows.sublist(i, i + kFridgeRows > rows.length ? rows.length : i + kFridgeRows)];
  for (final (p, pageRows) in pages.indexed) {
    final code = fridgeSheetCode(
        month: month, days: days, farmId: farmId, itemIds: [for (final i in items) i.id], page: p + 1, pages: pages.length, rows: [for (final e in pageRows) ?e]);
    final first = p * kFridgeRows;
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(16),
      build: (ctx) => pw.Stack(children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(14),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Image(logo, height: 40),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('FRIDGE SHEET  --  ${farmName.toUpperCase()}  --  ${monthLabel.toUpperCase()}',
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: ink)),
                  pw.SizedBox(height: 2),
                  pw.Text('${names.toUpperCase()}  ·  from $from (the day after the last pay)', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: ink)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                      'Make a mark ( | ) in your line, in its column, for every one taken. '
                      'New or temporary worker: write your surname and name on an empty line. On pay day, before the pay is done: count the marks into the '
                      'box beside them, photograph each page with the phone (FRIDGE SHEET) and start a new sheet.',
                      style: pw.TextStyle(fontSize: 7, color: muted)),
                ]),
              ),
              pw.SizedBox(width: 8),
              pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: code, width: 52, height: 52, color: ink),
            ]),
            pw.SizedBox(height: 6),
            pw.Expanded(
              child: pw.Table(
                border: pw.TableBorder.all(color: ink, width: 0.6),
                columnWidths: {
                  0: const pw.FixedColumnWidth(18),
                  1: const pw.FlexColumnWidth(3.4),
                  2: const pw.FlexColumnWidth(3.2),
                  for (var i = 0; i < items.length; i++) ...{
                    3 + 2 * i: pw.FlexColumnWidth(items.length == 1 ? 18 : 8.5),
                    4 + 2 * i: const pw.FlexColumnWidth(1.4),
                  },
                },
                children: [
                  pw.TableRow(
                    verticalAlignment: pw.TableCellVerticalAlignment.middle,
                    children: [
                      pw.SizedBox(height: 18, child: cell('#', bold: true)),
                      cell('Surname', bold: true, left: true),
                      cell('Name', bold: true, left: true),
                      for (final i in items) ...[
                        cell('${i.name.toUpperCase()}  --  a mark for each one', bold: true, size: 9),
                        cell('Total', bold: true),
                      ],
                    ],
                  ),
                  for (final (i, e) in pageRows.indexed)
                    pw.TableRow(
                      verticalAlignment: pw.TableCellVerticalAlignment.middle,
                      children: [
                        pw.SizedBox(height: 22, child: cell('${first + i + 1}')),
                        cell(e == null ? '' : _surname(e), left: true),
                        cell(e == null ? '' : e.firstName.trim(), left: true),
                        for (final _ in items) ...[pw.SizedBox(), pw.SizedBox()],
                      ],
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Row(children: [
              pw.Text('Tuck shop: ______________________   Signature: ______________________   Checked by: ______________________',
                  style: pw.TextStyle(fontSize: 8, color: ink)),
              pw.Spacer(),
              pw.Text('Page ${p + 1} of ${pages.length}', style: pw.TextStyle(fontSize: 7, color: muted)),
            ]),
          ]),
        ),
        pw.Positioned(left: 0, top: 0, child: mark()),
        pw.Positioned(right: 0, top: 0, child: mark()),
        pw.Positioned(left: 0, bottom: 0, child: mark()),
        pw.Positioned(right: 0, bottom: 0, child: mark()),
      ]),
    ));
  }
  return doc;
}
