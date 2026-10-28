import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import '../suppliers/suppliers_capture_approval.dart' show capturedPhoto;
import 'capture_models.dart';
import 'timesheet_capture.dart';

/// Checking a timesheet page read from its photo: the photo beside a grid
/// like the paper's, each box editable. Grey: already paid (stays as it is).
/// Red: clocked at another farm that day (left out). Amber: couldn't be read
/// as a number -- fix or clear it. Pops a [TimesheetApproval] on Approve.
class TimesheetApprovalPage extends StatefulWidget {
  const TimesheetApprovalPage({super.key, required this.entry});
  final CaptureEntry entry;
  @override
  State<TimesheetApprovalPage> createState() => _TimesheetApprovalPageState();
}

class _TimesheetApprovalPageState extends State<TimesheetApprovalPage> {
  TimesheetRead? read;
  Uint8List? photo;
  List<Employee> employees = [];
  TimesheetContext ctx = TimesheetContext(paidUpTo: {}, otherFarmHours: {});
  final rowEmployee = <int, String?>{};
  final cells = <(int, int), TextEditingController>{};
  String? problem;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in cells.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = TimesheetRead.fromPayload(widget.entry.payload);
      if (r == null) {
        setState(() {
          problem = widget.entry.payload['read_error'] as String? ?? 'Not read yet: the office PC reads the photos a few times a day.';
          loading = false;
        });
        return;
      }
      final results = await Future.wait([
        capturedPhoto(widget.entry.id),
        EmployeesRepository().watchEmployees().first,
      ]);
      read = r;
      photo = results[0] as Uint8List?;
      employees = (results[1] as List<Employee>)..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      for (final (i, row) in r.rows.indexed) {
        rowEmployee[i] = row.employeeId;
        for (var d = 0; d < r.days.length; d++) {
          cells[(i, d)] = TextEditingController(text: d < row.cells.length ? row.cells[d].trim() : '')..addListener(() => setState(() {}));
        }
      }
      await _loadContext();
    } catch (e) {
      problem = 'Could not load the timesheet: $e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadContext() async {
    final r = read!;
    final ids = [for (final id in rowEmployee.values) ?id];
    final c = await loadTimesheetContext(r.farmId, ids, r.days);
    if (mounted) setState(() => ctx = c);
  }

  double _rowTotal(int i) {
    var t = 0.0;
    for (var d = 0; d < read!.days.length; d++) {
      final v = timesheetHours(cells[(i, d)]!.text);
      if (v != null && !v.isNaN) t += v;
    }
    return t;
  }

  void _approve() {
    final r = read!;
    final lines = <({String employeeId, String date, double hours})>[];
    final unreadable = <String>[];
    final seen = <String>{};
    for (final (i, row) in r.rows.indexed) {
      final id = rowEmployee[i];
      if (id == null) continue;
      if (!seen.add(id)) {
        showProblem(context, '${_nameOf(id)} is on two lines -- pick the right worker for each line.');
        return;
      }
      for (var d = 0; d < r.days.length; d++) {
        final v = timesheetHours(cells[(i, d)]!.text);
        if (v == null || ctx.blockFor(id, r.days[d]) != null) continue;
        if (v.isNaN) {
          unreadable.add('${row.row}: ${fmtDateDisplay(r.days[d])}');
          continue;
        }
        lines.add((employeeId: id, date: r.days[d], hours: v));
      }
    }
    if (unreadable.isNotEmpty) {
      showProblem(context, 'Fix or clear the boxes in amber (line: day):\n${unreadable.take(12).join('\n')}');
      return;
    }
    if (lines.isEmpty) {
      showProblem(context, 'No hours to put in.');
      return;
    }
    Navigator.pop(context, TimesheetApproval(farmId: r.farmId, groupName: r.groupName, lines: lines));
  }

  static String _hours(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

  String _nameOf(String id) => employees.where((e) => e.id == id).firstOrNull?.displayName ?? 'A worker';

  @override
  Widget build(BuildContext context) {
    final r = read;
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Check timesheet'),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : r == null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(problem ?? 'Not read yet.', textAlign: TextAlign.center)))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text('${r.farmName}${r.groupName == null ? '' : ' · ${r.groupName}'} · ${fmtDateDisplay(r.days.first)} to ${fmtDateDisplay(r.days.last)} · page ${r.page ?? '?'}',
                        style: Theme.of(context).textTheme.titleMedium),
                    if ((r.notes ?? '').isNotEmpty) Text('Reader: ${r.notes}', style: const TextStyle(color: NaniniColors.muted)),
                    const SizedBox(height: 6),
                    const Text('Check each line against the photo and correct any box. Grey: already paid (left as it is). '
                        'Red: clocked at another farm that day (left out). Amber: not a number -- fix or clear it. '
                        'Approving replaces these workers\' hours at this farm on these days.'),
                    const SizedBox(height: 8),
                    if (photo != null)
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => Scaffold(
                                  appBar: const NaniniAppBar(title: 'Timesheet photo'),
                                  body: InteractiveViewer(maxScale: 8, child: Center(child: Image.memory(photo!))),
                                ))),
                        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(photo!, height: 220, fit: BoxFit.contain)),
                      ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(scrollDirection: Axis.horizontal, child: _grid(r)),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(onPressed: _approve, icon: const Icon(Icons.check), label: const Text('Approve these hours')),
                    ),
                  ],
                ),
    );
  }

  Widget _grid(TimesheetRead r) {
    const nameW = 220.0, dayW = 44.0, totalW = 60.0;
    Widget head(String t, double w) => SizedBox(width: w, child: Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          head('Worker', nameW),
          for (final d in r.days) head('${DateTime.parse(d).day}\n${const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][DateTime.parse(d).weekday - 1]}', dayW),
          head('Total', totalW),
          head('Sheet', totalW),
        ]),
        for (final (i, row) in r.rows.indexed) _row(r, i, row, nameW: nameW, dayW: dayW, totalW: totalW),
      ],
    );
  }

  Widget _row(TimesheetRead r, int i, TimesheetRow row, {required double nameW, required double dayW, required double totalW}) {
    final id = rowEmployee[i];
    final total = _rowTotal(i);
    final sheetTotal = timesheetHours(row.total);
    final totalOff = sheetTotal != null && !sheetTotal.isNaN && (sheetTotal - total).abs() > 0.01;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        SizedBox(
          width: nameW,
          child: row.employeeId != null
              ? Text('${row.row}. ${row.name}', overflow: TextOverflow.ellipsis)
              // A worker written in by hand: pick who it is.
              : DropdownButton<String?>(
                  isExpanded: true,
                  isDense: true,
                  value: id,
                  hint: Text('${row.row}. ${row.writtenName.isEmpty ? 'New worker' : row.writtenName}${row.idNumber.isEmpty ? '' : ' (${row.idNumber})'} -- pick',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(color: NaniniColors.amber)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Not on the list (leave out)')),
                    for (final e in employees) DropdownMenuItem<String?>(value: e.id, child: Text(e.displayName, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) async {
                    setState(() => rowEmployee[i] = v);
                    await _loadContext();
                  },
                ),
        ),
        for (var d = 0; d < r.days.length; d++) _cell(i, d, id, r.days[d], dayW),
        SizedBox(width: totalW, child: Text(_hours(total), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
        SizedBox(
          width: totalW,
          child: Text(row.total, textAlign: TextAlign.center, style: TextStyle(color: totalOff ? NaniniColors.red : NaniniColors.muted, fontWeight: totalOff ? FontWeight.w700 : null)),
        ),
      ]),
    );
  }

  Widget _cell(int i, int d, String? id, String date, double w) {
    final c = cells[(i, d)]!;
    final block = id == null ? null : ctx.blockFor(id, date);
    final v = timesheetHours(c.text);
    final color = switch (block) {
      TimesheetBlock.paid => NaniniColors.disabledBg,
      TimesheetBlock.otherFarm => NaniniColors.red.withValues(alpha: 0.18),
      null => v != null && v.isNaN ? NaniniColors.amber.withValues(alpha: 0.35) : null,
    };
    final field = SizedBox(
      width: w,
      height: 34,
      child: Container(
        margin: const EdgeInsets.all(1),
        color: color,
        child: TextField(
          controller: c,
          enabled: block != TimesheetBlock.paid,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8), border: InputBorder.none, filled: false),
        ),
      ),
    );
    if (block == TimesheetBlock.otherFarm && id != null) return Tooltip(message: 'Already at ${ctx.otherFarmHours[(id, date)]} -- left out', child: field);
    if (block == TimesheetBlock.paid) return Tooltip(message: 'Already paid -- left as it is', child: field);
    return field;
  }
}
