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

/// The employer on SARS documents (as on the IRP5/EMP501).
const kEmployerName = 'NANINI 121 CC';
const kTradingName = 'NANINI BOERDERY';
const kPayeRef = '7470796030';
const kSdlRef = 'L470796030';
const kUifRef = 'U470796030';

SheetCell _n(double? v, {bool bold = false, SheetTone tone = SheetTone.normal}) =>
    v == null ? const SheetCell.empty() : SheetCell.number((v * 100).roundToDouble() / 100, bold: bold, tone: tone);
SheetCell _t(String s, {bool bold = false}) => SheetCell.text(s, bold: bold);

// A heading over numbers: right, like them.
const _textCols = {
  'Month', 'Tax', 'As', 'Employee', 'Farm', 'ID/passport', 'Surname', 'Initials', 'Full names', 'Date of birth', 'Income tax no', //
  'Employed from', 'Employed to', 'Certificate', 'Reason', 'Item',
};
SheetCell _h(String s) => SheetCell.text(s, bold: true, right: !_textCols.contains(s));
SheetCell _diff(double v) => _n(v, bold: true, tone: v.abs() < 0.01 ? SheetTone.green : SheetTone.red);

/// Employer, references and the period, at the top of each report.
SheetTable _employer(List<(String, String)> more) => SheetTable(heading: 'Employer', fixed: const [110], [
      SheetRow([_h('Item'), _h('Value')], shade: SheetShade.heading),
      for (final (k, v) in [
        ('Employer', '$kEmployerName (trading as $kTradingName)'),
        ('PAYE reference', kPayeRef),
        ('SDL reference', kSdlRef),
        ('UIF reference', kUifRef),
        ...more,
      ])
        SheetRow([_t(k), _t(v)]),
    ]);

/// The EMP201 report for month [m]: what to declare to SARS -- the
/// employer, the amounts (PAYE, UIF employees' and employer's, total, due
/// date) and what was submitted on eFiling -- then the month's pay per
/// employee in the three groups (only "On EMP201" is declared).
List<SheetSection> emp201MonthSheet(Emp201YearMonth m, {List<Farm> farms = const []}) {
  final month = DateTime.parse(m.month);
  final name = DateFormat('MMMM yyyy').format(month);
  final due = Emp201(month, const [], includeSdl: false).dueDate;
  final ymd = DateFormat('yyyy-MM-dd');
  final title = 'EMP201 report -- $name';
  String farm(Employee? e) => farmShort(farms.where((f) => f.id == e?.farmId).firstOrNull);
  final paid = m.lines.isNotEmpty;
  final uifEmployees = m.uif / 2, uifEmployer = m.uif / 2;

  final declaration = SheetTable(heading: 'Declaration', fixed: const [160], [
    SheetRow([_h('Item'), _h('Amount')], shade: SheetShade.heading),
    SheetRow([_t('Employees on EMP201'), paid ? SheetCell.number(m.employees.toDouble(), integer: true) : const SheetCell.empty()]),
    SheetRow([_t('Gross remuneration'), paid ? _n(m.salary) : const SheetCell.empty()]),
    SheetRow([_t('PAYE'), paid ? _n(m.paye) : const SheetCell.empty()]),
    SheetRow([_t('UIF -- employees (1%)'), paid ? _n(uifEmployees) : const SheetCell.empty()]),
    SheetRow([_t('UIF -- employer (1%)'), paid ? _n(uifEmployer) : const SheetCell.empty()]),
    SheetRow([_t('UIF -- total'), paid ? _n(m.uif) : const SheetCell.empty()]),
    SheetRow([_t('Total payable', bold: true), paid ? _n(m.paye + m.uif, bold: true) : const SheetCell.empty()], shade: SheetShade.total),
  ]);
  final s = m.submitted;
  final submittedTable = SheetTable(heading: 'Submitted on eFiling', fixed: const [160], [
    SheetRow([_h('Item'), _h('Amount')], shade: SheetShade.heading),
    if (s == null)
      SheetRow([_t('Not entered yet -- tap Submitted after submitting on eFiling'), const SheetCell.empty()])
    else ...[
      SheetRow([_t('PAYE'), _n(s.paye)]),
      SheetRow([_t('UIF'), _n(s.uif)]),
      SheetRow([_t('Total', bold: true), _n(s.paye + s.uif, bold: true)], shade: SheetShade.total),
      SheetRow([_t('Difference (submitted less worked out)'), _diff(s.paye + s.uif - m.paye - m.uif)]),
      SheetRow([_t('Submitted on'), _t(s.submittedOn ?? '')]),
      SheetRow([_t('Reference'), _t(s.reference ?? '')]),
    ],
  ]);

  // The month's pay per employee, in the three groups.
  final groups = {for (final g in Emp201Group.values) g: <Emp201EmployeeMonth>[]};
  for (final l in m.lines) {
    groups[emp201GroupOf(l.employee)]!.add(l);
  }
  final employees = [
    for (final g in Emp201Group.values)
      SheetTable(
        heading: '${g.label} (${groups[g]!.length})${g == Emp201Group.declared ? '' : ' -- not declared; UIF is what was taken off their pay'}',
        fixed: const [110, 60, 80],
        [
          SheetRow([for (final c in ['Employee', 'Farm', 'ID/passport', 'Gross pay', 'PAYE', 'UIF employee', 'UIF employer']) _h(c)], shade: SheetShade.heading),
          for (final l in groups[g]!)
            () {
              final red = l.withheldNotDeclared ? SheetTone.red : SheetTone.normal;
              return SheetRow([
                _t(l.name), _t(farm(l.employee)), _t(l.employee?.idOrPassport ?? ''),
                _n(l.salary), _n(l.paye, tone: l.paye > l.dPaye + 0.004 ? SheetTone.red : SheetTone.normal),
                _n(l.uif - l.dUif / 2, tone: red), l.dUif > 0 ? _n(l.dUif / 2) : const SheetCell.empty(),
              ]);
            }(),
          SheetRow([
            _t('Total', bold: true), const SheetCell.empty(), const SheetCell.empty(),
            _n(groups[g]!.fold<double>(0, (a, l) => a + l.salary), bold: true),
            _n(groups[g]!.fold<double>(0, (a, l) => a + l.paye), bold: true),
            _n(groups[g]!.fold<double>(0, (a, l) => a + l.uif - l.dUif / 2), bold: true),
            _n(groups[g]!.fold<double>(0, (a, l) => a + l.dUif / 2), bold: true),
          ], shade: SheetShade.total),
        ],
      ),
  ];

  return [
    SheetSection(
      title,
      'What to declare on the EMP201 for $name, due by ${ymd.format(due)}. Only employees on the EMP201 count'
      '${m.fromHistory ? ' (this month from the old salary summary)' : ''}. After submitting on eFiling, enter what was submitted.',
      [
        _employer([('Period', DateFormat('yyyyMM').format(month)), ('Due by', ymd.format(due))]),
        declaration,
        submittedTable,
      ],
    ),
    SheetSection(
      'EMP201 report -- employees, $name',
      'Pay in the $name EMP201 per employee: on EMP201 (declared), and not on it with or without an ID/passport. '
      'Red: UIF or PAYE taken off pay that isn\'t declared.',
      employees,
    ),
  ];
}

/// The EMP501 reconciliation of [taxYear]: interim (March to August) or
/// annual (March to February). Each employee on the EMP201 as on their
/// IRP5/IT3(a), then the certificates' totals against the EMP201s
/// declared, month by month.
List<SheetSection> emp501Sheet(int taxYear, List<Emp201YearMonth> yearMonths, {required bool interim, List<Farm> farms = const []}) {
  final months = interim ? yearMonths.sublist(0, 6) : yearMonths;
  final kind = interim ? 'interim' : 'annual';
  final range = interim ? 'March to August ${taxYear - 1}' : 'March ${taxYear - 1} to February $taxYear';
  final period = interim ? '${taxYear - 1}08' : '${taxYear}02';
  final title = 'EMP501 report -- $kind reconciliation, tax year $taxYear ($range)';
  final ymd = DateFormat('yyyy-MM-dd');
  String farm(Employee? e) => farmShort(farms.where((f) => f.id == e?.farmId).firstOrNull);
  final people = emp201YearByEmployee(months)[Emp201Group.declared]!;

  // Certificates: each registered employee, only pay declared.
  final irp5 = SheetTable(heading: 'Certificates (IRP5/IT3(a)) -- ${people.length} employees', fixed: const [80], [
    SheetRow([
      for (final c in [
        'Employee', 'Surname', 'Initials', 'Full names', 'ID/passport', 'Date of birth', 'Income tax no', 'Farm', //
        'Employed from', 'Employed to', 'Months', 'Certificate', '3601 Income', '3699 Gross', '4102 PAYE', '4141 UIF', '4149 Total', 'Reason',
      ])
        _h(c),
    ], shade: SheetShade.heading),
    for (final y in people)
      () {
        final ls = (y.months.values.where((l) => l.counted).toList()..sort((a, b) => a.month.compareTo(b.month)));
        final pay = ls.fold<double>(0, (s, l) => s + l.dSalary);
        final paye = ls.fold<double>(0, (s, l) => s + l.dPaye);
        final uif = ls.fold<double>(0, (s, l) => s + l.dUif);
        final e = y.employee;
        final first = ls.isEmpty ? null : DateTime.parse(ls.first.month);
        final last = ls.isEmpty ? null : DateTime.parse(ls.last.month);
        final it3a = paye < 0.005;
        return SheetRow([
          _t(y.name), _t(irp5Surname(e, y.name)), _t(irp5Initials(e, y.name)), _t(irp5FullNames(e, y.name)), _t(e?.idOrPassport ?? ''),
          _t(dobFromSaId(e?.idOrPassport) ?? ''), _t(e?.incomeTaxNo ?? ''), _t(farm(e)),
          _t(first == null ? '' : ymd.format(first)),
          // Left the farm: the day they left; else the end of the last month paid.
          _t(e?.leftOn != null && last != null && e!.leftOn!.compareTo(ymd.format(first!)) >= 0
              ? e.leftOn!
              : last == null
                  ? ''
                  : ymd.format(DateTime(last.year, last.month + 1, 0))),
          SheetCell.number(ls.length.toDouble(), integer: true), _t(it3a ? 'IT3(a)' : 'IRP5'),
          _n(pay), _n(pay), _n(paye), _n(uif), _n(paye + uif, bold: true), _t(it3a ? '02' : ''),
        ]);
      }(),
    SheetRow([
      _t('Total', bold: true), for (var c = 0; c < 11; c++) const SheetCell.empty(),
      for (final f in <double Function(Emp201EmployeeMonth)>[(l) => l.dSalary, (l) => l.dSalary, (l) => l.dPaye, (l) => l.dUif, (l) => l.dPaye + l.dUif])
        _n(people.fold<double>(0, (s, y) => s + y.months.values.fold<double>(0, (a, l) => a + f(l))), bold: true),
      const SheetCell.empty(),
    ], shade: SheetShade.total),
  ]);

  // Reconciliation: certificates against the EMP201s declared (as submitted
  // on eFiling; a month not entered as submitted yet counts as worked out).
  double declaredOf(Emp201YearMonth m, double Function(Emp201Submitted) sub, double worked) => m.submitted == null ? worked : sub(m.submitted!);
  final payeM = [for (final m in months) declaredOf(m, (x) => x.paye, m.paye)];
  final sdlM = [for (final m in months) declaredOf(m, (x) => x.sdl, m.sdl)];
  final uifM = [for (final m in months) declaredOf(m, (x) => x.uif, m.uif)];
  double sum(List<double> v) => v.fold(0.0, (a, b) => a + b);
  final certs = people.expand((y) => y.months.values).toList();
  final certPaye = certs.fold<double>(0, (a, l) => a + l.dPaye);
  final certSdl = certs.fold<double>(0, (a, l) => a + l.dSdl);
  final certUif = certs.fold<double>(0, (a, l) => a + l.dUif);
  final monAbbr = DateFormat('MMM');
  bool open(int k) => months[k].lines.isEmpty && months[k].submitted == null;
  final declared = SheetTable(heading: 'EMP201 declarations per month', fixed: const [70], [
    SheetRow([_h('Tax'), for (final m in months) _h(monAbbr.format(DateTime.parse(m.month))), _h('Total')], shade: SheetShade.heading),
    // A month not paid nor submitted yet: blank.
    for (final (label, v) in [('PAYE', payeM), ('SDL', sdlM), ('UIF', uifM)])
      SheetRow([_t(label), for (var k = 0; k < months.length; k++) open(k) ? const SheetCell.empty() : _n(v[k]), _n(sum(v), bold: true)]),
    SheetRow([
      _t('Total', bold: true),
      for (var k = 0; k < months.length; k++) open(k) ? const SheetCell.empty() : _n(payeM[k] + sdlM[k] + uifM[k], bold: true),
      _n(sum(payeM) + sum(sdlM) + sum(uifM), bold: true),
    ], shade: SheetShade.total),
    SheetRow([
      _t('As'),
      for (final m in months) _t(m.submitted != null ? 'submitted' : (m.lines.isEmpty ? '' : 'worked out')),
      const SheetCell.empty(),
    ]),
  ]);
  final reconTotals = SheetTable(heading: 'Reconciliation', fixed: const [70], [
    SheetRow([_h('Tax'), _h('Certificates (IRP5/IT3(a))'), _h('EMP201 declared'), _h('Difference')], shade: SheetShade.heading),
    for (final (label, c, d) in [('PAYE', certPaye, sum(payeM)), ('SDL', certSdl, sum(sdlM)), ('UIF', certUif, sum(uifM))])
      SheetRow([_t(label), _n(c), _n(d), _diff(c - d)]),
    SheetRow([
      _t('Total', bold: true), _n(certPaye + certSdl + certUif, bold: true), _n(sum(payeM) + sum(sdlM) + sum(uifM), bold: true),
      _diff(certPaye + certSdl + certUif - sum(payeM) - sum(sdlM) - sum(uifM)),
    ], shade: SheetShade.total),
  ]);

  return [
    SheetSection(
      title,
      'The $kind EMP501: the employer, the certificates\' totals against the EMP201s declared to SARS, month by month (declared is what '
      'was entered as submitted on eFiling; a month not entered yet counts as worked out). The difference should be 0.00.',
      [_employer([('Transaction year', '$taxYear'), ('Period of reconciliation', period)]), reconTotals, declared],
    ),
    SheetSection(
      'EMP501 report -- certificates, tax year $taxYear ($range)',
      'Each employee on the EMP201 as on their IRP5/IT3(a) -- only pay declared. 3601 income, 3699 gross, 4102 PAYE, 4141 UIF '
      '(employee and employer), 4149 total. IT3(a) with reason 02: no PAYE (below the tax threshold). Income tax no: as in Employees > '
      'List (edit). Employed from/to: the first and last month paid in the period (to: the day they left, if they left).',
      [irp5],
    ),
  ];
}

/// Date of birth (yyyy-MM-dd) from a South African ID number; null for a
/// passport or anything that isn't one.
String? dobFromSaId(String? id) {
  final s = (id ?? '').replaceAll(' ', '');
  if (!RegExp(r'^\d{13}$').hasMatch(s)) return null;
  final yy = int.parse(s.substring(0, 2)), mm = int.parse(s.substring(2, 4)), dd = int.parse(s.substring(4, 6));
  if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return null;
  final year = yy > DateTime.now().year % 100 ? 1900 + yy : 2000 + yy;
  return '$year-${s.substring(2, 4)}-${s.substring(4, 6)}';
}

/// The surname for the IRP5: as on the ID, else the last word of the name.
String irp5Surname(Employee? e, String name) {
  final s = (e?.surname ?? '').trim();
  return (s.isNotEmpty ? s : _plain(name).split(RegExp(r'\s+')).last).toUpperCase();
}

/// Full names as on the ID, else the first name.
String irp5FullNames(Employee? e, String name) {
  final f = (e?.fullNames ?? '').trim();
  return (f.isNotEmpty ? f : _plain(name).split(RegExp(r'\s+')).first).toUpperCase();
}

/// A name without a note in brackets ("Queen (D)" -> "Queen").
String _plain(String name) => name.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();

/// Initials of the full names ("JOHANNES FRANCOIS" -> "JF").
String irp5Initials(Employee? e, String name) =>
    irp5FullNames(e, name).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w[0]).join();
