import 'package:flutter/material.dart';

import '../capture/capture_models.dart';
import '../capture/captured_review_screen.dart';
import '../capture/capture_repository.dart';
import '../../theme/nanini_theme.dart';

import 'package:provider/provider.dart';

import '../../core/auth/session.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../employees/employee_list_tab.dart';
import '../employees/employees_models.dart';
import 'hours_data.dart';
import 'hours_models.dart';
import 'hours_log_screen.dart';
import 'hours_repository.dart';
import 'hours_reports_screen.dart';
import 'hours_summary_screen.dart';
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
