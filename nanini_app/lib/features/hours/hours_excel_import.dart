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
/// run, `unmatched` is shown to the user so a typo'd name/passport isn't
/// silently dropped.
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

/// The Name column holds "FirstName  *  PassportNumber" (asterisk-
/// separated) or, if there's no passport on file, just the first name.
/// Returns (firstName, passport) with passport null when there's no
/// asterisk or nothing after it.
(String, String?) _parseNamePassport(String raw) {
  if (!raw.contains('*')) return (raw.trim(), null);
  final parts = raw.split('*');
  final firstName = parts.first.trim();
  final passport = parts.length > 1 ? parts.sublist(1).join('*').trim() : '';
  return (firstName, passport.isEmpty ? null : passport);
}

/// Finds each expected column by its header text in `headerRow` (case-/
/// whitespace-insensitive), falling back to the sheet's known default
/// position when a header isn't found -- so a sheet that hasn't added the
/// optional Surname column still parses exactly as before. -1 means "no
/// such column".
Map<String, int> _columnIndexes(List<Data?> headerRow) {
  const defaults = {'name': 0, 'r/hour': 1, 'total/h': 2, 't/income': 3, 'rent': 4, 'shop': 5, 'uif': 6, 'loan': 7, 'g/total': 8};
  final byHeader = <String, int>{};
  for (var i = 0; i < headerRow.length; i++) {
    final h = _text(headerRow[i]).toLowerCase();
    if (h.isNotEmpty && !byHeader.containsKey(h)) byHeader[h] = i;
  }
  return {
    for (final entry in defaults.entries) entry.key: byHeader[entry.key] ?? entry.value,
    'surname': byHeader['surname'] ?? -1,
  };
}

Data? _cellAt(List<Data?> row, int idx) => (idx >= 0 && idx < row.length) ? row[idx] : null;

/// Opens a file picker for the Haaskraal payroll .xlsx, parses its first
/// sheet, and matches each employee row -- by passport number first (from
/// "FirstName * Passport" in the Name column), then by full name using an
/// optional "Surname" column (the sheet only carries first names
/// otherwise) -- restricted to `employees` (the Haaskraal list). A row
/// with neither a passport nor a Surname match is reported as unmatched
/// rather than guessed at by first name alone. Returns null if the user
/// cancelled the picker.
///
/// Expected layout (matching the sheet actually used): row 1 is a weekday
/// header, row 2 is the column header (Name, R/hour, Total/h, T/Income,
/// RENT, SHOP, UIF, LOAN, G/Total, then one column per day -- plus an
/// optional Surname column anywhere in that row), and data starts on row
/// 3. G/Total is, despite the name, the nett pay for that employee (gross
/// minus rent/shop/uif/loan) -- there's no PAYE column, so imported rows
/// carry paye = 0.
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
  if (sheet.rows.length < 2) return HoursImportResult(rowsByEmployeeId: {}, unmatched: []);

  final cols = _columnIndexes(sheet.rows[1]);

  final byPassport = {for (final e in employees) if ((e.idOrPassport ?? '').trim().isNotEmpty) e.idOrPassport!.trim().toLowerCase(): e};
  final byFullName = {for (final e in employees) e.displayName.trim().toLowerCase(): e};

  final rowsByEmployeeId = <String, HaaskraalPayrollRow>{};
  final unmatched = <String>[];

  for (var i = 2; i < sheet.rows.length; i++) {
    final row = sheet.rows[i];
    if (row.isEmpty) continue;
    final rawName = _text(_cellAt(row, cols['name']!));
    if (rawName.isEmpty) continue;
    final (firstName, passport) = _parseNamePassport(rawName);
    final surname = _text(_cellAt(row, cols['surname']!));

    Employee? employee = passport != null ? byPassport[passport.toLowerCase()] : null;
    if (employee == null && surname.isNotEmpty) {
      employee = byFullName['${firstName.toLowerCase()} ${surname.toLowerCase()}'];
    }
    if (employee == null) {
      unmatched.add(surname.isNotEmpty ? '$firstName $surname' : firstName);
      continue;
    }

    rowsByEmployeeId[employee.id] = HaaskraalPayrollRow(
      employeeId: employee.id,
      hourlyRate: _num(_cellAt(row, cols['r/hour']!)),
      hoursWorked: _num(_cellAt(row, cols['total/h']!)),
      gross: _num(_cellAt(row, cols['t/income']!)),
      rent: _num(_cellAt(row, cols['rent']!)),
      tuckshopDeduction: _num(_cellAt(row, cols['shop']!)),
      uif: _num(_cellAt(row, cols['uif']!)),
      loan: _num(_cellAt(row, cols['loan']!)),
      nett: _num(_cellAt(row, cols['g/total']!)),
    );
  }

  return HoursImportResult(rowsByEmployeeId: rowsByEmployeeId, unmatched: unmatched);
}
