import '../../core/supabase_client.dart';
import '../hours/hours_repository.dart';
import 'capture_models.dart';

/// A timesheet page as read from its photo on the phone
/// (capture_app/timesheet_reader.dart, in the entry's payload 'read'):
/// the sheet from its QR code, and per row the hours written in each day's box.
class TimesheetRead {
  TimesheetRead({
    required this.farmId,
    required this.farmName,
    required this.month,
    required this.days,
    required this.rows,
    this.groupId,
    this.groupName,
    this.page,
    this.notes,
  });

  final String farmId;
  final String farmName;

  /// 'YYYY-MM': the month the sheet is named for.
  final String month;

  /// The sheet's days, in column order ('YYYY-MM-DD').
  final List<String> days;
  final List<TimesheetRow> rows;

  /// A work group's own sheet (its hours at the group's rate); null = all workers.
  final String? groupId;
  final String? groupName;

  /// e.g. '1/2'.
  final String? page;

  /// Anything the reader wasn't sure of.
  final String? notes;

  static TimesheetRead? fromPayload(Map<String, dynamic> p) {
    final r = p['read'];
    if (r is! Map) return null;
    return TimesheetRead(
      farmId: r['farm_id'] as String,
      farmName: r['farm_name'] as String? ?? '',
      month: r['month'] as String? ?? '',
      days: ((r['days'] as List?) ?? const []).cast<String>(),
      rows: [for (final row in ((r['rows'] as List?) ?? const []).cast<Map>()) TimesheetRow.fromJson(row.cast<String, dynamic>())],
      groupId: r['group_id'] as String?,
      groupName: r['group_name'] as String?,
      page: r['page'] as String?,
      notes: r['notes'] as String?,
    );
  }
}

class TimesheetRow {
  TimesheetRow(
      {required this.row, required this.cells, this.employeeId, this.idPrefix, this.name = '', this.writtenName = '', this.idNumber = '', this.total = ''});

  /// The row number printed on the sheet.
  final int row;

  /// A printed worker (from the QR code); null for a line written in by hand.
  final String? employeeId;

  /// A printed worker the phone didn't know: the start of their id (QR code).
  final String? idPrefix;

  /// As printed: surname and name.
  final String name;

  /// A new worker's name and ID/passport as written on an empty line.
  final String writtenName;
  final String idNumber;

  /// What was written in each day's box, in column order ('' = empty, '?' = can't read).
  final List<String> cells;

  /// The total written at the end of the row.
  final String total;

  factory TimesheetRow.fromJson(Map<String, dynamic> j) => TimesheetRow(
        row: (j['row'] as num).toInt(),
        employeeId: j['employee_id'] as String?,
        idPrefix: j['id_prefix'] as String?,
        name: j['name'] as String? ?? '',
        writtenName: j['written_name'] as String? ?? '',
        idNumber: j['id_number'] as String? ?? '',
        cells: ((j['hours'] as List?) ?? const []).map((v) => '${v ?? ''}').toList(),
        total: '${j['total'] ?? ''}',
      );
}

/// A day's box as hours: null when empty, NaN when it can't be read as a
/// number (e.g. '?', 'A'). A comma counts as the decimal point.
double? timesheetHours(String cell) {
  final t = cell.trim().replaceAll(',', '.');
  if (t.isEmpty || t == '-' || t == '0') return t == '0' ? 0 : null;
  final v = double.tryParse(t);
  return v == null || v < 0 || v > 24 ? double.nan : v;
}

/// Why a day's hours can't go in from the sheet.
enum TimesheetBlock {
  /// Already on a payslip: paid days are never changed.
  paid,

  /// Already clocked at another farm that day: one farm a day.
  otherFarm,
}

/// What's already there for the sheet's workers and days: the last day each
/// is paid up to, and their hours that day at other farms.
class TimesheetContext {
  TimesheetContext({required this.paidUpTo, required this.otherFarmHours});

  /// Employee id -> last 'work up to' date on a payslip.
  final Map<String, String> paidUpTo;

  /// (employee id, date) -> farm name and hours at another farm.
  final Map<(String, String), String> otherFarmHours;

  TimesheetBlock? blockFor(String employeeId, String date) {
    final paid = paidUpTo[employeeId];
    if (paid != null && date.compareTo(paid) <= 0) return TimesheetBlock.paid;
    if (otherFarmHours.containsKey((employeeId, date))) return TimesheetBlock.otherFarm;
    return null;
  }
}

/// Builds [TimesheetContext] from the sheet's workers' payslips and hours rows.
TimesheetContext timesheetContextFrom({
  required String farmId,
  required List<Map<String, dynamic>> payslips,
  required List<Map<String, dynamic>> hours,
  required Map<String, String> farmNames,
}) {
  final paid = <String, String>{};
  for (final p in payslips) {
    final id = p['employee_id'] as String, end = p['period_end'] as String;
    if (paid[id] == null || end.compareTo(paid[id]!) > 0) paid[id] = end;
  }
  final elsewhere = <(String, String), double>{};
  final where = <(String, String), String>{};
  for (final h in hours) {
    final farm = h['farm_id'] as String?;
    if (farm == null || farm == farmId) continue;
    final key = (h['employee_id'] as String, h['entry_date'] as String);
    elsewhere[key] = (elsewhere[key] ?? 0) + (h['hours'] as num).toDouble();
    where[key] = farmNames[farm] ?? 'another farm';
  }
  String n(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
  return TimesheetContext(
    paidUpTo: paid,
    otherFarmHours: {for (final e in elsewhere.entries) if (e.value > 0.001) e.key: '${where[e.key]} ${n(e.value)} h'},
  );
}

/// Loads [TimesheetContext] for [employeeIds] over [days].
Future<TimesheetContext> loadTimesheetContext(String farmId, List<String> employeeIds, List<String> days) async {
  if (employeeIds.isEmpty || days.isEmpty) return TimesheetContext(paidUpTo: {}, otherFarmHours: {});
  final payslips = ((await sb.from('payslips').select('employee_id, period_end').inFilter('employee_id', employeeIds)) as List).cast<Map<String, dynamic>>();
  final hours = ((await sb
          .from('hours_entries')
          .select('employee_id, entry_date, hours, farm_id')
          .inFilter('employee_id', employeeIds)
          .gte('entry_date', days.first)
          .lte('entry_date', days.last)) as List)
      .cast<Map<String, dynamic>>();
  final farms = ((await sb.from('farms').select('id, name')) as List).cast<Map<String, dynamic>>();
  return timesheetContextFrom(
    farmId: farmId,
    payslips: payslips,
    hours: hours,
    farmNames: {for (final f in farms) f['id'] as String: f['name'] as String},
  );
}

/// A timesheet page as checked in the hub: the hours to put in.
class TimesheetApproval {
  TimesheetApproval({required this.farmId, required this.lines, this.groupName});
  final String farmId;

  /// The work group's sheet: its hours go in as the group's (its rate).
  final String? groupName;
  final List<({String employeeId, String date, double hours})> lines;
}

/// Approving a checked timesheet page: each worker's hours at the sheet's
/// farm on each day are replaced by the sheet's (the sheet is the record for
/// that farm). Paid days and days clocked at another farm are left alone.
Future<void> applyTimesheetCapture(CaptureEntry entry, TimesheetApproval a) async {
  final ids = {for (final l in a.lines) l.employeeId}.toList();
  final days = {for (final l in a.lines) l.date}.toList()..sort();
  final ctx = await loadTimesheetContext(a.farmId, ids, days);
  final lines = [for (final l in a.lines) if (ctx.blockFor(l.employeeId, l.date) == null) l];
  if (lines.isEmpty) return;
  final rates = {
    for (final e in ((await sb.from('employees').select('id, rate_per_hour').inFilter('id', ids)) as List).cast<Map<String, dynamic>>())
      e['id'] as String: ((e['rate_per_hour'] as num?) ?? 0).toDouble(),
  };
  final repo = HoursRepository();
  final settings = await repo.fetchSettings();
  // This farm's hours for those days are replaced by the sheet's.
  for (final l in lines) {
    await sb.from('hours_entries').delete().eq('employee_id', l.employeeId).eq('entry_date', l.date).eq('farm_id', a.farmId);
  }
  final worked = [for (final l in lines) if (l.hours > 0) l];
  if (a.groupName != null) {
    for (final day in {for (final l in worked) l.date}) {
      await repo.logGroup(
        members: [for (final l in worked) if (l.date == day) (employeeId: l.employeeId, hours: l.hours, rate: rates[l.employeeId] ?? 0)],
        date: day,
        settings: settings,
        groupName: a.groupName!,
        farmId: a.farmId,
      );
    }
  } else {
    for (final l in worked) {
      await repo.logIndividual(employeeId: l.employeeId, date: l.date, hours: l.hours, rate: rates[l.employeeId] ?? 0, settings: settings, farmId: a.farmId);
    }
  }
}

/// The hub's lines for a timesheet entry in the Captured list.
List<String> timesheetDetailLines(CaptureEntry e) {
  final p = e.payload;
  final read = TimesheetRead.fromPayload(p);
  if (read == null) {
    final error = p['read_error'] as String?;
    return [
      'Photo of a timesheet page',
      error != null ? 'Could not read it: $error' : 'Not read on the phone -- reject it and send the page again',
    ];
  }
  final people = read.rows.where((r) => r.cells.any((c) => c.trim().isNotEmpty)).length;
  return [
    'Timesheet ${read.farmName}${read.groupName == null ? '' : ' · ${read.groupName}'} · ${read.month} · page ${read.page ?? '?'}',
    'Read: $people workers with hours, ${read.days.length} days -- check it before approving',
    if ((read.notes ?? '').isNotEmpty) 'Reader: ${read.notes}',
  ];
}
