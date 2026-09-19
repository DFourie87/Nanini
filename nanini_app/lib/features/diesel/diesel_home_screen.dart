import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/formatters.dart';
import '../../core/auth/session.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import 'diesel_models.dart';
import 'diesel_repository.dart';
import 'diesel_log_screen.dart';
import 'diesel_reports_screen.dart';

class DieselHomeScreen extends StatefulWidget {
  const DieselHomeScreen({super.key});
  @override
  State<DieselHomeScreen> createState() => _DieselHomeScreenState();
}

class _DieselHomeScreenState extends State<DieselHomeScreen> {
  final repo = DieselRepository();
  int index = 0;

  @override
  void initState() {
    super.initState();
    repo.ensureDefaultActivities();
  }

  @override
  Widget build(BuildContext context) {
    final isManager = context.watch<Session>().isAdmin;
    final pages = [
      _DieselDashboard(repo: repo),
      DieselLogScreen(repo: repo),
      if (isManager) DieselReportsScreen(repo: repo),
    ];
    final items = [
      const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
      const BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: 'Log entry'),
      if (isManager) const BottomNavigationBarItem(icon: Icon(Icons.summarize_outlined), label: 'Reports'),
    ];
    final safeIndex = index >= pages.length ? 0 : index;

    return Scaffold(
      appBar: const NaniniAppBar(title: 'Diesel'),
      // IndexedStack keeps every tab's widgets (and their stream subscriptions)
      // alive across switches, instead of tearing them down and resubscribing
      // to Supabase from scratch every time the tab changes.
      body: IndexedStack(index: safeIndex, children: pages),
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

class _DieselDashboard extends StatelessWidget {
  const _DieselDashboard({required this.repo});
  final DieselRepository repo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DieselTank>>(
      stream: repo.watchTanks(),
      builder: (context, tankSnap) {
        return StreamBuilder<List<DieselPurchase>>(
          stream: repo.watchPurchases(),
          builder: (context, purSnap) {
            return StreamBuilder<List<DieselUsage>>(
              stream: repo.watchUsage(),
              builder: (context, useSnap) {
                return StreamBuilder<List<DieselAdjustment>>(
                  stream: repo.watchAdjustments(),
                  builder: (context, adjSnap) {
                    final tanks = tankSnap.data ?? [];
                    final purchases = purSnap.data ?? [];
                    final usage = useSnap.data ?? [];
                    final adjustments = adjSnap.data ?? [];

                    if (tankSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (tanks.isEmpty) {
                      return _EmptyTanksState(repo: repo);
                    }

                    final recent = <_TxnRow>[
                      ...purchases.map((p) => _TxnRow(
                            at: p.createdAt,
                            isRefill: true,
                            description: (p.supplier?.trim().isNotEmpty ?? false) ? p.supplier!.trim() : '—',
                            tankName: tanks.where((t) => t.id == p.tankId).map((t) => t.name).firstOrNull ?? '',
                            hoursOrOdometer: null,
                            date: p.date,
                            litres: p.litres,
                          )),
                      ...usage.map((u) => _TxnRow(
                            at: u.createdAt,
                            isRefill: false,
                            description: (u.equipment?.trim().isNotEmpty ?? false)
                                ? u.equipment!.trim()
                                : ((u.asset?.trim().isNotEmpty ?? false) ? u.asset!.trim() : '—'),
                            tankName: tanks.where((t) => t.id == u.tankId).map((t) => t.name).firstOrNull ?? '',
                            hoursOrOdometer: u.hours,
                            date: u.date,
                            litres: u.litres,
                          )),
                    ]..sort((a, b) => b.at.compareTo(a.at));

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text('Tank levels', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        for (final tank in tanks)
                          _TankGauge(
                            tank: tank,
                            level: computeTankLevel(tank, purchases: purchases, usage: usage, adjustments: adjustments),
                          ),
                        const SizedBox(height: 8),
                        Text('Recent activity', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        for (final t in recent.take(5))
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(
                                t.isRefill ? Icons.arrow_upward : Icons.arrow_downward,
                                color: t.isRefill ? NaniniColors.green : NaniniColors.rust,
                              ),
                              title: Text(t.description),
                              subtitle: Text([
                                t.tankName,
                                if (t.hoursOrOdometer != null && t.hoursOrOdometer!.trim().isNotEmpty) t.hoursOrOdometer!.trim(),
                                fmtDateDisplay(t.date),
                              ].join(' · ')),
                              trailing: Text(fmtL(t.litres)),
                            ),
                          ),
                        if (recent.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No activity yet.')),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _TxnRow {
  _TxnRow({
    required this.at,
    required this.isRefill,
    required this.description,
    required this.tankName,
    required this.hoursOrOdometer,
    required this.date,
    required this.litres,
  });
  final DateTime at;
  final bool isRefill;
  final String description;
  final String tankName;
  final String? hoursOrOdometer;
  final String date;
  final double litres;
}

class _TankGauge extends StatelessWidget {
  const _TankGauge({required this.tank, required this.level});
  final DieselTank tank;
  final double level;

  @override
  Widget build(BuildContext context) {
    final pct = tank.capacity > 0 ? (level / tank.capacity * 100).clamp(0, 100) : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tank.name, style: Theme.of(context).textTheme.titleMedium),
                Text('${fmtLWhole(level)} / ${fmtLWhole(tank.capacity)}', style: const TextStyle(color: NaniniColors.muted)),
              ],
            ),
            const SizedBox(height: 10),
            Text('Tank level', style: const TextStyle(color: NaniniColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 14,
                backgroundColor: NaniniColors.disabledBg,
                color: NaniniColors.rust,
              ),
            ),
            const SizedBox(height: 6),
            Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(color: NaniniColors.rust, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _EmptyTanksState extends StatelessWidget {
  const _EmptyTanksState({required this.repo});
  final DieselRepository repo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No diesel tanks yet.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (!await requireAdmin(context)) return;
                if (!context.mounted) return;
                await _showAddTankDialog(context, repo);
              },
              child: const Text('Add a tank'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showAddTankDialog(BuildContext context, DieselRepository repo) async {
  final nameCtrl = TextEditingController();
  final capCtrl = TextEditingController();
  final levelCtrl = TextEditingController(text: '0');
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add tank'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tank name')),
          const SizedBox(height: 10),
          TextField(controller: capCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacity (L)')),
          const SizedBox(height: 10),
          TextField(controller: levelCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Current level (L)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final cap = double.tryParse(capCtrl.text) ?? 0;
            if (nameCtrl.text.trim().isEmpty || cap <= 0) return;
            await repo.addTank(name: nameCtrl.text.trim(), capacity: cap, initialLevel: double.tryParse(levelCtrl.text) ?? 0);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
