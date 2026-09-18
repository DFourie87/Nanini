import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/session.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'tuckshop_repository.dart';
import 'tuckshop_stock_screen.dart';
import 'tuckshop_purchases_screen.dart';
import 'tuckshop_log_screen.dart';
import 'tuckshop_reports_screen.dart';

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
    final isManager = context.watch<Session>().isAdmin;
    final isHaaskraal = farms.where((f) => f.id == selectedFarmId).any((f) => f.name.contains('Haaskraal'));

    final pages = [
      TuckshopStockScreen(repo: repo, farmId: selectedFarmId),
      TuckshopPurchasesScreen(repo: repo, farmId: selectedFarmId),
      TuckshopLogScreen(repo: repo, farmId: selectedFarmId, manualMode: isHaaskraal),
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
      appBar: const NaniniAppBar(title: 'Tuck Shop'),
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
                            label: Text(f.name.replaceFirst('Farm ', '').split(' - ').first),
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
}
