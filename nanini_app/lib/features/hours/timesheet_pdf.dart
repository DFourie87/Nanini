import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/formatters.dart';
import '../employees/employees_models.dart';
import 'hours_models.dart';

/// One printed timesheet: all a farm's workers, or a work group's (e.g.
/// "Potatoes - packhouse" at harvest time). Hours only: no tariffs on paper
/// (they're set when the sheet is read back, last month's by default).
class Timesheet {
  Timesheet({required this.title, required this.subtitle, required this.workers, this.groupId});
  final String title;
  final String subtitle;
  final List<Employee> workers;

  /// The work group, for a group's own sheet; null: ordinary work.
  final String? groupId;
}

String _surname(Employee e) => ((e.surname ?? '').trim().isNotEmpty ? e.surname! : e.lastName).trim();

/// The month's timesheets for [farm]: one list of the hourly workers who
/// work there -- in one of its work groups (wherever they're paid: someone
/// paid at Haaskraal who packs potatoes at Limpopodraai), or in none and of
/// the farm -- not members, monthly salaries, those not paid here or
/// gone by the 1st, nor seasonal pickers (paid only per kg in the 3 months
/// before, from [hours] and [kg]). [byGroup] (e.g. Limpopodraai's potato
/// harvest): a sheet per work group of the farm instead, and one for its
/// workers in none of them. Sorted by surname.
List<Timesheet> timesheetsFor(Farm farm, List<Employee> employees, List<EmployeeGroup> groups, DateTime month,
    {bool byGroup = false, List<HoursEntry> hours = const [], List<KgEntry> kg = const []}) {
  final first = toDateStr(DateTime(month.year, month.month, 1));
  final since = toDateStr(DateTime(month.year, month.month - 3, 1));
  bool recent(String d) => d.compareTo(since) >= 0 && d.compareTo(first) < 0;
  final withHours = {for (final h in hours) if (recent(h.date)) h.employeeId};
  final pickers = {for (final k in kg) if (recent(k.date) && !withHours.contains(k.employeeId)) k.employeeId};
  bool here(Employee e) => !e.hasLeftBy(first) && e.onPayroll && !e.isMember && (e.monthlySalary ?? 0) <= 0 && !pickers.contains(e.id);
  List<Employee> sorted(Iterable<Employee> list) => list.toList()
    ..sort((a, b) {
      final c = _surname(a).toLowerCase().compareTo(_surname(b).toLowerCase());
      return c != 0 ? c : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
    });
  // Where a worker works: their work group's farm, else their own.
  final groupFarm = {for (final g in groups) g.id: g.farmId};
  String? worksAt(Employee e) => groupFarm[e.currentGroupId] ?? e.farmId;
  final farmWorkers = employees.where((e) => here(e) && worksAt(e) == farm.id);
  final farmGroups = groups.where((g) => g.farmId == farm.id).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  if (!byGroup || farmGroups.isEmpty) return [Timesheet(title: 'All workers', subtitle: 'All hours worked', workers: sorted(farmWorkers))];
  final ids = {for (final g in farmGroups) g.id};
  final rest = sorted(farmWorkers.where((e) => !ids.contains(e.currentGroupId)));
  return [
    for (final g in farmGroups)
      if (sorted(employees.where((e) => here(e) && e.currentGroupId == g.id)) case final members when members.isNotEmpty)
        Timesheet(title: g.name, subtitle: 'Only hours worked in this work group', workers: members, groupId: g.id),
    if (rest.isNotEmpty) Timesheet(title: 'Not in a work group', subtitle: 'Hours of the workers in none of the groups', workers: rest),
  ];
}

/// Workers on a page, and blank rows for new ones at the end of each sheet.
const kTimesheetRows = 20, kTimesheetBlankRows = 20;

/// The days a month's timesheet covers: from the day after the farm's
/// previous payroll run (the latest of [paidUpTo] -- the farm's payslips'
/// "work up to" dates -- before the sheet ends) up to the month's last
/// Friday. Never from before the previous month's last Friday, so a payroll
/// not run yet doesn't stretch the sheet over two months.
List<DateTime> timesheetDays(DateTime month, {Iterable<String> paidUpTo = const []}) {
  DateTime lastFriday(int year, int month) {
    var d = DateTime(year, month + 1, 0);
    while (d.weekday != DateTime.friday) {
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return d;
  }

  final end = lastFriday(month.year, month.month);
  final prev = lastFriday(month.year, month.month - 1);
  var start = DateTime(prev.year, prev.month, prev.day + 1);
  final endStr = toDateStr(end);
  final paid = paidUpTo.where((d) => d.compareTo(endStr) < 0).fold<String?>(null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a);
  if (paid != null) {
    final p = DateTime.parse(paid);
    final after = DateTime(p.year, p.month, p.day + 1);
    if (after.isAfter(start)) start = after;
  }
  return [for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) d];
}

/// What a page's QR code holds -- read back when the filled-in sheet is
/// photographed (scripts/read_timesheets.py): the sheet (month, its first
/// and last day, farm, group or ordinary work), the page, and the workers
/// printed on it, in order (ids shortened to 8 characters).
String timesheetCode(
        {required DateTime month,
        required List<DateTime> days,
        required String farmId,
        String? groupId,
        required int page,
        required int pages,
        required List<Employee> rows}) =>
    [
      'NTS2',
      '${month.year}-${month.month.toString().padLeft(2, '0')}',
      toDateStr(days.first),
      toDateStr(days.last),
      _short(farmId),
      groupId == null ? '-' : _short(groupId),
      '$page/$pages',
      rows.map((e) => _short(e.id)).join(','),
    ].join('|');

String _short(String id) => id.length <= 8 ? id : id.substring(0, 8);

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// The month's blank timesheets for a farm, to print and fill in by hand on
/// the farm each day: per sheet ([timesheetsFor]) a row per worker (with
/// room for new ones), a box per day of the month (Sundays shaded) and a
/// total; a QR code and corner marks on every page
/// so a photo or scan of it can be read back.
Future<pw.Document> buildTimesheetsPdf(
    {required String farmName, required String farmId, required DateTime month, required List<Timesheet> sheets, List<DateTime>? days}) async {
  final doc = pw.Document();
  final logo = pw.MemoryImage((await rootBundle.load('assets/images/hub-logo-print.png')).buffer.asUint8List());
  final ink = PdfColor.fromInt(0xFF222222), muted = PdfColor.fromInt(0xFF5A5A5A), shade = PdfColor.fromInt(0xFFD9D9D9);
  // From the day after the previous payroll to the month's last Friday.
  final sheetDays = days ?? timesheetDays(month);
  final dayCount = sheetDays.length;
  String dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1].substring(0, 3)}';
  final rangeLabel = '${dayMonth(sheetDays.first)} to ${dayMonth(sheetDays.last)} ${sheetDays.last.year}';
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
          month: month, days: sheetDays, farmId: farmId, groupId: sheet.groupId, page: p + 1, pages: pages.length, rows: [for (final e in pageRows) ?e]);
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
                    // Which sheet, when the farm has more than one (a work group's own).
                    if (sheets.length > 1) ...[
                      pw.SizedBox(height: 2),
                      pw.Text('${sheet.title}:  ${sheet.subtitle}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: ink)),
                    ],
                    pw.SizedBox(height: 2),
                    pw.Text('Days: $rangeLabel', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: ink)),
                    pw.SizedBox(height: 2),
                    pw.Text('Write the hours worked each day in its box (e.g. 8 or 9.5); leave it empty when not worked. '
                        'New or temporary worker: write the surname, name and ID or passport number on an empty line. On the last day: the total per worker.',
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
                    3: const pw.FlexColumnWidth(3.6),
                    for (var i = 0; i < dayCount; i++) 4 + i: const pw.FlexColumnWidth(1),
                    4 + dayCount: const pw.FlexColumnWidth(1.7),
                  },
                  children: [
                    pw.TableRow(
                      verticalAlignment: pw.TableCellVerticalAlignment.full,
                      children: [
                        cell('#', bold: true),
                        cell('Surname', bold: true, left: true),
                        cell('Name', bold: true, left: true),
                        cell('ID / Passport', bold: true, left: true),
                        for (final d in sheetDays)
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
                          // Written in for a new (temporary) worker; known workers are on the QR code.
                          pw.SizedBox(),
                          for (final d in sheetDays) pw.Container(color: off(d) ? shade : null),
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
