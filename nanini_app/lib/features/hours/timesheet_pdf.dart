import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/formatters.dart';
import '../employees/employees_models.dart';

/// One printed timesheet: a farm's ordinary work, or a work group paid at
/// its own tariff (e.g. "Potatoes - packhouse") -- its hours on a sheet of
/// their own. Hours only: no tariffs on paper (they're set when the sheet
/// is read back, last month's by default).
class Timesheet {
  Timesheet({required this.title, required this.subtitle, required this.workers, this.groupId});
  final String title;
  final String subtitle;
  final List<Employee> workers;

  /// The work group, for a group's own sheet; null: ordinary work.
  final String? groupId;
}

String _surname(Employee e) => ((e.surname ?? '').trim().isNotEmpty ? e.surname! : e.lastName).trim();

/// The month's timesheets for [farm]: its ordinary work -- the farm's
/// hourly workers (not members, monthly salaries, those not paid here or
/// gone by the 1st) -- then a sheet per work group of the farm with its own
/// tariff, for the group's members (from any farm). Sorted by surname.
List<Timesheet> timesheetsFor(Farm farm, List<Employee> employees, List<EmployeeGroup> groups, DateTime month) {
  final first = toDateStr(DateTime(month.year, month.month, 1));
  bool here(Employee e) => !e.hasLeftBy(first) && e.onPayroll && !e.isMember && (e.monthlySalary ?? 0) <= 0;
  List<Employee> sorted(Iterable<Employee> list) => list.toList()
    ..sort((a, b) {
      final c = _surname(a).toLowerCase().compareTo(_surname(b).toLowerCase());
      return c != 0 ? c : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
    });
  final special = groups.where((g) => g.farmId == farm.id && (g.ratePerHour ?? 0) > 0).toList()..sort((a, b) => a.name.compareTo(b.name));
  return [
    Timesheet(
      title: 'Ordinary work',
      subtitle: special.isEmpty ? 'All hours worked' : 'All hours worked, except in ${special.map((g) => g.name).join(', ')} (on its own sheet)',
      workers: sorted(employees.where((e) => here(e) && e.farmId == farm.id)),
    ),
    for (final g in special)
      Timesheet(
        title: g.name,
        subtitle: 'Only hours worked in this work group',
        workers: sorted(employees.where((e) => here(e) && e.currentGroupId == g.id)),
        groupId: g.id,
      ),
  ];
}

/// Workers on a page, and blank rows for new ones at the end of each sheet.
const kTimesheetRows = 20, kTimesheetBlankRows = 5;

/// What a page's QR code holds -- read back when the filled-in sheet is
/// uploaded: the sheet (month, farm, group or ordinary work), the page, and
/// the workers printed on it in order (the first 8 characters of each id).
String timesheetCode({required DateTime month, required String farmId, String? groupId, required int page, required int pages, required List<Employee> rows}) =>
    ['NTS1', '${month.year}-${month.month.toString().padLeft(2, '0')}', _short(farmId), groupId == null ? '-' : _short(groupId), '$page/$pages', rows.map((e) => _short(e.id)).join(',')].join('|');

String _short(String id) => id.length <= 8 ? id : id.substring(0, 8);

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// The month's blank timesheets for a farm, to print and fill in by hand on
/// the farm each day: per sheet ([timesheetsFor]) a row per worker (with
/// room for new ones), a box per day of the month (Sundays shaded) and a
/// total; a QR code and corner marks on every page
/// so a photo or scan of it can be read back.
Future<pw.Document> buildTimesheetsPdf({required String farmName, required String farmId, required DateTime month, required List<Timesheet> sheets}) async {
  final doc = pw.Document();
  final logo = pw.MemoryImage((await rootBundle.load('assets/images/hub-logo-print.png')).buffer.asUint8List());
  final ink = PdfColor.fromInt(0xFF222222), muted = PdfColor.fromInt(0xFF5A5A5A), shade = PdfColor.fromInt(0xFFD9D9D9);
  final dayCount = DateTime(month.year, month.month + 1, 0).day;
  final days = [for (var d = 1; d <= dayCount; d++) DateTime(month.year, month.month, d)];
  bool off(DateTime d) => d.weekday == DateTime.sunday;
  const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  final monthLabel = '${_months[month.month - 1]} ${month.year}';

  pw.Widget cell(String t, {bool bold = false, bool left = false, double size = 7, PdfColor? bg}) => pw.Container(
        color: bg,
        padding: const pw.EdgeInsets.symmetric(horizontal: 2),
        alignment: left ? pw.Alignment.centerLeft : pw.Alignment.center,
        child: pw.Text(t, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null, color: ink), maxLines: 1),
      );
  // A solid square at each corner of the page's content: where to straighten a photo from.
  pw.Widget mark() => pw.Container(width: 9, height: 9, color: ink);

  for (final sheet in sheets) {
    // The workers in pages of [kTimesheetRows]; the blank rows after the last one.
    final rows = <Employee?>[...sheet.workers, for (var i = 0; i < kTimesheetBlankRows; i++) null];
    final pages = [for (var i = 0; i < rows.length; i += kTimesheetRows) rows.sublist(i, i + kTimesheetRows > rows.length ? rows.length : i + kTimesheetRows)];
    for (final (p, pageRows) in pages.indexed) {
      final code = timesheetCode(
          month: month, farmId: farmId, groupId: sheet.groupId, page: p + 1, pages: pages.length, rows: [for (final e in pageRows) ?e]);
      final first = p * kTimesheetRows;
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
                    pw.Text('TIMESHEET  --  ${farmName.toUpperCase()}  --  ${monthLabel.toUpperCase()}',
                        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: ink)),
                    pw.SizedBox(height: 2),
                    pw.Text('${sheet.title}:  ${sheet.subtitle}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: ink)),
                    pw.SizedBox(height: 2),
                    pw.Text('Write the hours worked each day in its box (e.g. 8 or 9.5); leave it empty when not worked. '
                        'New worker: write the name and ID number on an empty line. At the end of the month: the total per worker.',
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
                    0: const pw.FixedColumnWidth(16),
                    1: const pw.FlexColumnWidth(3.4),
                    2: const pw.FlexColumnWidth(3.2),
                    for (var i = 0; i < dayCount; i++) 3 + i: const pw.FlexColumnWidth(1),
                    3 + dayCount: const pw.FlexColumnWidth(1.7),
                  },
                  children: [
                    pw.TableRow(
                      verticalAlignment: pw.TableCellVerticalAlignment.full,
                      children: [
                        cell('#', bold: true),
                        cell('Surname', bold: true, left: true),
                        cell('Name', bold: true, left: true),
                        for (final d in days)
                          pw.Container(
                            color: off(d) ? shade : null,
                            padding: const pw.EdgeInsets.symmetric(vertical: 2),
                            alignment: pw.Alignment.center,
                            child: pw.Text('${d.day}\n${weekdays[d.weekday - 1]}',
                                textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: ink)),
                          ),
                        cell('Total', bold: true),
                      ],
                    ),
                    for (final (i, e) in pageRows.indexed)
                      pw.TableRow(
                        verticalAlignment: pw.TableCellVerticalAlignment.full,
                        children: [
                          pw.SizedBox(height: 21.5, child: cell('${first + i + 1}', size: 6.5)),
                          cell(e == null ? '' : _surname(e), left: true, size: 8),
                          cell(e == null ? '' : e.firstName.trim(), left: true, size: 8),
                          for (final d in days) pw.Container(color: off(d) ? shade : null),
                          pw.SizedBox(),
                        ],
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(children: [
                pw.Text('Foreman: ______________________   Signature: ______________________   Checked by: ______________________',
                    style: pw.TextStyle(fontSize: 8, color: ink)),
                pw.Spacer(),
                pw.Text('Page ${p + 1} of ${pages.length}  ·  shaded: Sundays', style: pw.TextStyle(fontSize: 7, color: muted)),
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
  }
  return doc;
}
