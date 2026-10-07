import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../employees/employees_models.dart';
import 'emp201_year.dart';
import 'emp201_year_sheet.dart';

/// The EMP201 tax-year summary as a PDF, landscape -- one page (or more)
/// per part of [emp201YearSheet], the same layout as the Excel.
Future<pw.Document> buildEmp201YearPdf(int taxYear, List<Emp201YearMonth> months, {List<Farm> farms = const []}) async {
  final doc = pw.Document();
  final rust = PdfColor.fromInt(0xFF9A4A24);
  final shades = {SheetShade.heading: PdfColor.fromInt(0xFFFBF6EF), SheetShade.total: PdfColor.fromInt(0xFFF3E7D8)};
  final tones = {SheetTone.red: PdfColors.red800, SheetTone.green: PdfColors.green800};
  const font = 5.6;
  pw.Widget cell(SheetCell c) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 1.5, vertical: 1.2),
        alignment: c.left ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
        child: pw.Text(
          c.text ?? _num(c),
          style: pw.TextStyle(fontSize: font, fontWeight: c.bold ? pw.FontWeight.bold : null, color: tones[c.tone]),
          maxLines: 1,
        ),
      );
  final border = pw.TableBorder.all(color: PdfColors.grey400, width: 0.3);
  final theme = pw.PageTheme(pageFormat: PdfPageFormat.a4.landscape, margin: const pw.EdgeInsets.all(18));
  for (final s in emp201YearSheet(taxYear, months, farms: farms)) {
    doc.addPage(pw.MultiPage(
      pageTheme: theme,
      build: (_) => [
        pw.Text(s.title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: rust)),
        pw.Text(s.note, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        pw.SizedBox(height: 6),
        for (final t in s.tables) ...[
          if (t.heading != null) ...[
            pw.SizedBox(height: 6),
            pw.Text(t.heading!, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: rust)),
            pw.SizedBox(height: 2),
          ],
          pw.Table(
            border: border,
            columnWidths: {for (var i = 0; i < t.fixed.length; i++) i: pw.FixedColumnWidth(t.fixed[i])},
            children: [
              for (final r in t.rows)
                pw.TableRow(
                  decoration: shades[r.shade] == null ? null : pw.BoxDecoration(color: shades[r.shade]),
                  children: [for (final c in r.cells) cell(c)],
                ),
            ],
          ),
        ],
      ],
    ));
  }
  return doc;
}

/// Numbers with 2 decimals; a count (Employees) without.
String _num(SheetCell c) {
  final v = c.number;
  if (v == null) return '';
  return c.integer ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
