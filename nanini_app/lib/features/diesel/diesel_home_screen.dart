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
                      ...purchases.map((p) => _TxnRow(p.createdAt, 'Purchase', p.litres, tanks.where((t) => t.id == p.tankId).map((t) => t.name).firstOrNull ?? '')),
                      ...usage.map((u) => _TxnRow(u.createdAt, 'Usage', -u.litres, tanks.where((t) => t.id == u.tankId).map((t) => t.name).firstOrNull ?? '')),
                    ]..sort((a, b) => b.at.compareTo(a.at));

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
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
                              leading: Icon(t.litres >= 0 ? Icons.local_gas_station : Icons.moving, color: t.litres >= 0 ? NaniniColors.green : NaniniColors.rustDark),
                              title: Text('${t.type} · ${t.tankName}'),
                              subtitle: Text(fmtDateTimeDisplay(t.at.toIso8601String())),
                              trailing: Text(fmtL(t.litres.abs())),
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
  _TxnRow(this.at, this.type, this.litres, this.tankName);
  final DateTime at;
  final String type;
  final double litres;
  final String tankName;
}

class _TankGauge extends StatelessWidget {
  const _TankGauge({required this.tank, required this.level});
  final DieselTank tank;
  final double level;

  @override
  Widget build(BuildContext context) {
    final pct = tank.capacity > 0 ? (level / tank.capacity * 100).clamp(0, 100) : 0.0;
    final color = pct >= 35 ? NaniniColors.green : (pct >= 15 ? NaniniColors.amber : NaniniColors.red);
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
                Text('${fmtL(level)} / ${fmtL(tank.capacity)}', style: const TextStyle(color: NaniniColors.muted)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 14,
                backgroundColor: NaniniColors.disabledBg,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text('${pct.toStringAsFixed(0)}% full', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
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
