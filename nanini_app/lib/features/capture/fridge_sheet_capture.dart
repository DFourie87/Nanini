import '../../core/supabase_client.dart';
import '../employees/employees_repository.dart';
import '../tuckshop/tuckshop_repository.dart';
import 'capture_models.dart';

/// A box to check: its Total can't be read, or differs from the marks counted.
bool fridgeCountUnclear(int marks, String total) => total == '?' || (marks > 0 && int.tryParse(total) != null && int.parse(total) != marks);

/// How many were taken, as read: the total written, else the marks counted;
/// null when nothing.
int? fridgeCount(int marks, String total) => int.tryParse(total) ?? (marks > 0 ? marks : null);

/// A fridge sheet page as read from its photo on the phone
/// (capture_app/fridge_reader.dart, in the entry's payload 'read'): the
/// sheet from its QR code, its items, and per line the marks per item.
class FridgeRead {
  FridgeRead({
    required this.farmId,
    required this.farmName,
    required this.month,
    required this.first,
    required this.last,
    required this.items,
    required this.rows,
    this.page,
    this.notes,
  });
  final String farmId, farmName;

  /// 'YYYY-MM': the month the sheet is named for; [first]..[last] its pay period.
  final String month, first, last;
  final List<FridgeItem> items;
  final List<FridgeRow> rows;

  /// e.g. '1/2'.
  final String? page;

  /// Anything the reader wasn't sure of.
  final String? notes;

  static FridgeRead? fromPayload(Map<String, dynamic> p) {
    final r = p['read'];
    if (r is! Map) return null;
    return FridgeRead(
      farmId: r['farm_id'] as String,
      farmName: r['farm_name'] as String? ?? '',
      month: r['month'] as String? ?? '',
      first: r['first'] as String? ?? '',
      last: r['last'] as String? ?? '',
      items: [
        for (final i in ((r['items'] as List?) ?? const []).cast<Map>())
          FridgeItem(id: i['id'] as String?, prefix: i['prefix'] as String? ?? '', name: i['name'] as String? ?? ''),
      ],
      rows: [for (final row in ((r['rows'] as List?) ?? const []).cast<Map>()) FridgeRow.fromJson(row.cast<String, dynamic>())],
      page: r['page'] as String?,
      notes: r['notes'] as String?,
    );
  }

  /// What the tuck shop purchases from this page are noted with -- so the
  /// same page can't be approved twice.
  String get purchaseNote => 'Fridge sheet $farmName from $first, page ${page ?? '?'}';
}

class FridgeItem {
  FridgeItem({required this.id, required this.prefix, required this.name});

  /// Null when the phone didn't know the item: found in the hub by [prefix].
  final String? id;
  final String prefix, name;
}

class FridgeRow {
  FridgeRow({required this.row, required this.counts, this.employeeId, this.idPrefix, this.name = '', this.writtenName = ''});

  /// The row number printed on the sheet.
  final int row;

  /// A printed worker (from the QR code), or a written-in one the phone
  /// recognised; null otherwise.
  final String? employeeId;

  /// A printed worker the phone didn't know: the start of their id (QR code).
  final String? idPrefix;
  final String name;

  /// A new worker's name as written on an empty line.
  final String writtenName;

  /// Per item, in the sheet's order: the marks counted and the total written
  /// ('' none, '?' can't be read).
  final List<({int marks, String total})> counts;

  factory FridgeRow.fromJson(Map<String, dynamic> j) => FridgeRow(
        row: (j['row'] as num).toInt(),
        employeeId: j['employee_id'] as String?,
        idPrefix: j['id_prefix'] as String?,
        name: j['name'] as String? ?? '',
        writtenName: j['written_name'] as String? ?? '',
        counts: [
          for (final c in ((j['counts'] as List?) ?? const []).cast<Map>()) (marks: ((c['marks'] as num?) ?? 0).toInt(), total: '${c['total'] ?? ''}'),
        ],
      );
}

/// A fridge sheet page as checked in the hub: what each worker took.
class FridgeApproval {
  FridgeApproval({required this.date, required this.note, required this.lines});

  /// The purchases' date: the day the page was photographed (or the sheet's
  /// last day, when later) -- they come off the first pay not yet done.
  final String date;
  final String note;
  final List<({String employeeId, String itemId, int qty})> lines;
}

/// The date fridge sheet purchases go in on: the day the photo was taken,
/// but not after the sheet's last day.
String fridgeSaleDate(DateTime capturedAt, String last) {
  final d = capturedAt.toIso8601String().substring(0, 10);
  return last.isNotEmpty && d.compareTo(last) > 0 ? last : d;
}

/// Approving a checked fridge sheet page: each worker's count of each item
/// goes on their tuck shop account as a sale (stock taken off, like a sale
/// in the shop). Not twice for the same page.
Future<void> applyFridgeCapture(CaptureEntry entry, FridgeApproval a) async {
  final done = await sb.from('tuckshop_purchases').select('id').eq('note', a.note).limit(1);
  if ((done as List).isNotEmpty) throw StateError('This page is already on the tuck shop accounts (${a.note}) -- reject it.');
  final employees = await EmployeesRepository().watchEmployees().first;
  final repo = TuckshopRepository();
  for (final l in a.lines.where((l) => l.qty > 0)) {
    final employee = employees.where((e) => e.id == l.employeeId).firstOrNull;
    if (employee == null) throw StateError('A worker on the sheet is no longer in the employee list.');
    // Re-read each time: every sale uses up stock batches (FIFO), so the
    // next line must see what's left.
    final item = (await repo.watchItems().first).where((i) => i.id == l.itemId).firstOrNull;
    if (item == null) throw StateError('An item on the sheet is no longer in the tuck shop stock list.');
    await repo.logItemPurchase(item: item, employee: employee, qty: l.qty.toDouble(), date: a.date, note: a.note);
  }
}

/// The hub's lines for a fridge sheet entry in the Captured list.
List<String> fridgeSheetDetailLines(CaptureEntry e) {
  final read = FridgeRead.fromPayload(e.payload);
  if (read == null) return ['Photo of a fridge sheet page', 'Not read on the phone -- reject it and send the page again'];
  final people = read.rows.where((r) => r.counts.any((c) => fridgeCount(c.marks, c.total) != null)).length;
  return [
    'Fridge sheet ${read.farmName} · from ${read.first} · page ${read.page ?? '?'}',
    for (final (i, item) in read.items.indexed)
      '${item.name}: ${read.rows.fold<int>(0, (s, r) => s + (i < r.counts.length ? fridgeCount(r.counts[i].marks, r.counts[i].total) ?? 0 : 0))} as read',
    'Read: $people workers took something -- check it before approving',
    if ((read.notes ?? '').isNotEmpty) 'Reader: ${read.notes}',
  ];
}
