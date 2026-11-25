import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters.dart';
import 'tuckshop_models.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "25 Nov 2026 07:15" -- when the list was printed.
String stockTakeStamp(DateTime at) =>
    '${at.day} ${_months[at.month - 1]} ${at.year} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// A tuck shop's stock take list, to print and count: each item with its
/// selling price and the stock the app has for it at [at] -- the moment it's
/// printed (never another day: what the app shows now) -- and empty boxes
/// for the actual stock counted and the difference. Items by name.
Future<pw.Document> buildStockTakePdf({required String farmName, required List<TuckshopItem> items, required DateTime at}) async {
  final doc = pw.Document();
  final logo = pw.MemoryImage((await rootBundle.load('assets/images/hub-logo-print.png')).buffer.asUint8List());
  const ink = PdfColors.black;
  final muted = PdfColor.fromInt(0xFF6B6B6B);
  final shade = PdfColor.fromInt(0xFFF3E7D8);
  final sorted = [...items]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  String qty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  pw.Widget cell(String t, {bool bold = false, bool right = false, PdfColor? bg}) => pw.Container(
        color: bg,
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(t, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : null, color: ink)),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    header: (ctx) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Image(logo, height: 40),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('STOCK TAKE  --  ${farmName.toUpperCase()} TUCK SHOP',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: ink)),
            pw.SizedBox(height: 3),
            pw.Text('Stock as per the app at ${stockTakeStamp(at)} (when this list was printed)',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: ink)),
            pw.SizedBox(height: 2),
            pw.Text('Count each item and write it under Actual stock; Difference = Actual stock - Stock as per app (minus: short).',
                style: pw.TextStyle(fontSize: 8, color: muted)),
          ]),
        ),
      ]),
    ),
    footer: (ctx) => pw.Column(children: [
      if (ctx.pageNumber == ctx.pagesCount) ...[
        pw.SizedBox(height: 24),
        pw.Row(children: [
          pw.Text('Counted by: ______________________   Signature: ______________________   Checked by: ______________________',
              style: pw.TextStyle(fontSize: 9, color: ink)),
        ]),
        pw.SizedBox(height: 8),
      ],
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}  ·  printed ${stockTakeStamp(at)}', style: pw.TextStyle(fontSize: 7, color: muted)),
      ),
    ]),
    build: (ctx) => [
      pw.Table(
        border: pw.TableBorder.all(color: ink, width: 0.6),
        columnWidths: const {
          0: pw.FlexColumnWidth(4),
          1: pw.FlexColumnWidth(1.6),
          2: pw.FlexColumnWidth(1.6),
          3: pw.FlexColumnWidth(1.6),
          4: pw.FlexColumnWidth(1.6),
        },
        children: [
          pw.TableRow(
            repeat: true,
            decoration: pw.BoxDecoration(color: shade),
            children: [
              cell('Item', bold: true),
              cell('Selling price', bold: true, right: true),
              cell('Stock as per app', bold: true, right: true),
              cell('Actual stock', bold: true, right: true),
              cell('Difference', bold: true, right: true),
            ],
          ),
          for (final i in sorted)
            pw.TableRow(children: [
              cell(i.name),
              cell(fmtR(i.sellPrice), right: true),
              cell(qty(i.totalStock), right: true),
              cell(''),
              cell(''),
            ]),
        ],
      ),
    ],
  ));
  return doc;
}
