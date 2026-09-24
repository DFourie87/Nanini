import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/formatters.dart';
import '../../core/auth/session.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'employee_form.dart';
import 'employees_models.dart';
import 'employees_repository.dart';

class EmployeesHomeScreen extends StatefulWidget {
  const EmployeesHomeScreen({super.key});
  @override
  State<EmployeesHomeScreen> createState() => _EmployeesHomeScreenState();
}

class _EmployeesHomeScreenState extends State<EmployeesHomeScreen> {
  final repo = EmployeesRepository();
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _EmployeesTab(repo: repo),
      _GroupsTab(repo: repo),
    ];
    return Scaffold(
      appBar: NaniniAppBar(
        title: 'Employee List',
        actions: [
          IconButton(
            tooltip: 'Help',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const AlertDialog(
                content: Text(
                  'This is the one place employee details are entered — the '
                  'Hours, Tuck Shop, and other apps read from this list instead '
                  'of adding their own.',
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Employees')),
                ButtonSegment(value: 1, label: Text('Farms/Groups')),
              ],
              selected: {index},
              onSelectionChanged: (s) => setState(() => index = s.first),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: NaniniColors.rust,
                selectedForegroundColor: Colors.white,
              ),
            ),
          ),
          Expanded(child: pages[index]),
        ],
      ),
    );
  }
}

class _EmployeesTab extends StatefulWidget {
  const _EmployeesTab({required this.repo});
  final EmployeesRepository repo;
  @override
  State<_EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<_EmployeesTab> {
  String search = '';
  List<Farm> farms = [];

  @override
  void initState() {
    super.initState();
    widget.repo.fetchFarms().then((f) {
      if (mounted) setState(() => farms = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isManager = context.watch<Session>().isAdmin;
    return Stack(
      children: [
        StreamBuilder<List<Employee>>(
      stream: widget.repo.watchEmployees(),
      builder: (context, empSnap) {
        return StreamBuilder<List<EmployeeGroup>>(
          stream: widget.repo.watchGroups(),
          builder: (context, grpSnap) {
            final employees = empSnap.data ?? [];
            final groups = grpSnap.data ?? [];
            final groupsById = {for (final g in groups) g.id: g};
            final farmsById = {for (final f in farms) f.id: f};
            final filtered = employees
                .where((e) => e.displayName.toLowerCase().contains(search.toLowerCase()))
                .toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search employees…',
                    ),
                    onChanged: (v) => setState(() => search = v),
                  ),
                ),
                Expanded(
                  child: !empSnap.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? const Center(child: Text('No employees yet.'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final e = filtered[i];
                                final group = e.currentGroupId != null ? groupsById[e.currentGroupId] : null;
                                final farm = e.farmId != null ? farmsById[e.farmId] : null;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: ListTile(
                                    title: Text(e.displayName),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (farm != null) Text(farm.name),
                                        if (group != null) Text(group.name),
                                        if (e.ratePerHour != null) Text('Tariff: ${fmtR(e.ratePerHour)}/hr'),
                                      ],
                                    ),
                                    trailing: isManager
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined),
                                                onPressed: () async {
                                                  final updated = await showEmployeeForm(context, existing: e, groups: groups, farms: farms);
                                                  if (updated != null) {
                                                    await widget.repo.updateEmployee(e.id, updated);
                                                    if (context.mounted) showToast(context, 'Employee updated');
                                                  }
                                                },
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline),
                                                onPressed: () async {
                                                  final ok = await confirmDialog(context,
                                                      message: 'Delete ${e.displayName}? Records already logged for them elsewhere are kept.',
                                                      danger: true);
                                                  if (ok) {
                                                    await widget.repo.deleteEmployee(e.id);
                                                    if (context.mounted) showToast(context, 'Employee deleted');
                                                  }
                                                },
                                              ),
                                            ],
                                          )
                                        : null,
                                  ),
                                );
                              },
                            ),
                ),
              ],
            );
          },
        );
      },
    ),
        Positioned(
              right: 16,
              bottom: 32,
              child: FloatingActionButton.extended(
                onPressed: () async {
                  if (!await requireAdmin(context)) return;
                  if (!context.mounted) return;
                  final groups = await widget.repo.watchGroups().first;
                  if (!context.mounted) return;
                  final created = await showEmployeeForm(context, groups: groups, farms: farms);
                  if (created != null) {
                    await widget.repo.addEmployee(created);
                    if (context.mounted) showToast(context, 'Employee added');
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Add employee'),
              ),
            ),
      ],
    );
  }
}

class _GroupsTab extends StatefulWidget {
  const _GroupsTab({required this.repo});
  final EmployeesRepository repo;
  @override
  State<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<_GroupsTab> {
  List<Farm> farms = [];

  @override
  void initState() {
    super.initState();
    widget.repo.fetchFarms().then((f) {
      if (mounted) setState(() => farms = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isManager = context.watch<Session>().isAdmin;
    return StreamBuilder<List<Employee>>(
      stream: widget.repo.watchEmployees(),
      builder: (context, empSnap) {
        return StreamBuilder<List<EmployeeGroup>>(
          stream: widget.repo.watchGroups(),
          builder: (context, grpSnap) {
            final employees = empSnap.data ?? [];
            final groups = grpSnap.data ?? [];
            final loading = !empSnap.hasData || !grpSnap.hasData;

            return Stack(
              children: [
                loading
                    ? const Center(child: CircularProgressIndicator())
                    : farms.isEmpty
                        ? const Center(child: Text('No farms yet.'))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                            itemCount: farms.length,
                            itemBuilder: (context, i) {
                              final farm = farms[i];
                              final farmEmployees = employees.where((e) => e.farmId == farm.id).toList()
                                ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
                              final farmGroups = groups.where((g) => g.farmId == farm.id).toList()
                                ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                              return _FarmSection(
                                farm: farm,
                                employees: farmEmployees,
                                groups: farmGroups,
                                isManager: isManager,
                                onDeleteGroup: (g) async {
                                  final ok = await confirmDialog(context,
                                      message: 'Delete "${g.name}"? Members will be unassigned, not deleted.', danger: true);
                                  if (ok) {
                                    await widget.repo.deleteGroup(g.id);
                                    if (context.mounted) showToast(context, 'Group deleted');
                                  }
                                },
                              );
                            },
                          ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(
                    onPressed: () async {
                      if (!await requireAdmin(context)) return;
                      if (!context.mounted || farms.isEmpty) return;
                      final result = await _showAddGroupDialog(context, farms);
                      if (result != null) {
                        await widget.repo.addGroup(EmployeeGroup(id: '', name: result.$2, farmId: result.$1));
                        if (context.mounted) showToast(context, 'Group added');
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add group'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<(String, String)?> _showAddGroupDialog(BuildContext context, List<Farm> farms) async {
    final controller = TextEditingController();
    var farmId = farms.first.id;
    return showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: farmId,
                decoration: const InputDecoration(labelText: 'Farm'),
                items: farms.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
                onChanged: (v) => setLocal(() => farmId = v!),
              ),
              const SizedBox(height: 10),
              TextField(controller: controller, decoration: const InputDecoration(labelText: 'Group name')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx, (farmId, name));
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FarmSection extends StatelessWidget {
  const _FarmSection({required this.farm, required this.employees, required this.groups, required this.isManager, required this.onDeleteGroup});
  final Farm farm;
  final List<Employee> employees;
  final List<EmployeeGroup> groups;
  final bool isManager;
  final ValueChanged<EmployeeGroup> onDeleteGroup;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(farm.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('Workers (${employees.length})', style: const TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
            const SizedBox(height: 6),
            if (employees.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('No workers assigned to this farm yet.', style: TextStyle(color: NaniniColors.muted)))
            else
              for (final e in employees) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(e.displayName)),
            const SizedBox(height: 16),
            Text('Groups (${groups.length})', style: const TextStyle(fontWeight: FontWeight.w600, color: NaniniColors.muted, fontSize: 12)),
            const SizedBox(height: 6),
            if (groups.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('No groups for this farm yet.', style: TextStyle(color: NaniniColors.muted)))
            else
              for (final g in groups)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(g.name)),
                      if (isManager)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => onDeleteGroup(g),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
