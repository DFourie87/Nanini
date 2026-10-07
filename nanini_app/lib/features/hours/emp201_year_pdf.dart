import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../employees/employees_models.dart';
import 'emp201_year.dart';
import 'pay_widgets.dart';
import 'payroll_month.dart';

/// The EMP201 tax-year summary as a PDF, landscape -- the same as the Excel
/// sheet: the months (worked out, submitted, difference), then everyone
/// paid in the tax year, each month's salary, UIF, SDL and PAYE, in the
/// three groups -- March to August first, then September to February and
/// the year.
Future<pw.Document> buildEmp201YearPdf(int taxYear, List<Emp201YearMonth> months, {List<Farm> farms = const []}) async {
  final doc = pw.Document();
  final rust = PdfColor.fromInt(0xFF9A4A24);
  final shade = PdfColor.fromInt(0xFFFBF6EF);
  final groupBg = PdfColor.fromInt(0xFFF3E7D8);
  const font = 5.6;
  String money(double? v) => v == null ? '' : v.toStringAsFixed(2);
  String farm(Employee? e) => farmShort(farms.where((f) => f.id == e?.farmId).firstOrNull);
  final monthName = DateFormat('MMMM yyyy');
  final mon = DateFormat('MMM yy');

  pw.Widget cell(String t, {bool bold = false, bool left = false, PdfColor? color, PdfColor? bg}) => pw.Container(
        color: bg,
        padding: const pw.EdgeInsets.symmetric(horizontal: 1.5, vertical: 1.2),
        alignment: left ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
        child: pw.Text(t, style: pw.TextStyle(fontSize: font, fontWeight: bold ? pw.FontWeight.bold : null, color: color), maxLines: 1),
      );
  pw.TableRow row(List<pw.Widget> cells, {PdfColor? bg}) => pw.TableRow(decoration: bg == null ? null : pw.BoxDecoration(color: bg), children: cells);
  final border = pw.TableBorder.all(color: PdfColors.grey400, width: 0.3);

  // 1. The months.
  final subs = months.where((m) => m.submitted != null).toList();
  double tot(double Function(Emp201YearMonth) f) => months.fold(0.0, (s, m) => s + f(m));
  double sub(double Function(Emp201YearMonth) f) => subs.fold(0.0, (s, m) => s + f(m));
  final monthsTable = pw.Table(
    border: border,
    columnWidths: {0: const pw.FixedColumnWidth(70)},
    children: [
      row([
        for (final h in ['Month', 'Employees', 'Remuneration', 'UIF', 'SDL', 'PAYE', 'Total', 'Submitted UIF', 'Submitted SDL', 'Submitted PAYE', 'Submitted total', 'Difference', 'Submitted on', 'Reference'])
          cell(h, bold: true, left: h == 'Month'),
      ], bg: shade),
      for (final m in months)
        row([
          cell('${monthName.format(DateTime.parse(m.month))}${m.fromHistory ? ' *' : ''}', left: true),
          cell(m.employees == 0 ? '' : '${m.employees}'),
          // A month not paid yet: blank.
          for (final v in [m.salary, m.uif, m.sdl, m.paye]) cell(m.lines.isEmpty ? '' : money(v)),
          cell(m.lines.isEmpty ? '' : money(m.total), bold: true),
          cell(money(m.submitted?.uif)), cell(money(m.submitted?.sdl)), cell(money(m.submitted?.paye)), cell(money(m.submitted?.total)),
          cell(money(m.difference), color: m.difference == null ? null : (m.difference!.abs() < 0.01 ? PdfColors.green800 : PdfColors.red800)),
          cell(m.submitted?.submittedOn ?? ''), cell(m.submitted?.reference ?? ''),
        ]),
      row([
        cell('Total', bold: true, left: true), cell(''),
        cell(money(tot((m) => m.salary)), bold: true), cell(money(tot((m) => m.uif)), bold: true), cell(money(tot((m) => m.sdl)), bold: true),
        cell(money(tot((m) => m.paye)), bold: true), cell(money(tot((m) => m.total)), bold: true),
        for (final f in <double Function(Emp201YearMonth)>[(m) => m.submitted!.uif, (m) => m.submitted!.sdl, (m) => m.submitted!.paye, (m) => m.submitted!.total, (m) => m.difference!])
          cell(subs.isEmpty ? '' : money(sub(f)), bold: true),
        cell(''), cell(''),
      ], bg: shade),
    ],
  );

  // 2. Everyone, half a year per table: 4 figures a month.
  final people = emp201YearByEmployee(months);
  List<pw.Widget> employees(List<Emp201YearMonth> ms, {required bool withYear}) {
    final widths = <int, pw.TableColumnWidth>{0: const pw.FixedColumnWidth(78), 1: const pw.FixedColumnWidth(42), 2: const pw.FixedColumnWidth(54)};
    List<pw.Widget> heads() => [
          cell('Employee', bold: true, left: true), cell('Farm', bold: true, left: true), cell('ID/passport', bold: true, left: true),
          for (final m in ms) ...[cell(mon.format(DateTime.parse(m.month)), bold: true), for (final f in emp201Figures.skip(1)) cell(f, bold: true)],
          if (withYear) ...[cell('Year', bold: true), for (final f in emp201Figures.skip(1)) cell(f, bold: true)],
        ];
    return [
      for (final g in Emp201Group.values) ...[
        pw.SizedBox(height: 6),
        pw.Text('${g.label} (${people[g]!.length})${g == Emp201Group.declared ? '' : ' -- UIF here is what was taken off their pay, not declared'}',
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: rust)),
        pw.SizedBox(height: 2),
        pw.Table(
          border: border,
          columnWidths: widths,
          children: [
            row(heads(), bg: shade),
            for (final y in people[g]!)
              row([
                cell(y.name, left: true), cell(farm(y.employee), left: true), cell(y.employee?.idOrPassport ?? '', left: true),
                for (final m in ms)
                  for (var i = 0; i < 4; i++)
                    cell(money(emp201Figure(y.months[m.month], i)),
                        color: i > 0 && (y.months[m.month]?.withheldNotDeclared ?? false) ? PdfColors.red800 : null),
                if (withYear)
                  for (var i = 0; i < 4; i++) cell(money(y.months.values.fold<double>(0, (s, l) => s + (emp201Figure(l, i) ?? 0))), bold: true),
              ]),
            row([
              cell('Total', bold: true, left: true), cell(''), cell(''),
              for (final m in ms)
                for (var i = 0; i < 4; i++) cell(money(people[g]!.fold<double>(0, (s, y) => s + (emp201Figure(y.months[m.month], i) ?? 0))), bold: true),
              if (withYear)
                for (var i = 0; i < 4; i++)
                  cell(money(people[g]!.fold<double>(0, (s, y) => s + y.months.values.fold<double>(0, (a, l) => a + (emp201Figure(l, i) ?? 0)))), bold: true),
            ], bg: groupBg),
          ],
        ),
      ],
    ];
  }

  pw.Widget title(String sub) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Nanini 121 CC -- EMP201 summary, tax year $taxYear (March ${taxYear - 1} to February $taxYear)',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: rust)),
        pw.Text(sub, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        pw.SizedBox(height: 6),
      ]);

  final theme = pw.PageTheme(pageFormat: PdfPageFormat.a4.landscape, margin: const pw.EdgeInsets.all(18));
  doc.addPage(pw.MultiPage(
    pageTheme: theme,
    build: (_) => [
      title('EMP201 per month: worked out, what was submitted on eFiling, and the difference (submitted less worked out). '
          'Only employees on the EMP201 count; UIF is the employees\' and the employer\'s together. * From the old salary summary.'),
      monthsTable,
    ],
  ));
  doc.addPage(pw.MultiPage(
    pageTheme: theme,
    build: (_) => [
      title('Per employee, March to August ${taxYear - 1}: salary, UIF, SDL, PAYE each month.'),
      ...employees(months.sublist(0, 6), withYear: false),
    ],
  ));
  doc.addPage(pw.MultiPage(
    pageTheme: theme,
    build: (_) => [
      title('Per employee, September ${taxYear - 1} to February $taxYear and the year: salary, UIF, SDL, PAYE each month.'),
      ...employees(months.sublist(6), withYear: true),
    ],
  ));
  return doc;
}
