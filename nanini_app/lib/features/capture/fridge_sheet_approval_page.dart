import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import '../suppliers/suppliers_capture_approval.dart' show capturedPhoto;
import '../tuckshop/tuckshop_models.dart';
import '../tuckshop/tuckshop_repository.dart';
import 'capture_models.dart';
import 'fridge_sheet_capture.dart';

/// Checking a fridge sheet page read from its photo: the photo above a list
/// like the paper's, each count editable. Under each count: the marks
/// counted and the total written. Amber: they differ, or the total can't be
/// read -- check it against the photo. Pops a [FridgeApproval] on Approve.
class FridgeSheetApprovalPage extends StatefulWidget {
  const FridgeSheetApprovalPage({super.key, required this.entry});
  final CaptureEntry entry;
  @override
  State<FridgeSheetApprovalPage> createState() => _FridgeSheetApprovalPageState();
}

class _FridgeSheetApprovalPageState extends State<FridgeSheetApprovalPage> {
  FridgeRead? read;
  Uint8List? photo;
  List<Employee> employees = [];

  /// The sheet's items as in the stock list (by the start of their id when
  /// the phone didn't know them); null when not found.
  List<TuckshopItem?> items = [];
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
      final r = FridgeRead.fromPayload(widget.entry.payload);
      if (r == null) {
        setState(() {
          problem = 'Not read on the phone -- reject it and send the page again.';
          loading = false;
        });
        return;
      }
      final results = await Future.wait([
        capturedPhoto(widget.entry.id),
        EmployeesRepository().watchEmployees().first,
        TuckshopRepository().watchItems().first,
      ]);
      read = r;
      photo = results[0] as Uint8List?;
      employees = (results[1] as List<Employee>)..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      final stock = results[2] as List<TuckshopItem>;
      items = [
        for (final i in r.items)
          stock.where((s) => s.id == i.id).firstOrNull ?? (stock.where((s) => s.id.startsWith(i.prefix)).length == 1 ? stock.firstWhere((s) => s.id.startsWith(i.prefix)) : null),
      ];
      for (final (i, row) in r.rows.indexed) {
        // A printed worker the phone didn't know: by the start of their id.
        final byPrefix = row.idPrefix == null ? const <Employee>[] : employees.where((e) => e.id.startsWith(row.idPrefix!)).toList();
        rowEmployee[i] = row.employeeId ?? (byPrefix.length == 1 ? byPrefix.single.id : null);
        for (var k = 0; k < r.items.length; k++) {
          final c = k < row.counts.length ? row.counts[k] : (marks: 0, total: '');
          cells[(i, k)] = TextEditingController(text: '${fridgeCount(c.marks, c.total) ?? ''}')..addListener(() => setState(() {}));
        }
      }
    } catch (e) {
      problem = 'Could not load the fridge sheet: $e';
    }
    if (mounted) setState(() => loading = false);
  }

  /// A box as a count: null when empty, -1 when it isn't a whole number.
  static int? _count(String t) {
    final s = t.trim();
    if (s.isEmpty) return null;
    final v = int.tryParse(s);
    return v == null || v < 0 ? -1 : v;
  }

  void _approve() {
    final r = read!;
    final missing = [for (final (k, item) in items.indexed) if (item == null) r.items[k].name];
    if (missing.isNotEmpty) {
      showProblem(context, 'Not in the tuck shop stock list: ${missing.join(', ')} -- reject this page.');
      return;
    }
    final lines = <({String employeeId, String itemId, int qty})>[];
    final bad = <String>[], unnamed = <String>[];
    final seen = <String>{};
    for (final (i, row) in r.rows.indexed) {
      final id = rowEmployee[i];
      final counts = [for (var k = 0; k < r.items.length; k++) _count(cells[(i, k)]!.text)];
      if (counts.contains(-1)) bad.add('${row.row}');
      if (id == null) {
        if (counts.any((c) => c != null && c > 0)) unnamed.add('${row.row}');
        continue;
      }
      if (!seen.add(id)) {
        showProblem(context, '${_nameOf(id)} is on two lines -- pick the right worker for each line.');
        return;
      }
      for (final (k, c) in counts.indexed) {
        if (c != null && c > 0) lines.add((employeeId: id, itemId: items[k]!.id, qty: c));
      }
    }
    if (bad.isNotEmpty) {
      showProblem(context, 'Type a whole number (or clear it) on line ${bad.join(', ')}.');
      return;
    }
    if (unnamed.isNotEmpty) {
      showProblem(context, 'Pick the worker on line ${unnamed.join(', ')} (or clear their counts).');
      return;
    }
    if (lines.isEmpty) {
      showProblem(context, 'Nothing taken on this page.');
      return;
    }
    Navigator.pop(context, FridgeApproval(date: fridgeSaleDate(widget.entry.capturedAt, r.last), note: r.purchaseNote, lines: lines));
  }

  String _nameOf(String id) => employees.where((e) => e.id == id).firstOrNull?.displayName ?? 'A worker';

  @override
  Widget build(BuildContext context) {
    final r = read;
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Check fridge sheet'),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : r == null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(problem ?? 'Not read yet.', textAlign: TextAlign.center)))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text('${r.farmName} · from ${fmtDateDisplay(r.first)} · page ${r.page ?? '?'}', style: Theme.of(context).textTheme.titleMedium),
                    if ((r.notes ?? '').isNotEmpty) Text('Reader: ${r.notes}', style: const TextStyle(color: NaniniColors.muted)),
                    const SizedBox(height: 6),
                    Text('Check each count against the photo and correct it. Under each: the marks counted and the total written. '
                        'Amber: they differ or the total isn\'t clear. Approving puts them on the workers\' tuck shop accounts '
                        '(dated ${fmtDateDisplay(fridgeSaleDate(widget.entry.capturedAt, r.last))}) and takes them off the stock.'),
                    const SizedBox(height: 8),
                    if (photo != null)
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => Scaffold(
                                  appBar: const NaniniAppBar(title: 'Fridge sheet photo'),
                                  body: InteractiveViewer(maxScale: 8, child: Center(child: Image.memory(photo!))),
                                ))),
                        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(photo!, height: 220, fit: BoxFit.contain)),
                      ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(scrollDirection: Axis.horizontal, child: _grid(r)),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(onPressed: _approve, icon: const Icon(Icons.check), label: const Text('Approve these')),
                    ),
                  ],
                ),
    );
  }

  Widget _grid(FridgeRead r) {
    const nameW = 240.0, itemW = 120.0;
    Widget head(String t, double w) => SizedBox(width: w, child: Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          head('Worker', nameW),
          for (final (k, i) in r.items.indexed) head(items[k]?.name ?? '${i.name} (not in stock list)', itemW),
        ]),
        for (final (i, row) in r.rows.indexed) _row(r, i, row, nameW: nameW, itemW: itemW),
        const Divider(),
        Row(children: [
          head('Total', nameW),
          for (var k = 0; k < r.items.length; k++)
            head('${[for (var i = 0; i < r.rows.length; i++) _count(cells[(i, k)]!.text) ?? 0].where((c) => c > 0).fold<int>(0, (a, b) => a + b)}', itemW),
        ]),
      ],
    );
  }

  Widget _row(FridgeRead r, int i, FridgeRow row, {required double nameW, required double itemW}) {
    final id = rowEmployee[i];
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: nameW,
          child: row.employeeId != null || (row.idPrefix != null && id != null)
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${row.row}. ${row.employeeId != null && row.name.isNotEmpty ? row.name : _nameOf(id!)}', overflow: TextOverflow.ellipsis),
                )
              // A worker written in by hand: pick who it is.
              : DropdownButton<String?>(
                  isExpanded: true,
                  value: id,
                  hint: Text('${row.row}. ${row.writtenName.isEmpty ? 'New worker' : row.writtenName} -- pick',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(color: NaniniColors.amber)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Not on the list (leave out)')),
                    for (final e in employees) DropdownMenuItem<String?>(value: e.id, child: Text(e.displayName, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => rowEmployee[i] = v),
                ),
        ),
        for (var k = 0; k < r.items.length; k++) _cell(i, k, row, itemW),
      ]),
    );
  }

  Widget _cell(int i, int k, FridgeRow row, double w) {
    final c = cells[(i, k)]!;
    final read = k < row.counts.length ? row.counts[k] : (marks: 0, total: '');
    final value = _count(c.text);
    final unclear = value == -1 || (fridgeCountUnclear(read.marks, read.total) && '${fridgeCount(read.marks, read.total) ?? ''}' == c.text.trim());
    return SizedBox(
      width: w,
      child: Column(children: [
        Container(
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          color: unclear ? NaniniColors.amber.withValues(alpha: 0.35) : null,
          child: TextField(
            controller: c,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8), border: InputBorder.none, filled: false),
          ),
        ),
        if (read.marks > 0 || read.total.isNotEmpty)
          Text('marks ${read.marks} · total ${read.total.isEmpty ? '-' : read.total}', style: const TextStyle(fontSize: 11, color: NaniniColors.muted)),
      ]),
    );
  }
}
