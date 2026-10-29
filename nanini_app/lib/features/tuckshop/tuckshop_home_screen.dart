import 'package:flutter/material.dart';
import '../capture/capture_models.dart';
import '../capture/captured_review_screen.dart';
import 'package:provider/provider.dart';
import '../../core/auth/session.dart';
import '../../core/auth/app_modules.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'tuckshop_repository.dart';
import 'tuckshop_stock_screen.dart';
import 'tuckshop_purchases_screen.dart';
import 'tuckshop_log_screen.dart';
import 'tuckshop_reports_screen.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../hours/hours_payslip_preview.dart' show showPdfPreview;
import '../hours/hours_repository.dart';
import '../hours/pay_widgets.dart' show farmShort;
import '../hours/timesheet_pdf.dart';
import 'tuckshop_models.dart';

class TuckshopHomeScreen extends StatefulWidget {
  const TuckshopHomeScreen({super.key});
  @override
  State<TuckshopHomeScreen> createState() => _TuckshopHomeScreenState();
}

class _TuckshopHomeScreenState extends State<TuckshopHomeScreen> {
  final repo = TuckshopRepository();
  final employeesRepo = EmployeesRepository();
  int navIndex = 0;
  List<Farm> farms = [];
  String? selectedFarmId;

  @override
  void initState() {
    super.initState();
    employeesRepo.fetchFarms().then((all) {
      if (!mounted) return;
      final filtered = all.where((f) => f.name.contains('Limpopodraai') || f.name.contains('Haaskraal')).toList();
      setState(() {
        farms = filtered;
        selectedFarmId = filtered.isNotEmpty ? filtered.first.id : null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final farmName = farms.where((f) => f.id == selectedFarmId).firstOrNull?.name;
    // An admin, or someone given this farm's tuck shop in Manage users (e.g.
    // Haaskraal's): stock, items and reports for this farm.
    final isManager = session.isAdmin || session.can(farmRight('tuckshop', farmName));

    final pages = [
      TuckshopStockScreen(repo: repo, farmId: selectedFarmId),
      TuckshopPurchasesScreen(repo: repo, farmId: selectedFarmId),
      TuckshopLogScreen(repo: repo, farmId: selectedFarmId),
      if (isManager) TuckshopReportsScreen(repo: repo, farmId: selectedFarmId),
    ];
    final items = [
      const BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), label: 'Stock'),
      const BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'Purchases'),
      const BottomNavigationBarItem(icon: Icon(Icons.add_shopping_cart), label: 'Log'),
      if (isManager) const BottomNavigationBarItem(icon: Icon(Icons.summarize_outlined), label: 'Reports'),
    ];
    final safeIndex = navIndex >= pages.length ? 0 : navIndex;

    return Scaffold(
      appBar: NaniniAppBar(
        title: 'Tuck Shop',
        actions: [
          if (isManager)
            IconButton(icon: const Icon(Icons.kitchen_outlined), tooltip: 'Print fridge sheets', onPressed: () => _printFridgeSheets(context)),
          const CapturedInboxButton(title: 'Tuck Shop', modules: CaptureModule.tuckshopModules),
        ],
      ),
      body: Column(
        children: [
          if (farms.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: farms
                    .map((f) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: ChoiceChip(
                            label: Text(f.name),
                            selected: selectedFarmId == f.id,
                            onSelected: (_) => setState(() => selectedFarmId = f.id),
                          ),
                        ))
                    .toList(),
              ),
            ),
          Expanded(child: pages[safeIndex]),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: safeIndex,
        onTap: (i) async {
          if (i == 3 && !isManager) {
            if (!await requireAdmin(context)) return;
          }
          setState(() => navIndex = i);
        },
        items: items,
      ),
    );
  }

  /// The fridge sheets to print (nothing is saved): per item (wors, chicken)
  /// a page like the timesheets -- this farm's workers (with those in its work
  /// groups, the potatoes), 20 empty lines, a box per day from the day after
  /// the last payroll to the month's last Friday, and a QR code per page.
  Future<void> _printFridgeSheets(BuildContext context) async {
    final farm = farms.where((f) => f.id == selectedFarmId).firstOrNull;
    if (farm == null) return;
    final List<TuckshopItem> items;
    final List<Employee> employees;
    final List<EmployeeGroup> groups;
    final List<String> paidUpTo;
    try {
      items = [for (final i in await repo.watchItems().first) if (i.farmId == farm.id && !i.archived) i]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      employees = await employeesRepo.watchEmployees().first;
      groups = await employeesRepo.watchGroups().first;
      paidUpTo = [for (final p in await HoursRepository().watchPayslips().first) if (p.farmId == farm.id) p.periodEnd];
    } catch (e) {
      if (context.mounted) showToast(context, 'Could not load the stock and workers: $e', isError: true);
      return;
    }
    if (items.isEmpty) {
      if (context.mounted) showToast(context, 'No stock items for ${farmShort(farm)} yet', isError: true);
      return;
    }
    // Wors and chicken ticked to start with.
    final chosen = {for (final i in items) if (RegExp('wors|chicken|hoender', caseSensitive: false).hasMatch(i.name)) i.id};
    final now = DateTime.now();
    var month = now.day >= 20 ? DateTime(now.year, now.month + 1) : DateTime(now.year, now.month);
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final workers = timesheetsFor(farm, employees, groups, month).single.workers;
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Print fridge sheets'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DropdownButtonFormField<DateTime>(
                  initialValue: month,
                  decoration: const InputDecoration(labelText: 'Month'),
                  items: [
                    for (var i = -1; i <= 2; i++)
                      if (DateTime(now.year, now.month + i) case final m) DropdownMenuItem(value: m, child: Text('${names[m.month - 1]} ${m.year}')),
                  ],
                  onChanged: (v) => setLocal(() => month = v ?? month),
                ),
                const SizedBox(height: 8),
                Text('A sheet for each:', style: Theme.of(ctx).textTheme.titleSmall),
                for (final i in items)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: chosen.contains(i.id),
                    title: Text(i.name),
                    onChanged: (v) => setLocal(() => v == true ? chosen.add(i.id) : chosen.remove(i.id)),
                  ),
                Text('${workers.length} workers (with the potato groups) and 20 empty lines', style: const TextStyle(color: NaniniColors.muted)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, true), child: const Text('Show')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final people = timesheetsFor(farm, employees, groups, month).single.workers;
    await showPdfPreview(
      context,
      () => buildTimesheetsPdf(
        farmName: farmShort(farm),
        farmId: farm.id,
        month: month,
        fridge: true,
        days: timesheetDays(month, paidUpTo: paidUpTo),
        sheets: [
          for (final i in items)
            if (chosen.contains(i.id)) Timesheet(title: i.name, subtitle: 'How many each worker took', workers: people, itemId: i.id),
        ],
      ),
      landscape: true,
      title: 'Fridge sheets: ${farmShort(farm)} ${names[month.month - 1]} ${month.year}',
    );
  }
}
