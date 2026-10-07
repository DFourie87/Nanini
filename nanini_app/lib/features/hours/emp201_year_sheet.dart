import 'package:intl/intl.dart';
import '../employees/employees_models.dart';
import 'emp201_year.dart';
import 'pay_widgets.dart';
import 'payroll_month.dart';

/// One cell of the EMP201 summary sheet: text, or a number (2 decimals).
class SheetCell {
  const SheetCell.text(this.text, {this.bold = false, this.tone = SheetTone.normal, bool right = false})
      : number = null,
        left = !right,
        integer = false;
  const SheetCell.number(this.number, {this.bold = false, this.tone = SheetTone.normal, this.integer = false})
      : text = null,
        left = false;
  const SheetCell.empty()
      : text = null,
        number = null,
        bold = false,
        left = false,
        tone = SheetTone.normal,
        integer = false;
  final String? text;
  final double? number;
  final bool bold;
  final bool left;
  final SheetTone tone;

  /// A count, not money: no decimals.
  final bool integer;
}

enum SheetTone { normal, red, green }

/// A row: its cells, shaded as a heading or total row.
class SheetRow {
  const SheetRow(this.cells, {this.shade = SheetShade.none});
  final List<SheetCell> cells;
  final SheetShade shade;
}

enum SheetShade { none, heading, total }

/// A table with an optional heading above it; [fixed] widths (points) for
/// the first columns, the rest share what's left.
class SheetTable {
  const SheetTable(this.rows, {this.heading, this.fixed = const []});
  final String? heading;
  final List<SheetRow> rows;
  final List<double> fixed;
}

/// A part of the sheet -- a page in the preview: title, note, tables.
class SheetSection {
  const SheetSection(this.title, this.note, this.tables);
  final String title;
  final String note;
  final List<SheetTable> tables;
}

/// The EMP201 summary of [taxYear], laid out once -- the preview (PDF) and
/// the Excel are both drawn from it, so they're the same: the months
/// (worked out, submitted, difference), then everyone paid, each month's
/// salary, UIF and PAYE in the three groups -- March to August, then
/// September to February -- and each one's year: total pay, UIF, PAYE.
List<SheetSection> emp201YearSheet(int taxYear, List<Emp201YearMonth> months, {List<Farm> farms = const []}) {
  final title = 'Nanini 121 CC -- EMP201 summary, tax year $taxYear (March ${taxYear - 1} to February $taxYear)';
  final monthName = DateFormat('MMMM yyyy');
  final mon = DateFormat('MMM yy');
  SheetCell n(double? v, {bool bold = false, SheetTone tone = SheetTone.normal}) =>
      v == null ? const SheetCell.empty() : SheetCell.number((v * 100).roundToDouble() / 100, bold: bold, tone: tone);
  SheetCell t(String s, {bool bold = false}) => SheetCell.text(s, bold: bold);
  // A heading over numbers: right, like them.
  const textCols = {'Month', 'Employee', 'Farm', 'ID/passport', 'Submitted on', 'Reference'};
  SheetCell h(String s) => SheetCell.text(s, bold: true, right: !textCols.contains(s));
  String farm(Employee? e) => farmShort(farms.where((f) => f.id == e?.farmId).firstOrNull);

  // 1. The months.
  final subs = months.where((m) => m.submitted != null).toList();
  double tot(double Function(Emp201YearMonth) f) => months.fold(0.0, (s, m) => s + f(m));
  double? sub(double Function(Emp201YearMonth) f) => subs.isEmpty ? null : subs.fold<double>(0.0, (s, m) => s + f(m));
  final monthsTable = SheetTable(fixed: const [70], [
    SheetRow([
      for (final h0 in ['Month', 'Employees', 'Remuneration', 'UIF', 'PAYE', 'Total', 'Submitted UIF', 'Submitted PAYE', 'Submitted total', 'Difference', 'Submitted on', 'Reference'])
        h(h0),
    ], shade: SheetShade.heading),
    for (final m in months)
      SheetRow([
        t('${monthName.format(DateTime.parse(m.month))}${m.fromHistory ? ' *' : ''}'),
        // A month not paid yet: blank.
        m.lines.isEmpty ? const SheetCell.empty() : SheetCell.number(m.employees.toDouble(), integer: true),
        for (final v in [m.salary, m.uif, m.paye]) m.lines.isEmpty ? const SheetCell.empty() : n(v),
        m.lines.isEmpty ? const SheetCell.empty() : n(m.total, bold: true),
        n(m.submitted?.uif), n(m.submitted?.paye), n(m.submitted?.total),
        n(m.difference, tone: m.difference == null ? SheetTone.normal : (m.difference!.abs() < 0.01 ? SheetTone.green : SheetTone.red)),
        m.submitted?.submittedOn == null ? const SheetCell.empty() : t(m.submitted!.submittedOn!),
        m.submitted?.reference == null ? const SheetCell.empty() : t(m.submitted!.reference!),
      ]),
    SheetRow([
      t('Total', bold: true), const SheetCell.empty(),
      n(tot((m) => m.salary), bold: true), n(tot((m) => m.uif), bold: true),
      n(tot((m) => m.paye), bold: true), n(tot((m) => m.total), bold: true),
      n(sub((m) => m.submitted!.uif), bold: true),
      n(sub((m) => m.submitted!.paye), bold: true), n(sub((m) => m.submitted!.total), bold: true),
      n(sub((m) => m.difference!), bold: true), const SheetCell.empty(), const SheetCell.empty(),
    ], shade: SheetShade.heading),
  ]);

  // 2. Everyone, half a year per section: salary, UIF, PAYE a month.
  final people = emp201YearByEmployee(months);
  double yearOf(Emp201EmployeeYear y, int i) => y.months.values.fold<double>(0, (s, l) => s + (emp201Figure(l, i) ?? 0));
  const k = 3; // figures a month
  List<SheetTable> employees(List<Emp201YearMonth> ms) => [
        for (final g in Emp201Group.values)
          SheetTable(
            heading: '${g.label} (${people[g]!.length})${g == Emp201Group.declared ? '' : ' -- UIF here is what was taken off their pay, not declared'}',
            fixed: const [78, 42, 54],
            [
              SheetRow([
                h('Employee'), h('Farm'), h('ID/passport'),
                for (final m in ms) ...[h(mon.format(DateTime.parse(m.month))), for (final f in emp201Figures.skip(1)) h(f)],
              ], shade: SheetShade.heading),
              for (final y in people[g]!)
                SheetRow([
                  t(y.name), t(farm(y.employee)), t(y.employee?.idOrPassport ?? ''),
                  for (final m in ms)
                    for (var i = 0; i < k; i++)
                      n(emp201Figure(y.months[m.month], i),
                          tone: i > 0 && (y.months[m.month]?.withheldNotDeclared ?? false) ? SheetTone.red : SheetTone.normal),
                ]),
              SheetRow([
                t('Total', bold: true), const SheetCell.empty(), const SheetCell.empty(),
                for (final m in ms)
                  for (var i = 0; i < k; i++) n(people[g]!.fold<double>(0, (s, y) => s + (emp201Figure(y.months[m.month], i) ?? 0)), bold: true),
              ], shade: SheetShade.total),
            ],
          ),
      ];

  // 3. The year per employee: total pay, UIF and PAYE.
  final yearTables = [
    for (final g in Emp201Group.values)
      SheetTable(
        heading: '${g.label} (${people[g]!.length})${g == Emp201Group.declared ? '' : ' -- UIF here is what was taken off their pay, not declared'}',
        fixed: const [110, 60, 80],
        [
          SheetRow([
            for (final c in ['Employee', 'Farm', 'ID/passport', 'Months paid', 'Total pay', 'UIF', 'PAYE']) h(c),
          ], shade: SheetShade.heading),
          for (final y in people[g]!)
            SheetRow([
              t(y.name), t(farm(y.employee)), t(y.employee?.idOrPassport ?? ''),
              SheetCell.number(y.months.values.where((l) => l.salary > 0).length.toDouble(), integer: true),
              for (var i = 0; i < k; i++) n(yearOf(y, i), bold: i == 0, tone: i > 0 && y.months.values.any((l) => l.withheldNotDeclared) ? SheetTone.red : SheetTone.normal),
            ]),
          SheetRow([
            t('Total', bold: true), const SheetCell.empty(), const SheetCell.empty(), const SheetCell.empty(),
            for (var i = 0; i < k; i++) n(people[g]!.fold<double>(0, (s, y) => s + yearOf(y, i)), bold: true),
          ], shade: SheetShade.total),
        ],
      ),
  ];

  return [
    SheetSection(
      title,
      'EMP201 per month: worked out, what was submitted on eFiling, and the difference (submitted less worked out). '
      'Only employees on the EMP201 count; UIF is the employees\' and the employer\'s together. * From the old salary summary.',
      [monthsTable],
    ),
    SheetSection(title, 'Per employee, March to August ${taxYear - 1}: salary, UIF and PAYE each month.', employees(months.sublist(0, 6))),
    SheetSection(title, 'Per employee, September ${taxYear - 1} to February $taxYear: salary, UIF and PAYE each month.', employees(months.sublist(6))),
    SheetSection(title, 'Per employee, the tax year: total pay, UIF and PAYE.', yearTables),
  ];
}
