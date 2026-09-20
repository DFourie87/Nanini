import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import '../employees/employees_models.dart';

/// Result of matching an uploaded Haaskraal hours sheet against the
/// employee list -- `hoursByEmployeeId` feeds straight into that payroll
/// run, `unmatched` is shown to the user so a typo'd name/ID isn't silently
/// dropped.
class HoursImportResult {
  HoursImportResult({required this.hoursByEmployeeId, required this.unmatched});
  final Map<String, double> hoursByEmployeeId;
  final List<String> unmatched;
}

String _cellText(Data? cell) => (cell?.value?.toString() ?? '').trim();

/// One row per employee: column A is an ID/passport number or, failing
/// that, a full name; column B is total hours for the pay period. The
/// first row is treated as a header and skipped.
double? _parseHours(String raw) {
  final cleaned = raw.replaceAll(',', '.').trim();
  return double.tryParse(cleaned);
}

/// Opens a file picker for an .xlsx sheet, parses it, and matches each row
/// to an employee -- by ID/passport first, then by full name (case- and
/// whitespace-insensitive) -- restricted to `employees` (the Haaskraal
/// list). Returns null if the user cancelled the picker.
Future<HoursImportResult?> pickAndParseHoursExcel(List<Employee> employees) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls'],
    withData: true,
  );
  final bytes = result?.files.single.bytes;
  if (bytes == null) return null;

  final book = Excel.decodeBytes(bytes);
  if (book.tables.isEmpty) return HoursImportResult(hoursByEmployeeId: {}, unmatched: []);
  final sheet = book.tables[book.tables.keys.first]!;

  final byId = {for (final e in employees) if ((e.idOrPassport ?? '').trim().isNotEmpty) e.idOrPassport!.trim().toLowerCase(): e};
  final byName = {for (final e in employees) e.displayName.trim().toLowerCase(): e};

  final hoursByEmployeeId = <String, double>{};
  final unmatched = <String>[];

  for (var i = 1; i < sheet.rows.length; i++) {
    final row = sheet.rows[i];
    if (row.isEmpty) continue;
    final identifier = _cellText(row.length > 0 ? row[0] : null);
    final hoursRaw = _cellText(row.length > 1 ? row[1] : null);
    if (identifier.isEmpty && hoursRaw.isEmpty) continue;
    final hours = _parseHours(hoursRaw);
    if (identifier.isEmpty || hours == null || hours <= 0) {
      if (identifier.isNotEmpty) unmatched.add(identifier);
      continue;
    }

    final key = identifier.toLowerCase();
    final employee = byId[key] ?? byName[key];
    if (employee == null) {
      unmatched.add(identifier);
      continue;
    }
    hoursByEmployeeId[employee.id] = (hoursByEmployeeId[employee.id] ?? 0) + hours;
  }

  return HoursImportResult(hoursByEmployeeId: hoursByEmployeeId, unmatched: unmatched);
}
