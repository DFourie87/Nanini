import 'package:flutter/material.dart';
import '../capture/capture_models.dart';
import '../capture/captured_review_screen.dart';
import 'package:provider/provider.dart';
import '../../core/auth/session.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../core/widgets/nanini_app_bar.dart';
import 'hours_data.dart';
import 'hours_repository.dart';
import 'hours_reports_screen.dart';
import 'hours_summary_screen.dart';
import 'hours_work_screen.dart';
import 'pay_run.dart';
import 'pay_widgets.dart';

class HoursHomeScreen extends StatefulWidget {
  const HoursHomeScreen({super.key});
  @override
  State<HoursHomeScreen> createState() => _HoursHomeScreenState();
}

class _HoursHomeScreenState extends State<HoursHomeScreen> {
  final repo = HoursRepository();
  late final data = HoursData(repo);
  int index = 0;

  // Shared by Work and Summary, so the summary is of exactly what was checked.
  WorkStep step = WorkStep.hours;
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
      const BottomNavigationBarItem(icon: Icon(Icons.fact_check_outlined), label: 'Work'),
      const BottomNavigationBarItem(icon: Icon(Icons.summarize_outlined), label: 'Summary'),
      if (isManager) const BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Reports'),
    ];
    final safeIndex = index >= items.length ? 0 : index;

    return Scaffold(
      appBar: NaniniAppBar(
        title: 'Hours',
        actions: const [CapturedInboxButton(title: 'Hours', modules: CaptureModule.hoursModules)],
      ),
      body: safeIndex == 2
          ? HoursReportsScreen(repo: repo)
          : ListenableBuilder(
              listenable: data,
              builder: (context, _) {
                final lines = data.loaded
                    ? buildPayRun(
                        payUpTo: toDateStr(payUpTo),
                        employees: data.employees!,
                        entries: data.entries!,
                        kgEntries: data.kgEntries!,
                        purchases: data.purchases!,
                        payslips: data.payslips!,
                      ).where((l) => farmId == null || l.employee.farmId == farmId).toList()
                    : <PayLine>[];
                final scopeBar = PayScopeBar(
                  farms: data.farms,
                  farmId: farmId,
                  payUpTo: payUpTo,
                  onFarm: (f) => setState(() => farmId = f),
                  onPayUpTo: (d) => setState(() => payUpTo = d),
                );
                return safeIndex == 0
                    ? HoursWorkScreen(
                        data: data,
                        lines: lines,
                        scopeBar: scopeBar,
                        step: step,
                        onStep: (s) => setState(() => step = s),
                        onDone: () => setState(() => index = 1),
                      )
                    : HoursSummaryScreen(
                        data: data,
                        lines: lines,
                        scopeBar: scopeBar,
                        payUpTo: payUpTo,
                        farmName: farmId == null ? null : farmShort(data.farms.where((f) => f.id == farmId).firstOrNull),
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
