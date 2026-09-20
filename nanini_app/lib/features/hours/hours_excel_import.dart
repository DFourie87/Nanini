import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import '../employees/employees_models.dart';

/// One employee's row from the Haaskraal payroll sheet, already fully
/// computed there (rate, hours, gross, deductions, nett) -- the sheet is
/// the source of truth for that period's pay, not just a source of hours.
class HaaskraalPayrollRow {
  HaaskraalPayrollRow({
    required this.employeeId,
    required this.hoursWorked,
    required this.hourlyRate,
    required this.gross,
    required this.rent,
    required this.tuckshopDeduction,
    required this.uif,
    required this.loan,
    required this.nett,
  });
  final String employeeId;
  final double hoursWorked;
  final double hourlyRate;
  final double gross;
  final double rent;
  final double tuckshopDeduction;
  final double uif;
  final double loan;
  final double nett;
}

/// Result of matching an uploaded Haaskraal payroll sheet against the
/// employee list -- `rowsByEmployeeId` feeds straight into that payroll
/// run, `unmatched` is shown to the user so a typo'd name/ID isn't silently
/// dropped.
class HoursImportResult {
  HoursImportResult({required this.rowsByEmployeeId, required this.unmatched});
  final Map<String, HaaskraalPayrollRow> rowsByEmployeeId;
  final List<String> unmatched;
}

String _text(Data? cell) => (cell?.value?.toString() ?? '').trim();

double _num(Data? cell) {
  final raw = _text(cell);
  if (raw.isEmpty) return 0;
  return double.tryParse(raw.replaceAll(',', '.')) ?? 0;
}

/// Column A holds "Name  *  IDNUMBER" (asterisk-separated) or, if there's
/// no ID on file, just the name. Returns (name, id) with id null when
/// there's no asterisk or nothing after it.
(String, String?) _parseNameId(String raw) {
  if (!raw.contains('*')) return (raw.trim(), null);
  final parts = raw.split('*');
  final name = parts.first.trim();
  final id = parts.length > 1 ? parts.sublist(1).join('*').trim() : '';
  return (name, id.isEmpty ? null : id);
}

/// Opens a file picker for the Haaskraal payroll .xlsx, parses its first
/// sheet, and matches each employee row -- by ID/passport first, then by
/// full name (case- and whitespace-insensitive) -- restricted to
/// `employees` (the Haaskraal list). Returns null if the user cancelled
/// the picker.
///
/// Expected layout (matching the sheet actually used): row 1 is a weekday
/// header, row 2 is the column header (Name, R/hour, Total/h, T/Income,
/// RENT, SHOP, UIF, LOAN, G/Total, then one column per day), and data
/// starts on row 3. G/Total is, despite the name, the nett pay for that
/// employee (gross minus rent/shop/uif/loan) -- there's no PAYE column,
/// so imported rows carry paye = 0.
Future<HoursImportResult?> pickAndParseHoursExcel(List<Employee> employees) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls'],
    withData: true,
  );
  final bytes = result?.files.single.bytes;
  if (bytes == null) return null;

  final book = Excel.decodeBytes(bytes);
  if (book.tables.isEmpty) return HoursImportResult(rowsByEmployeeId: {}, unmatched: []);
  final sheet = book.tables[book.tables.keys.first]!;

  final byId = {for (final e in employees) if ((e.idOrPassport ?? '').trim().isNotEmpty) e.idOrPassport!.trim().toLowerCase(): e};
  final byName = {for (final e in employees) e.displayName.trim().toLowerCase(): e};

  final rowsByEmployeeId = <String, HaaskraalPayrollRow>{};
  final unmatched = <String>[];

  for (var i = 2; i < sheet.rows.length; i++) {
    final row = sheet.rows[i];
    if (row.isEmpty) continue;
    final rawName = _text(row.length > 0 ? row[0] : null);
    if (rawName.isEmpty) continue;
    final (name, id) = _parseNameId(rawName);

    final employee = (id != null ? byId[id.toLowerCase()] : null) ?? byName[name.toLowerCase()];
    if (employee == null) {
      unmatched.add(rawName);
      continue;
    }

    rowsByEmployeeId[employee.id] = HaaskraalPayrollRow(
      employeeId: employee.id,
      hourlyRate: _num(row.length > 1 ? row[1] : null),
      hoursWorked: _num(row.length > 2 ? row[2] : null),
      gross: _num(row.length > 3 ? row[3] : null),
      rent: _num(row.length > 4 ? row[4] : null),
      tuckshopDeduction: _num(row.length > 5 ? row[5] : null),
      uif: _num(row.length > 6 ? row[6] : null),
      loan: _num(row.length > 7 ? row[7] : null),
      nett: _num(row.length > 8 ? row[8] : null),
    );
  }

  return HoursImportResult(rowsByEmployeeId: rowsByEmployeeId, unmatched: unmatched);
}
