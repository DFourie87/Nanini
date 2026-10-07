import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'emp201_year_screen.dart';
import 'hours_models.dart';
import 'hours_payslip_preview.dart';
import 'hours_repository.dart';
import 'pay_widgets.dart';
import 'payroll_month.dart';
import '../../core/run_once.dart';

final _monthFmt = DateFormat('MMMM yyyy');
final _dueFmt = DateFormat('EEEE d MMMM yyyy');
const _kSdlPref = 'hours.sdl';

/// Hours > Reports (admins): a calendar month's pay for all farms together,
/// that month's EMP201 for SARS, and the payslip history (each run printable
/// as a summary + payslips). Everything by the date pay was paid.
class HoursReportsScreen extends StatefulWidget {
  const HoursReportsScreen({super.key, required this.repo});
  final HoursRepository repo;
  @override
  State<HoursReportsScreen> createState() => _HoursReportsScreenState();
}

class _HoursReportsScreenState extends State<HoursReportsScreen> {
  final employeesRepo = EmployeesRepository();
  late final _employees = employeesRepo.watchEmployees();
  late final _payslips = widget.repo.watchPayslips();
  late final _entries = widget.repo.watchEntries();
  List<Farm> farms = [];

  /// Default: last month until the 7th (its EMP201 is still due), then this one.
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month - (DateTime.now().day <= 7 ? 1 : 0));
  bool? sdl;

  @override
  void initState() {
    super.initState();
    employeesRepo.fetchFarms().then((f) {
      if (mounted) setState(() => farms = f);
    });
    SharedPreferences.getInstance().then((p) {
      if (mounted && p.containsKey(_kSdlPref)) setState(() => sdl = p.getBool(_kSdlPref));
    });
  }

  /// Members of Nanini 121 CC (only admins get them): their own group in
  /// every summary and run, never mixed in with a farm's workers.
  static const _kMembers = '__members__';
  Set<String> _memberIds = {};
  String? groupOf(Payslip p) => _memberIds.contains(p.employeeId) ? _kMembers : p.farmId;

  String farmName(String? id) => id == _kMembers ? 'Members' : farmShort(farms.where((f) => f.id == id).firstOrNull);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Employee>>(
      stream: _employees,
      builder: (context, empSnap) {
        return StreamBuilder<List<Payslip>>(
          stream: _payslips,
          builder: (context, paySnap) {
            final employees = empSnap.data ?? [];
            final payslips = paySnap.data ?? [];
            _memberIds = {for (final e in employees) if (e.isMember) e.id};
            final monthSlips = paidInMonth(payslips, month);
            final all = PayTotals(monthSlips);
            final farmIds = {for (final p in monthSlips) groupOf(p)}.toList()
              ..sort((a, b) => farms.indexWhere((f) => f.id == a).compareTo(farms.indexWhere((f) => f.id == b)));
            // Runs paid up to 3 days after the month are in its EMP201 (and
            // not the next one's) -- only those declared to SARS count.
            final empSlips = emp201Slips(payslips, month);
            final declared = declaredSlips(empSlips, employees);
            // SDL is only for a payroll over R500 000 a year -- guessed from
            // this month until switched on or off.
            final includeSdl = sdl ?? PayTotals(declared).gross * 12 > 500000;
            final emp = Emp201(month, declared, includeSdl: includeSdl);
            final groups = emp201Summary(empSlips, employees);
            final runs = groupRuns(payslips, groupOf: groupOf);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left)),
                    Expanded(child: Text(_monthFmt.format(month), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge)),
                    IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right)),
                  ],
                ),
                const SizedBox(height: 8),
                FarmSection(
                  title: 'Pay -- all farms',
                  totals: '${all.employees.length} workers',
                  children: [
                    if (monthSlips.isEmpty)
                      const Padding(padding: EdgeInsets.all(16), child: Text('Nothing paid this month.', style: TextStyle(color: NaniniColors.muted))),
                    for (final id in farmIds)
                      () {
                        final t = PayTotals(monthSlips.where((p) => groupOf(p) == id));
                        return ListTile(
                          title: Text(farmName(id)),
                          subtitle: Text('${t.employees.length} workers · gross ${fmtR(t.gross)} · deductions ${fmtR(t.deductions)}'),
                          trailing: Text(fmtR(t.nett), style: const TextStyle(fontWeight: FontWeight.w700)),
                        );
                      }(),
                    if (monthSlips.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Column(
                          children: [
                            AmountRow('Gross', all.gross),
                            AmountRow('PAYE', -all.paye),
                            AmountRow('UIF (employees)', -all.uif),
                            AmountRow('Rent', -all.rent),
                            AmountRow('Loans', -all.loan),
                            AmountRow('Tuck shop', -all.tuckshop),
                            const Divider(),
                            AmountRow('Nett paid', all.nett, bold: true),
                          ],
                        ),
                      ),
                  ],
                ),
                _HoursByFarm(entries: _entries, month: month, employees: employees, farms: farms, farmName: farmName),
                _Emp201Summary(groups: groups, farms: farms, period: emp.period),
                FarmSection(
                  title: 'EMP201 -- ${emp.period}',
                  totals: fmtR(emp.total),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AmountRow('PAYE', emp.paye),
                          AmountRow('UIF -- employees (1%)', emp.uifEmployee),
                          AmountRow('UIF -- employer (1%)', emp.uifEmployer),
                          AmountRow('SDL (1%)', emp.sdl),
                          AmountRow('ETI', -emp.eti),
                          const Divider(),
                          AmountRow('Total to pay SARS', emp.total, bold: true),
                          const SizedBox(height: 6),
                          Text('Submit and pay by ${_dueFmt.format(emp.dueDate)}', style: const TextStyle(fontWeight: FontWeight.w700, color: NaniniColors.rustDark)),
                          Text('${emp.employees} employees · remuneration ${fmtR(emp.remuneration)}', style: const TextStyle(color: NaniniColors.muted)),
                          Text('Payroll runs paid ${fmtDateDisplay(emp.paidFrom)} to ${fmtDateDisplay(emp.paidTo)}',
                              style: const TextStyle(color: NaniniColors.muted)),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      value: includeSdl,
                      onChanged: (v) async {
                        setState(() => sdl = v);
                        (await SharedPreferences.getInstance()).setBool(_kSdlPref, v);
                      },
                      title: const Text('Include SDL'),
                      subtitle: const Text('Only if the payroll is over R500 000 a year'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => Emp201YearScreen(payslips: payslips, employees: employees, includeSdl: includeSdl),
                        )),
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('EMP201 tax year -- submitted vs worked out'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'From payslips paid this month. ETI is not worked out here, and UIF is worked out on at most R17 712 a month '
                        '(the ceiling) -- check before submitting on eFiling. A public holiday on the due date isn\'t allowed for.',
                        style: TextStyle(color: NaniniColors.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: monthSlips.isEmpty ? null : () => _printMonth(monthSlips, farmIds, all, emp),
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Print month'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: monthSlips.isEmpty ? null : () => runOnce('hours_reports_screen.1', () => _exportMonthCsv(monthSlips, employees, emp)),
                        icon: const Icon(Icons.download),
                        label: const Text('Export CSV'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Payslip history', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (runs.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No payroll runs yet.'))
                else
                  for (final run in runs)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        title: Text('${farmName(run.farmId)} · ${fmtDateDisplay(run.periodStart)} – ${fmtDateDisplay(run.periodEnd)}'),
                        subtitle: Text('Paid ${fmtDateDisplay(run.paidDate)} · ${run.slips.length} workers · ${fmtR(run.totals.nett)} nett'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => runOnce('hours_reports_screen.2', () => showPdfPreview(
                                  context,
                                  () => buildRunPdf(farmName: farmName(run.farmId), slips: _withEmployees(run.slips, employees)),
                                  title: 'Payslips: ${farmName(run.farmId)}',
                                )),
                                icon: const Icon(Icons.print_outlined),
                                label: const Text('Print summary + payslips'),
                              ),
                            ),
                          ),
                          for (final p in run.slips)
                            ListTile(
                              dense: true,
                              title: Text(employees.where((e) => e.id == p.employeeId).firstOrNull?.displayName ?? 'Unknown'),
                              subtitle: Text('Nett ${fmtR(p.nett)}'),
                              trailing: const Icon(Icons.picture_as_pdf_outlined),
                              onTap: () {
                                final emp = employees.where((e) => e.id == p.employeeId).firstOrNull;
                                if (emp != null) showPayslipPreview(context, p, emp);
                              },
                            ),
                        ],
                      ),
                    ),
              ],
            );
          },
        );
      },
    );
  }

  /// Payslips with their employee (one since removed shows as "Unknown").
  List<(Payslip, Employee)> _withEmployees(List<Payslip> slips, List<Employee> employees) => [
        for (final p in slips) (p, employees.where((e) => e.id == p.employeeId).firstOrNull ?? Employee(id: p.employeeId, firstName: 'Unknown', lastName: '')),
      ];

  List<String> _cells(PayTotals t) => [
        '${t.employees.length}',
        t.hours.toStringAsFixed(1),
        fmtR(t.gross),
        fmtR(t.paye),
        fmtR(t.uif),
        fmtR(t.rent),
        fmtR(t.loan),
        fmtR(t.tuckshop),
        fmtR(t.nett),
      ];

  List<(String, String)> _emp201Lines(Emp201 e) => [
        ('Period', e.period),
        ('Payroll runs paid', '${fmtDateDisplay(e.paidFrom)} to ${fmtDateDisplay(e.paidTo)}'),
        ('Employees', '${e.employees}'),
        ('Remuneration', fmtRCents(e.remuneration)),
        ('PAYE', fmtRCents(e.paye)),
        ('UIF -- employees (1%)', fmtRCents(e.uifEmployee)),
        ('UIF -- employer (1%)', fmtRCents(e.uifEmployer)),
        ('SDL (1%)${e.includeSdl ? '' : ' -- not included'}', fmtRCents(e.sdl)),
        ('ETI', fmtRCents(e.eti)),
        ('Total payable to SARS', fmtRCents(e.total)),
      ];

  void _printMonth(List<Payslip> slips, List<String?> farmIds, PayTotals all, Emp201 e) {
    showPdfPreview(
      context,
      () => buildMonthPdf(
        monthLabel: _monthFmt.format(month),
        farmRows: [for (final id in farmIds) (farmName(id), _cells(PayTotals(slips.where((p) => groupOf(p) == id))))],
        totalRow: _cells(all),
        emp201: _emp201Lines(e),
        dueLine: 'Submit and pay by ${_dueFmt.format(e.dueDate)}',
      ),
      title: 'Pay summary ${_monthFmt.format(month)}',
    );
  }

  Future<void> _exportMonthCsv(List<Payslip> slips, List<Employee> employees, Emp201 e) async {
    final rows = <List<dynamic>>[
      ['Pay summary', _monthFmt.format(month)],
      [],
      ['Farm', 'Employee', 'ID/Passport', 'EMP201', 'Period', 'Paid', 'Hours', 'Gross', 'PAYE', 'UIF', 'Rent', 'Loan', 'Tuck shop', 'Nett'],
      for (final p in slips)
        () {
          final emp = employees.where((x) => x.id == p.employeeId).firstOrNull;
          return [
            farmName(groupOf(p)),
            emp?.legalName ?? 'Unknown',
            emp?.idOrPassport ?? '',
            emp201GroupOf(emp).label,
            '${p.periodStart} to ${p.periodEnd}',
            p.paidDate,
            p.hoursWorked,
            p.gross,
            p.paye,
            p.uif,
            p.rent,
            p.loan,
            p.tuckshopDeduction,
            p.nett,
          ];
        }(),
      [],
      ['EMP201'],
      for (final (k, v) in _emp201Lines(e)) [k, v],
      ['Due by', toDateStr(e.dueDate)],
    ];
    await Share.share(const ListToCsvConverter().convert(rows), subject: 'pay-${e.period}.csv');
  }
}

/// Hours worked on each farm in the month -- by the farm the day was worked
/// on, whoever's farm pays the worker (people move between farms). Entries
/// from before the farm was recorded count at the worker's own farm.
class _HoursByFarm extends StatelessWidget {
  const _HoursByFarm({required this.entries, required this.month, required this.employees, required this.farms, required this.farmName});
  final Stream<List<HoursEntry>> entries;
  final DateTime month;
  final List<Employee> employees;
  final List<Farm> farms;
  final String Function(String?) farmName;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HoursEntry>>(
      stream: entries,
      builder: (context, snap) {
        final byFarm = hoursByFarm(snap.data ?? [], employees, month);
        final ids = byFarm.keys.toList()..sort((a, b) => farms.indexWhere((f) => f.id == a).compareTo(farms.indexWhere((f) => f.id == b)));
        final total = byFarm.values.fold<double>(0, (s, v) => s + v.hours);
        return FarmSection(
          title: 'Hours worked per farm',
          totals: fmtHours((total * 100).roundToDouble() / 100),
          children: [
            if (ids.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No hours this month.', style: TextStyle(color: NaniniColors.muted))),
            for (final id in ids)
              ListTile(
                title: Text(farmName(id)),
                subtitle: Text([
                  '${byFarm[id]!.workers.length} workers · cost ${fmtR(byFarm[id]!.cost)}',
                  if (byFarm[id]!.visitors > 0) '${fmtHours((byFarm[id]!.visitors * 100).roundToDouble() / 100)} by workers from other farms',
                ].join('\n')),
                trailing: Text(fmtHours((byFarm[id]!.hours * 100).roundToDouble() / 100), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('By the farm the work was done on, by date worked. Pay above is by each worker\'s own farm.',
                  style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
            ),
          ],
        );
      },
    );
  }
}

/// EMP201 summary, all farms in one: the month's EMP201 pay per employee in
/// three groups -- on the EMP201 (what goes to SARS), and not on it with or
/// without an ID/passport on file.
class _Emp201Summary extends StatelessWidget {
  const _Emp201Summary({required this.groups, required this.farms, required this.period});
  final Map<Emp201Group, List<Emp201SummaryLine>> groups;
  final List<Farm> farms;
  final String period;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: NaniniColors.muted);
    double sum(List<Emp201SummaryLine> ls, double Function(Emp201SummaryLine) f) => ls.fold(0.0, (s, l) => s + f(l));
    final everyone = [for (final g in groups.values) ...g];
    return FarmSection(
      title: 'EMP201 summary -- all farms',
      totals: '${everyone.length} employees',
      children: [
        for (final g in Emp201Group.values)
          () {
            final ls = groups[g]!;
            // Not declared, yet UIF or PAYE taken off their pay.
            final withheld = g != Emp201Group.declared ? ls.where((l) => l.uif > 0 || l.paye > 0).toList() : const <Emp201SummaryLine>[];
            return ExpansionTile(
              title: Text(g.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${ls.length} employees · pay ${fmtR(sum(ls, (l) => l.gross))} · UIF ${fmtRCents(sum(ls, (l) => l.uif))} · PAYE ${fmtRCents(sum(ls, (l) => l.paye))}'
                '${withheld.isEmpty ? '' : '\n${withheld.length} with UIF or PAYE taken off but not declared'}',
                style: TextStyle(color: withheld.isEmpty ? NaniniColors.muted : NaniniColors.red),
              ),
              children: [
                if (ls.isEmpty) const ListTile(dense: true, title: Text('Nobody this month.', style: muted)),
                for (final l in ls)
                  ListTile(
                    dense: true,
                    title: Text(l.name),
                    subtitle: Text(
                      [
                        farmShort(farms.where((f) => f.id == l.employee?.farmId).firstOrNull),
                        if (g != Emp201Group.notDeclaredNoId) 'ID ${l.employee?.idOrPassport ?? '-'}',
                        'UIF ${fmtRCents(l.uif)}',
                        'PAYE ${fmtRCents(l.paye)}',
                      ].join(' · '),
                      style: TextStyle(color: g != Emp201Group.declared && (l.uif > 0 || l.paye > 0) ? NaniniColors.red : NaniniColors.muted),
                    ),
                    trailing: Text(fmtR(l.gross), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            );
          }(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            'Pay in the $period EMP201 (runs paid up to 3 days after the month count for it). Only "On EMP201" goes to SARS -- '
            'tick it per employee in Employees > List (edit).',
            style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
