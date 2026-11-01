import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../features/employees/employees_models.dart' show employeeDetailsProblem;
import '../../features/capture/fridge_sheet_capture.dart';
import '../../features/capture/timesheet_capture.dart';
import '../../theme/nanini_theme.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../ref_data.dart';

/// The photo, small; tapped: full screen to zoom in.
class _Photo extends StatelessWidget {
  const _Photo(this.photo);
  final Uint8List photo;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Photo')),
            body: InteractiveViewer(maxScale: 8, child: Center(child: Image.memory(photo))),
          ),
        )),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(photo, height: 200, fit: BoxFit.contain)),
        ),
      );
}

/// "Not on the list (leave out)" in [_PickWorker]: their line is left out.
const _leaveOut = '-';

/// A worker written in by hand: pick who it is (or leave them out); not yet
/// picked (null): the amber prompt.
class _PickWorker extends StatelessWidget {
  const _PickWorker({required this.label, required this.people, required this.value, required this.onChanged});
  final String label;
  final List<RefPerson> people;
  final String? value;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButton<String?>(
        isExpanded: true,
        value: value,
        hint: Text(label, style: const TextStyle(fontSize: 18, color: NaniniColors.amber, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
        items: [
          const DropdownMenuItem<String?>(value: _leaveOut, child: Text('Not on the list (leave out)', style: TextStyle(fontSize: 18))),
          for (final p in people) DropdownMenuItem<String?>(value: p.id, child: Text(p.name, style: const TextStyle(fontSize: 18), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      );
}

Widget _box(TextEditingController c, {required bool amber, double width = 52}) => Container(
      width: width,
      height: 44,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: amber ? NaniniColors.amber.withValues(alpha: 0.35) : null,
        border: Border.all(color: NaniniColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: TextField(
        controller: c,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(isDense: true, border: InputBorder.none, filled: false, contentPadding: EdgeInsets.symmetric(vertical: 10)),
      ),
    );

String _n(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

/// A timesheet page read from its photo, checked on the phone by the person
/// who took it: each worker's box per day, as on the paper (amber: couldn't
/// be read -- fix or clear it), and who a written-in worker is. SAVE pops
/// the checked hours ({farm_id, group_name, lines: [{employee_id,
/// employee_name, date, hours}]}); they go straight in (no office approval):
/// paid days and days clocked at another farm are left alone.
class TimesheetCheckPage extends StatefulWidget {
  const TimesheetCheckPage({super.key, required this.photo, required this.read, this.workers = const {}});
  final Uint8List photo;
  final Map<String, dynamic> read;

  /// The written-in lines, as settled on the new-workers step: line index ->
  /// who it is (an employee's id, a new worker, or left out).
  final Map<int, WrittenWorker> workers;
  @override
  State<TimesheetCheckPage> createState() => _TimesheetCheckPageState();
}

class _TimesheetCheckPageState extends State<TimesheetCheckPage> {
  late final TimesheetRead r = TimesheetRead.fromPayload({'read': widget.read})!;
  final rowEmployee = <int, String?>{};
  final cells = <(int, int), TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final (i, row) in r.rows.indexed) {
      final w = widget.workers[i];
      rowEmployee[i] = row.employeeId ?? (w == null ? null : w.leftOut ? _leaveOut : w.key);
      for (var d = 0; d < r.days.length; d++) {
        cells[(i, d)] = TextEditingController(text: d < row.cells.length ? row.cells[d].trim() : '')..addListener(() => setState(() {}));
      }
    }
  }

  @override
  void dispose() {
    for (final c in cells.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _total(int i) => [for (var d = 0; d < r.days.length; d++) timesheetHours(cells[(i, d)]!.text)].fold(0.0, (s, v) => v == null || v.isNaN ? s : s + v);

  void _save(List<RefPerson> people) {
    final newOnes = {for (final w in widget.workers.values) if (w.details != null) w.key: w};
    String nameOf(String id) =>
        newOnes[id]?.label ?? people.where((p) => p.id == id).firstOrNull?.name ?? r.rows.where((x) => x.employeeId == id).firstOrNull?.name ?? 'A worker';
    final lines = <Map<String, dynamic>>[];
    final unclear = <String>[], unnamed = <String>[];
    final seen = <String>{};
    for (final (i, row) in r.rows.indexed) {
      final id = rowEmployee[i];
      final values = [for (var d = 0; d < r.days.length; d++) timesheetHours(cells[(i, d)]!.text)];
      if (id == _leaveOut) continue;
      for (final (d, v) in values.indexed) {
        if (v != null && v.isNaN) unclear.add('line ${row.row}: ${fmtDateDisplay(r.days[d])}');
      }
      if (id == null) {
        if (values.any((v) => v != null && !v.isNaN && v > 0)) unnamed.add('${row.row}');
        continue;
      }
      if (!seen.add(id)) return showNeed(context, '${nameOf(id)} is on two lines -- pick the right worker for each line');
      for (final (d, v) in values.indexed) {
        if (v == null || v.isNaN) continue;
        lines.add({'employee_id': id, 'employee_name': nameOf(id), 'date': r.days[d], 'hours': v});
      }
    }
    if (unclear.isNotEmpty) return showNeed(context, 'Fix or clear the amber boxes: ${unclear.take(4).join(', ')}${unclear.length > 4 ? '…' : ''}');
    if (unnamed.isNotEmpty) return showNeed(context, 'Pick the worker on line ${unnamed.join(', ')} (or clear their hours)');
    if (lines.isEmpty) return showNeed(context, 'No hours on this page');
    final used = {for (final l in lines) l['employee_id']};
    Navigator.pop(context, {
      'farm_id': r.farmId,
      'group_id': r.groupId,
      'group_name': r.groupName,
      'lines': lines,
      // New workers written on the sheet: added (at this farm) when it's saved.
      'new_workers': [for (final w in newOnes.values) if (used.contains(w.key)) {'key': w.key, ...w.details!}],
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<CaptureStore>().ref;
    final people = [...ref.people]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return StepPage(
      task: 'Timesheet',
      step: 2,
      steps: 2,
      question: 'Are the hours right?',
      hint: 'Check each box against the photo and fix it. Amber: not clear. SAVE puts the hours in.',
      onBack: () => Navigator.of(context).pop(),
      onNext: () => _save(people),
      nextLabel: 'SAVE',
      nextIcon: Icons.check,
      child: ListView(children: [
        _Photo(widget.photo),
        Text('${r.farmName}${r.groupName == null ? '' : ' · ${r.groupName}'} · page ${r.page ?? '?'}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final (i, row) in r.rows.indexed)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (row.employeeId != null)
                  Text('${row.row}. ${row.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))
                else if (widget.workers[i] case final w?)
                  Text('${row.row}. ${w.leftOut ? '${row.writtenName} -- left out' : w.details != null ? '${w.label} (new)' : people.where((p) => p.id == w.key).firstOrNull?.name ?? w.label}',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: w.leftOut ? NaniniColors.muted : null))
                else
                  _PickWorker(
                    label: '${row.row}. ${row.writtenName.isEmpty ? 'New worker' : row.writtenName} -- pick',
                    people: people,
                    value: rowEmployee[i],
                    onChanged: (v) => setState(() => rowEmployee[i] = v),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (var d = 0; d < r.days.length; d++)
                      Column(children: [
                        Text('${DateTime.parse(r.days[d]).day}', style: const TextStyle(fontSize: 13, color: NaniniColors.muted)),
                        _box(cells[(i, d)]!, amber: timesheetHours(cells[(i, d)]!.text)?.isNaN ?? false),
                      ]),
                  ]),
                ),
                Text(
                  'Total ${_n(_total(i))} h${row.total.isEmpty ? '' : ' · written ${row.total}'}',
                  style: TextStyle(
                    fontSize: 16,
                    color: row.total.isNotEmpty && double.tryParse(row.total.replaceAll(',', '.')) != null &&
                            (double.parse(row.total.replaceAll(',', '.')) - _total(i)).abs() > 0.01
                        ? NaniniColors.amber
                        : NaniniColors.muted,
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Who a line written in by hand on a timesheet is: an employee ([key] =
/// their id), a new worker ([details] to add, [key] `new:LINE`), or left
/// out.
class WrittenWorker {
  const WrittenWorker.existing(String id, this.label)
      : key = id,
        details = null,
        leftOut = false;
  const WrittenWorker.added(int row, Map<String, dynamic> this.details, this.label)
      : key = 'new:$row',
        leftOut = false;
  const WrittenWorker.out()
      : key = _leaveOut,
        details = null,
        label = '',
        leftOut = true;
  final String key;
  final Map<String, dynamic>? details;
  final String label;
  final bool leftOut;
}

/// The lines of a timesheet page written in by hand (new or temporary
/// workers): the first check after the photo. Each is an existing worker,
/// a NEW WORKER whose details are captured and confirmed here, or left out.
/// Pops line index -> [WrittenWorker] for every such line.
class NewWorkersPage extends StatefulWidget {
  const NewWorkersPage({super.key, required this.read});
  final Map<String, dynamic> read;

  /// The lines written in by hand with a name or hours on them.
  static List<(int, TimesheetRow)> writtenLines(TimesheetRead r) => [
        for (final (i, row) in r.rows.indexed)
          if (row.employeeId == null && (row.writtenName.trim().isNotEmpty || row.cells.any((c) => c.trim().isNotEmpty))) (i, row),
      ];

  @override
  State<NewWorkersPage> createState() => _NewWorkersPageState();
}

class _NewWorkersPageState extends State<NewWorkersPage> {
  late final TimesheetRead r = TimesheetRead.fromPayload({'read': widget.read})!;
  late final lines = NewWorkersPage.writtenLines(r);
  final chosen = <int, WrittenWorker>{};

  Future<void> _newWorker(int i, TimesheetRow row) async {
    final details = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => NewWorkerPage(writtenName: row.writtenName, farmName: r.farmName)));
    if (details == null) return;
    setState(() => chosen[i] = WrittenWorker.added(row.row, details, '${details['name']} ${details['surname'] ?? ''}'.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<CaptureStore>().ref;
    final people = [...ref.people]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return StepPage(
      task: 'Timesheet',
      step: 2,
      steps: 3,
      question: 'New workers on the sheet',
      hint: 'For each name written in: pick the worker, or NEW WORKER to add their details',
      onBack: () => Navigator.of(context).pop(),
      onNext: () {
        final open = [for (final (i, row) in lines) if (!chosen.containsKey(i)) row.row];
        if (open.isNotEmpty) return showNeed(context, 'Say who is on line ${open.join(', ')}: pick, NEW WORKER or LEAVE OUT');
        Navigator.pop(context, Map<int, WrittenWorker>.of(chosen));
      },
      child: ListView(children: [
        for (final (i, row) in lines)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Line ${row.row}: ${row.writtenName.isEmpty ? '(no name written)' : row.writtenName}',
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                if (chosen[i] case final w?)
                  CheckLine(
                    icon: w.leftOut ? Icons.block : Icons.check_circle,
                    color: w.leftOut ? NaniniColors.muted : NaniniColors.green,
                    text: w.leftOut
                        ? 'Left out'
                        : w.details != null
                            ? 'New: ${w.label}${(w.details!['id_or_passport'] ?? '').toString().isEmpty ? '' : ' · ${w.details!['id_or_passport']}'}'
                            : 'Is ${people.where((p) => p.id == w.key).firstOrNull?.name ?? w.label}',
                  ),
                _PickWorker(
                  label: 'Already a worker? Pick them',
                  people: people,
                  value: chosen[i]?.details == null && chosen[i]?.leftOut == false ? chosen[i]!.key : null,
                  onChanged: (v) => setState(() {
                    if (v == null) return;
                    chosen[i] = v == _leaveOut ? const WrittenWorker.out() : WrittenWorker.existing(v, people.firstWhere((p) => p.id == v).name);
                  }),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _newWorker(i, row),
                      icon: const Icon(Icons.person_add),
                      label: Text(chosen[i]?.details != null ? 'CHANGE DETAILS' : 'NEW WORKER', style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => setState(() => chosen[i] = const WrittenWorker.out()),
                    child: const Text('LEAVE OUT', style: TextStyle(fontSize: 18)),
                  ),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// A new worker written on a timesheet: their details, then CONFIRM.
/// Pops {name, surname, full_names, id_or_passport, payment_method,
/// bank_name, bank_account_no, phone_number}.
class NewWorkerPage extends StatefulWidget {
  const NewWorkerPage({super.key, required this.writtenName, required this.farmName});
  final String writtenName;
  final String farmName;
  @override
  State<NewWorkerPage> createState() => _NewWorkerPageState();
}

class _NewWorkerPageState extends State<NewWorkerPage> {
  late final words = widget.writtenName.trim().split(RegExp(r'\s+'));
  // As written on the sheet: surname first, then the name.
  late final surname = TextEditingController(text: words.isNotEmpty ? words.first : '');
  late final name = TextEditingController(text: words.length > 1 ? words.sublist(1).join(' ') : '');
  final fullNames = TextEditingController();
  final idNo = TextEditingController();
  final bank = TextEditingController();
  final account = TextEditingController();
  final phone = TextEditingController();
  String? method;

  @override
  void dispose() {
    for (final c in [surname, name, fullNames, idNo, bank, account, phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String label, TextEditingController c, {TextInputType? keyboard}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          textCapitalization: keyboard == null ? TextCapitalization.words : TextCapitalization.none,
          style: const TextStyle(fontSize: 20),
          decoration: InputDecoration(labelText: label),
        ),
      );

  void _confirm() {
    final problem = employeeDetailsProblem(name: name.text, idOrPassport: idNo.text, fullNames: fullNames.text, surname: surname.text);
    if (problem != null) return showNeed(context, problem);
    if (method == null) return showNeed(context, 'How are they paid? Bank, ATM or Cash');
    if (method == 'atm' && phone.text.trim().isEmpty) return showNeed(context, 'Paid by ATM: type their phone number');
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    Navigator.pop(context, {
      'name': name.text.trim(),
      'surname': t(surname),
      'full_names': t(fullNames),
      'id_or_passport': idNo.text.replaceAll(' ', '').isEmpty ? null : idNo.text.replaceAll(' ', ''),
      'payment_method': method,
      'bank_name': method == 'bank' ? t(bank) : null,
      'bank_account_no': method == 'bank' ? t(account) : null,
      'phone_number': method == 'atm' ? t(phone) : null,
    });
  }

  @override
  Widget build(BuildContext context) => StepPage(
        task: 'New worker',
        step: 1,
        steps: 1,
        question: 'New worker at ${widget.farmName}',
        hint: 'As on their ID. CONFIRM adds them when the sheet is saved.',
        onBack: () => Navigator.of(context).pop(),
        onNext: _confirm,
        nextLabel: 'CONFIRM',
        nextIcon: Icons.check,
        child: ListView(children: [
          _field('Name (known as) *', name),
          _field('Surname', surname),
          _field('Full names (as on ID)', fullNames),
          _field('ID / passport number', idNo, keyboard: TextInputType.text),
          const Text('Paid by', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'bank', label: Text('Bank', style: TextStyle(fontSize: 18))),
              ButtonSegment(value: 'atm', label: Text('ATM', style: TextStyle(fontSize: 18))),
              ButtonSegment(value: 'cash', label: Text('Cash', style: TextStyle(fontSize: 18))),
            ],
            emptySelectionAllowed: true,
            selected: {?method},
            onSelectionChanged: (v) => setState(() => method = v.firstOrNull),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
          ),
          const SizedBox(height: 12),
          if (method == 'bank') ...[_field('Bank', bank), _field('Account number', account, keyboard: TextInputType.number)],
          if (method == 'atm') _field('Phone number *', phone, keyboard: TextInputType.phone),
        ]),
      );
}

/// A fridge sheet page read from its photo, checked on the phone: each
/// worker's count per item (amber: the marks and the total written differ,
/// or the total isn't clear), and who a written-in worker is. SAVE pops the
/// checked sales ({date, note, lines: [{employee_id, employee_name, item_id,
/// item_name, qty}]}); they go straight onto the workers' tuck shop accounts.
class FridgeCheckPage extends StatefulWidget {
  const FridgeCheckPage({super.key, required this.photo, required this.read, this.today});
  final Uint8List photo;
  final Map<String, dynamic> read;

  /// The day of the photo (tests); default today.
  final DateTime? today;
  @override
  State<FridgeCheckPage> createState() => _FridgeCheckPageState();
}

class _FridgeCheckPageState extends State<FridgeCheckPage> {
  late final FridgeRead r = FridgeRead.fromPayload({'read': widget.read})!;
  final rowEmployee = <int, String?>{};
  final cells = <(int, int), TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final (i, row) in r.rows.indexed) {
      rowEmployee[i] = row.employeeId;
      for (var k = 0; k < r.items.length; k++) {
        final c = k < row.counts.length ? row.counts[k] : (marks: 0, total: '');
        cells[(i, k)] = TextEditingController(text: '${fridgeCount(c.marks, c.total) ?? ''}')..addListener(() => setState(() {}));
      }
    }
  }

  @override
  void dispose() {
    for (final c in cells.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// A box as a count: null when empty, -1 when it isn't a whole number.
  static int? _count(String t) {
    final s = t.trim();
    if (s.isEmpty) return null;
    final v = int.tryParse(s);
    return v == null || v < 0 ? -1 : v;
  }

  void _save(List<RefPerson> people) {
    String nameOf(String id) => people.where((p) => p.id == id).firstOrNull?.name ?? 'A worker';
    final lines = <Map<String, dynamic>>[];
    final bad = <String>[], unnamed = <String>[];
    final seen = <String>{};
    for (final (i, row) in r.rows.indexed) {
      final id = rowEmployee[i];
      final counts = [for (var k = 0; k < r.items.length; k++) _count(cells[(i, k)]!.text)];
      if (counts.contains(-1)) bad.add('${row.row}');
      if (id == _leaveOut) continue;
      if (id == null) {
        if (counts.any((c) => c != null && c > 0)) unnamed.add('${row.row}');
        continue;
      }
      if (!seen.add(id)) return showNeed(context, '${nameOf(id)} is on two lines -- pick the right worker for each line');
      for (final (k, c) in counts.indexed) {
        if (c == null || c <= 0) continue;
        final item = r.items[k];
        if (item.id == null) return showNeed(context, "${item.name} isn't on this phone -- open the app on Wi-Fi, then take the photo again");
        lines.add({'employee_id': id, 'employee_name': nameOf(id), 'item_id': item.id, 'item_name': item.name, 'qty': c});
      }
    }
    if (bad.isNotEmpty) return showNeed(context, 'Type a whole number (or clear it) on line ${bad.join(', ')}');
    if (unnamed.isNotEmpty) return showNeed(context, 'Pick the worker on line ${unnamed.join(', ')} (or clear their counts)');
    if (lines.isEmpty) return showNeed(context, 'Nothing taken on this page');
    Navigator.pop(context, {'date': fridgeSaleDate(widget.today ?? DateTime.now(), r.last), 'note': r.purchaseNote, 'lines': lines});
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<CaptureStore>().ref;
    final people = [...ref.people]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return StepPage(
      task: 'Fridge sheet',
      step: 2,
      steps: 2,
      question: 'Are the counts right?',
      hint: 'Check each count against the photo and fix it. Amber: the marks and the total differ. SAVE puts them on the accounts.',
      onBack: () => Navigator.of(context).pop(),
      onNext: () => _save(people),
      nextLabel: 'SAVE',
      nextIcon: Icons.check,
      child: ListView(children: [
        _Photo(widget.photo),
        Text('${r.farmName} · page ${r.page ?? '?'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final (i, row) in r.rows.indexed)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (row.employeeId != null)
                  Text('${row.row}. ${row.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))
                else
                  _PickWorker(
                    label: '${row.row}. ${row.writtenName.isEmpty ? 'New worker' : row.writtenName} -- pick',
                    people: people,
                    value: rowEmployee[i],
                    onChanged: (v) => setState(() => rowEmployee[i] = v),
                  ),
                Wrap(spacing: 10, runSpacing: 4, children: [
                  for (var k = 0; k < r.items.length; k++)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(r.items[k].name, style: const TextStyle(fontSize: 17)),
                      _box(
                        cells[(i, k)]!,
                        width: 60,
                        amber: () {
                          final c = k < row.counts.length ? row.counts[k] : (marks: 0, total: '');
                          final v = _count(cells[(i, k)]!.text);
                          return v == -1 || (fridgeCountUnclear(c.marks, c.total) && '${fridgeCount(c.marks, c.total) ?? ''}' == cells[(i, k)]!.text.trim());
                        }(),
                      ),
                    ]),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}
