import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/session.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/widgets/nanini_app_bar.dart';
import 'hours_repository.dart';
import 'hours_log_screen.dart';
import 'hours_worked_screen.dart';
import 'hours_reports_screen.dart';

class HoursHomeScreen extends StatefulWidget {
  const HoursHomeScreen({super.key});
  @override
  State<HoursHomeScreen> createState() => _HoursHomeScreenState();
}

class _HoursHomeScreenState extends State<HoursHomeScreen> {
  final repo = HoursRepository();
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final isManager = context.watch<Session>().isAdmin;
    final pages = [
      HoursLogScreen(repo: repo),
      HoursWorkedScreen(repo: repo),
      if (isManager) HoursReportsScreen(repo: repo),
    ];
    final items = [
      const BottomNavigationBarItem(icon: Icon(Icons.edit_calendar_outlined), label: 'Log'),
      const BottomNavigationBarItem(icon: Icon(Icons.access_time), label: 'Hours worked'),
      if (isManager) const BottomNavigationBarItem(icon: Icon(Icons.summarize_outlined), label: 'Reports'),
    ];
    final safeIndex = index >= pages.length ? 0 : index;

    return Scaffold(
      appBar: const NaniniAppBar(title: 'Hours'),
      body: pages[safeIndex],
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
