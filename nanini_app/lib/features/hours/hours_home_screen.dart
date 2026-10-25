import 'package:flutter/material.dart';

import '../capture/capture_models.dart';
import '../capture/captured_review_screen.dart';
import '../capture/capture_repository.dart';
import '../../theme/nanini_theme.dart';

import 'package:provider/provider.dart';

import '../../core/auth/session.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/toast.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../employees/employee_list_tab.dart';
import '../employees/employees_models.dart';
import 'hours_data.dart';
import 'hours_models.dart';
import 'hours_log_screen.dart';
import 'hours_repository.dart';
import 'hours_reports_screen.dart';
import 'hours_summary_screen.dart';
import 'hours_payslip_preview.dart' show showPdfPreview;
import 'timesheet_pdf.dart';
import 'pay_run.dart';
import 'pay_widgets.dart';

/// Employees (hub tile): Summary -- pay since the last pay per worker and
/// farm, and running payroll -- List (every employee's details, farms and
/// groups) and Reports. The farm managers'
/// check before pay (hours, tariffs, extra pay, deductions) is done on their
/// phones in Nanini Capture > Payslips and arrives in the captured inbox.
class HoursHomeScreen extends StatefulWidget {
  const HoursHomeScreen({super.key});
  @override
  State<HoursHomeScreen> createState() => _HoursHomeScreenState();
}

class _HoursHomeScreenState extends State<HoursHomeScreen> {
  final repo = HoursRepository();
  late final data = HoursData(repo);
  int index = 0;
  String? farmId;
  DateTime payUpTo = DateTime.now();

  @override
  void dispose() {
    data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isManager = context.watch<Session>().isAdmin;
    final items = [
      const BottomNavigationBarItem(icon: Icon(Icons.summarize_outlined), label: 'Summary'),
      const BottomNavigationBarItem(icon: Icon(Icons.people_alt_outlined), label: 'List'),
      if (isManager) const BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Reports'),
    ];
    final safeIndex = index >= items.length ? 0 : index;

    return Scaffold(
      appBar: NaniniAppBar(
        title: 'Employees',
        actions: [
          IconButton(
            tooltip: 'Add hours',
            icon: const Icon(Icons.more_time),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: const NaniniAppBar(title: 'Add hours'),
                  body: HoursLogScreen(repo: repo),
                ),
              ),
            ),
          ),
          // A month's blank timesheets for a farm, filled in by hand on the farm.
          IconButton(
            tooltip: 'Print timesheets',
            icon: const Icon(Icons.print_outlined),
            onPressed: () => runOnce('hours_home.timesheets', () => _printTimesheets(context)),
          ),
          // Hours, payslip checks and employee details sent from phones.
          const CapturedInboxButton(title: 'Employees', modules: [...CaptureModule.hoursModules, ...CaptureModule.employeeModules]),
        ],
      ),
      body: safeIndex == 2
          ? HoursReportsScreen(repo: repo)
          : safeIndex == 1
          ? const EmployeeListTab()
          : ListenableBuilder(
              listenable: data,
              builder: (context, _) {
                // The Members tab (salaries) is for admins only.
                final scope = farmId == kMembersScope && !isManager ? null : farmId;
                // Members are paid once a month (automatically on the last
                // Friday): already paid in pay up to's month, nothing to run.
                final monthStart = '${toDateStr(payUpTo).substring(0, 7)}-01';
                bool paidThisMonth(String id) => (data.payslips ?? const <Payslip>[]).any((p) => p.employeeId == id && p.periodEnd.compareTo(monthStart) >= 0);
                final lines = data.loaded
                    ? buildPayRun(
                        payUpTo: toDateStr(payUpTo),
                        employees: data.employees!,
                        entries: data.entries!,
                        kgEntries: data.kgEntries!,
                        purchases: data.purchases!,
                        payslips: data.payslips!,
                        extras: data.extras,
                      ).where((l) => scope == kMembersScope ? l.employee.isMember && !paidThisMonth(l.employee.id) : !l.employee.isMember && (scope == null || l.employee.farmId == scope)).toList()
                    : <PayLine>[];
                final members = isManager ? (data.employees ?? const <Employee>[]).where((e) => e.isMember).toList() : <Employee>[];
                return HoursSummaryScreen(
                  data: data,
                  lines: lines,
                  scopeBar: Column(mainAxisSize: MainAxisSize.min, children: [
                    const _WaitingNote(),
                    PayScopeBar(
                    farms: data.farms,
                    farmId: scope,
                    payUpTo: payUpTo,
                    onFarm: (f) => setState(() => farmId = f),
                    onPayUpTo: (d) => setState(() => payUpTo = d),
                    showMembers: members.isNotEmpty,
                  ),
                  ]),
                  memberInfo: scope == kMembersScope ? members : null,
                  payUpTo: payUpTo,
                  farmName: scope == null ? null : scope == kMembersScope ? 'Members' : farmShort(data.farms.where((f) => f.id == scope).firstOrNull),
                );
              },
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: safeIndex,
        onTap: (i) async {
          if (i == 2 && !isManager) {
            if (!await requireAdmin(context)) return;
          }
          setState(() => index = i);
        },
        items: items,
      ),
    );
  }

  /// A month's blank timesheets for a farm -- ordinary work, and a sheet per
  /// work group with its own tariff -- to print (nothing is saved).
  Future<void> _printTimesheets(BuildContext context) async {
    final farms = data.farms;
    final employees = data.employees;
    if (farms.isEmpty || employees == null) {
      showToast(context, 'Still loading -- try again in a moment.');
      return;
    }
    final List<EmployeeGroup> groups;
    try {
      groups = await data.employeesRepo.watchGroups().first;
    } catch (e) {
      if (context.mounted) showToast(context, 'Could not load the work groups: $e', isError: true);
      return;
    }
    // This month, or next month from the 20th (printed before it starts).
    final now = DateTime.now();
    var month = now.day >= 20 ? DateTime(now.year, now.month + 1) : DateTime(now.year, now.month);
    var farm = farms.where((f) => f.id == farmId).firstOrNull ?? farms.first;
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final sheets = timesheetsFor(farm, employees, groups, month);
          return AlertDialog(
            title: const Text('Print timesheets'),
            content: SizedBox(
              width: 380,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DropdownButtonFormField<String>(
                  initialValue: farm.id,
                  decoration: const InputDecoration(labelText: 'Farm'),
                  items: [for (final f in farms) DropdownMenuItem(value: f.id, child: Text(farmShort(f)))],
                  onChanged: (v) => setLocal(() => farm = farms.firstWhere((f) => f.id == v)),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<DateTime>(
                  initialValue: month,
                  decoration: const InputDecoration(labelText: 'Month'),
                  items: [
                    for (var i = -1; i <= 2; i++)
                      if (DateTime(now.year, now.month + i) case final m)
                        DropdownMenuItem(value: m, child: Text('${names[m.month - 1]} ${m.year}')),
                  ],
                  onChanged: (v) => setLocal(() => month = v ?? month),
                ),
                const SizedBox(height: 12),
                for (final t in sheets) Text('${t.title}: ${t.workers.length} workers', style: const TextStyle(color: NaniniColors.muted)),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Show')),
            ],
          );
        },
      ),
    );
    if (ok != true || !context.mounted) return;
    final label = '${names[month.month - 1]} ${month.year}';
    await showPdfPreview(
      context,
      () => buildTimesheetsPdf(farmName: farmShort(farm), farmId: farm.id, month: month, sheets: timesheetsFor(farm, employees, groups, month)),
      landscape: true,
      title: 'Timesheets: ${farmShort(farm)} $label',
    );
  }
}

/// Hours, picking and payslip checks sent from the phones but not yet
/// approved aren't in Summary: say so, with the way to the inbox.
class _WaitingNote extends StatelessWidget {
  const _WaitingNote();

  static const _modules = [...CaptureModule.hoursModules];

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CaptureEntry>>(
        stream: CaptureRepository().watchPending(_modules),
        builder: (context, snap) {
          final n = snap.data?.length ?? 0;
          if (n == 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              color: NaniniColors.amber.withValues(alpha: 0.15),
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.move_to_inbox_outlined, color: NaniniColors.amber),
                title: Text('$n from the phones still to approve'),
                subtitle: const Text('Picking and payslip checks only count here once approved (hours from the phones go in by themselves).'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CapturedReviewScreen(title: 'Employees', modules: _modules)),
                ),
              ),
            ),
          );
        },
      );
}
