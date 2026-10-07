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
/// (what the EMP201 needs, submitted, difference), then everyone paid, each
/// month's salary, UIF and PAYE in the three groups -- March to August,
/// then September to February -- and for the EMP501 each registered
/// employee's year as on their IRP5/IT3(a).
List<SheetSection> emp201YearSheet(int taxYear, List<Emp201YearMonth> months, {List<Farm> farms = const []}) {
  final title = 'Nanini 121 CC -- EMP201 summary, tax year $taxYear (March ${taxYear - 1} to February $taxYear)';
  final monthName = DateFormat('MMMM yyyy');
  final mon = DateFormat('MMM yy');
  SheetCell n(double? v, {bool bold = false, SheetTone tone = SheetTone.normal}) =>
      v == null ? const SheetCell.empty() : SheetCell.number((v * 100).roundToDouble() / 100, bold: bold, tone: tone);
  SheetCell t(String s, {bool bold = false}) => SheetCell.text(s, bold: bold);
  // A heading over numbers: right, like them.
  const textCols = {
    'Month', 'Tax', 'As', 'Employee', 'Farm', 'ID/passport', 'Submitted on', 'Reference', 'Due by', 'Surname', 'Initials', 'Full names', //
    'Date of birth', 'Income tax no', 'Employed from', 'Employed to', 'Certificate', 'Reason',
  };
  SheetCell h(String s) => SheetCell.text(s, bold: true, right: !textCols.contains(s));
  String farm(Employee? e) => farmShort(farms.where((f) => f.id == e?.farmId).firstOrNull);

  // 1. The months: what the EMP201 needs -- PAYE, UIF, total, due date --
  // and what was submitted on eFiling.
  final subs = months.where((m) => m.submitted != null).toList();
  double tot(double Function(Emp201YearMonth) f) => months.fold(0.0, (s, m) => s + f(m));
  double? sub(double Function(Emp201YearMonth) f) => subs.isEmpty ? null : subs.fold<double>(0.0, (s, m) => s + f(m));
  final ymd = DateFormat('yyyy-MM-dd');
  final monthsTable = SheetTable(fixed: const [70], [
    SheetRow([
      for (final h0 in ['Month', 'Employees', 'Remuneration', 'PAYE', 'UIF', 'Total payable', 'Due by', 'Submitted PAYE', 'Submitted UIF', 'Submitted total', 'Difference', 'Submitted on', 'Reference'])
        h(h0),
    ], shade: SheetShade.heading),
    for (final m in months)
      SheetRow([
        t('${monthName.format(DateTime.parse(m.month))}${m.fromHistory ? ' *' : ''}'),
        // A month not paid yet: blank.
        m.lines.isEmpty ? const SheetCell.empty() : SheetCell.number(m.employees.toDouble(), integer: true),
        for (final v in [m.salary, m.paye, m.uif]) m.lines.isEmpty ? const SheetCell.empty() : n(v),
        m.lines.isEmpty ? const SheetCell.empty() : n(m.total, bold: true),
        t(ymd.format(Emp201(DateTime.parse(m.month), const [], includeSdl: false).dueDate)),
        n(m.submitted?.paye), n(m.submitted?.uif), n(m.submitted?.total),
        n(m.difference, tone: m.difference == null ? SheetTone.normal : (m.difference!.abs() < 0.01 ? SheetTone.green : SheetTone.red)),
        m.submitted?.submittedOn == null ? const SheetCell.empty() : t(m.submitted!.submittedOn!),
        m.submitted?.reference == null ? const SheetCell.empty() : t(m.submitted!.reference!),
      ]),
    SheetRow([
      t('Total', bold: true), const SheetCell.empty(),
      n(tot((m) => m.salary), bold: true), n(tot((m) => m.paye), bold: true),
      n(tot((m) => m.uif), bold: true), n(tot((m) => m.total), bold: true), const SheetCell.empty(),
      n(sub((m) => m.submitted!.paye), bold: true), n(sub((m) => m.submitted!.uif), bold: true), n(sub((m) => m.submitted!.total), bold: true),
      n(sub((m) => m.difference!), bold: true), const SheetCell.empty(), const SheetCell.empty(),
    ], shade: SheetShade.heading),
  ]);

  // 2. Everyone, half a year per section: salary, UIF, PAYE a month.
  final people = emp201YearByEmployee(months);
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

  // 3. EMP501: each registered employee's tax year, as on the IRP5/IT3(a)
  // -- only what was declared (on EMP201, from the day registered).
  final irp5 = SheetTable(fixed: const [80], [
    SheetRow([
      for (final c in [
        'Employee', 'Surname', 'Initials', 'Full names', 'ID/passport', 'Date of birth', 'Income tax no', 'Farm', //
        'Employed from', 'Employed to', 'Months', 'Certificate', '3601 Income', '3699 Gross', '4102 PAYE', '4141 UIF', '4149 Total', 'Reason',
      ])
        h(c),
    ], shade: SheetShade.heading),
    for (final y in people[Emp201Group.declared]!)
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
          t(y.name), t(irp5Surname(e, y.name)), t(irp5Initials(e, y.name)), t(irp5FullNames(e, y.name)), t(e?.idOrPassport ?? ''),
          t(dobFromSaId(e?.idOrPassport) ?? ''), t(''), t(farm(e)),
          t(first == null ? '' : ymd.format(first)), t(last == null ? '' : ymd.format(DateTime(last.year, last.month + 1, 0))),
          SheetCell.number(ls.length.toDouble(), integer: true), t(it3a ? 'IT3(a)' : 'IRP5'),
          n(pay), n(pay), n(paye), n(uif), n(paye + uif, bold: true), t(it3a ? '02' : ''),
        ]);
      }(),
    SheetRow([
      t('Total', bold: true), for (var c = 0; c < 11; c++) const SheetCell.empty(),
      for (final f in <double Function(Emp201EmployeeMonth)>[(l) => l.dSalary, (l) => l.dSalary, (l) => l.dPaye, (l) => l.dUif, (l) => l.dPaye + l.dUif])
        n(people[Emp201Group.declared]!.fold<double>(0, (s, y) => s + y.months.values.fold<double>(0, (a, l) => a + f(l))), bold: true),
      const SheetCell.empty(),
    ], shade: SheetShade.total),
  ]);

  // 4. EMP501 reconciliation: the certificates' totals against what was
  // declared on the EMP201s (as submitted on eFiling; a month not entered
  // as submitted yet counts as worked out).
  double declaredOf(Emp201YearMonth m, double Function(Emp201Submitted) sub, double worked) => m.submitted == null ? worked : sub(m.submitted!);
  final payeM = [for (final m in months) declaredOf(m, (x) => x.paye, m.paye)];
  final sdlM = [for (final m in months) declaredOf(m, (x) => x.sdl, m.sdl)];
  final uifM = [for (final m in months) declaredOf(m, (x) => x.uif, m.uif)];
  double sum(List<double> v) => v.fold(0.0, (a, b) => a + b);
  final certs = people[Emp201Group.declared]!.expand((y) => y.months.values).toList();
  final certPaye = certs.fold<double>(0, (a, l) => a + l.dPaye);
  final certSdl = certs.fold<double>(0, (a, l) => a + l.dSdl);
  final certUif = certs.fold<double>(0, (a, l) => a + l.dUif);
  final monAbbr = DateFormat('MMM');
  bool open(int k) => months[k].lines.isEmpty && months[k].submitted == null;
  final declared = SheetTable(heading: 'EMP201 declarations per month', fixed: const [70], [
    SheetRow([h('Tax'), for (final m in months) h(monAbbr.format(DateTime.parse(m.month))), h('Total')], shade: SheetShade.heading),
    // A month not paid nor submitted yet: blank.
    for (final (label, v) in [('PAYE', payeM), ('SDL', sdlM), ('UIF', uifM)])
      SheetRow([t(label), for (var k = 0; k < months.length; k++) open(k) ? const SheetCell.empty() : n(v[k]), n(sum(v), bold: true)]),
    SheetRow([
      t('Total', bold: true),
      for (var k = 0; k < months.length; k++) open(k) ? const SheetCell.empty() : n(payeM[k] + sdlM[k] + uifM[k], bold: true),
      n(sum(payeM) + sum(sdlM) + sum(uifM), bold: true),
    ], shade: SheetShade.total),
    SheetRow([
      t('As'),
      for (final m in months) t(m.submitted != null ? 'submitted' : (m.lines.isEmpty ? '' : 'worked out')),
      const SheetCell.empty(),
    ]),
  ]);
  SheetCell diff(double v) => n(v, bold: true, tone: v.abs() < 0.01 ? SheetTone.green : SheetTone.red);
  final reconTotals = SheetTable(heading: 'Reconciliation', fixed: const [70], [
    SheetRow([h('Tax'), h('Certificates (IRP5/IT3(a))'), h('EMP201 declared'), h('Difference')], shade: SheetShade.heading),
    for (final (label, c, d) in [('PAYE', certPaye, sum(payeM)), ('SDL', certSdl, sum(sdlM)), ('UIF', certUif, sum(uifM))])
      SheetRow([t(label), n(c), n(d), diff(c - d)]),
    SheetRow([
      t('Total', bold: true), n(certPaye + certSdl + certUif, bold: true), n(sum(payeM) + sum(sdlM) + sum(uifM), bold: true),
      diff(certPaye + certSdl + certUif - sum(payeM) - sum(sdlM) - sum(uifM)),
    ], shade: SheetShade.total),
  ]);

  return [
    SheetSection(
      title,
      'EMP201 per month: what to submit -- PAYE, UIF (the employees\' and the employer\'s together) and the total, due by the date '
      'shown -- then what was submitted on eFiling and the difference (submitted less worked out). Only employees on the EMP201 count. '
      '* From the old salary summary.',
      [monthsTable],
    ),
    SheetSection(title, 'Per employee, March to August ${taxYear - 1}: salary, UIF and PAYE each month.', employees(months.sublist(0, 6))),
    SheetSection(title, 'Per employee, September ${taxYear - 1} to February $taxYear: salary, UIF and PAYE each month.', employees(months.sublist(6))),
    SheetSection(
      title,
      'EMP501: each employee on the EMP201, the tax year as on their IRP5/IT3(a) -- only pay declared. 3601 income, 3699 gross, '
      '4102 PAYE, 4141 UIF (employee and employer), 4149 total. IT3(a) with reason 02: no PAYE (below the tax threshold). '
      'Income tax no: fill in (not kept in the app). Employed from/to: the first and last month paid this tax year.',
      [irp5],
    ),
    SheetSection(
      title,
      'EMP501 reconciliation: the total of all the IRP5/IT3(a) certificates against the EMP201s declared to SARS, month by month. '
      'Declared is what was entered as submitted on eFiling; a month not entered yet counts as worked out. The difference should be 0.00.',
      [reconTotals, declared],
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
