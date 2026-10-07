import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/dialog_error.dart';
import 'package:provider/provider.dart';
import '../../core/auth/session.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'employee_form.dart';
import 'employees_models.dart';
import 'employees_repository.dart';
import '../../core/run_once.dart';

/// Employees > List: every employee's details (name, ID/passport and names
/// as on the ID, farm, group, how they're paid) and the farms/groups. The
/// one place employees are added -- Hours, Tuck Shop, Nanini Capture and the
/// other apps read from here.
class EmployeeListTab extends StatefulWidget {
  const EmployeeListTab({super.key});
  @override
  State<EmployeeListTab> createState() => _EmployeeListTabState();
}

class _EmployeeListTabState extends State<EmployeeListTab> {
  final repo = EmployeesRepository();
  int index = 0;

  @override
  Widget build(BuildContext context) {
    // Members of Nanini 121 CC have their own tab, for admins only: other
    // users don't see it at all (not even locked).
    final isAdmin = context.watch<Session>().isAdmin;
    final pages = [
      _EmployeesTab(repo: repo),
      _GroupsTab(repo: repo),
      if (isAdmin) _EmployeesTab(repo: repo, members: true),
    ];
    if (index >= pages.length) index = 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SegmentedButton<int>(
            segments: [
              const ButtonSegment(value: 0, label: Text('Employees')),
              const ButtonSegment(value: 1, label: Text('Farms/Groups')),
              if (isAdmin) const ButtonSegment(value: 2, label: Text('Members')),
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
    );
  }
}

class _EmployeesTab extends StatefulWidget {
  const _EmployeesTab({required this.repo, this.members = false});
  final EmployeesRepository repo;

  /// The Members tab: only the members of Nanini 121 CC (the Employees tab
  /// leaves them out).
  final bool members;
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
            // A to Z by name, however the rows arrive (live updates land at
            // the end; the database's order is case-sensitive).
            final filtered = employees
                .where((e) => e.isMember == widget.members)
                .where((e) => e.displayName.toLowerCase().contains(search.toLowerCase()))
                .toList()
              ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: widget.members ? 'Search members…' : 'Search employees…',
                    ),
                    onChanged: (v) => setState(() => search = v),
                  ),
                ),
                Expanded(
                  child: !empSnap.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? Center(child: Text(widget.members ? 'No members.' : 'No employees yet.'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final e = filtered[i];
                                final group = e.isMember ? null : e.currentGroupId != null ? groupsById[e.currentGroupId] : null;
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
                                        if (e.isMember)
                                          Text(
                                            'Member of Nanini 121 CC (private) · ${e.onPayroll ? 'salary ${fmtR(e.monthlySalary)} per month' : 'not on payroll'}',
                                            style: const TextStyle(color: NaniniColors.rust, fontWeight: FontWeight.w600),
                                          ),
                                        if (e.legalNameMissing)
                                          const Text('Full names & surname (as on ID) needed', style: TextStyle(color: NaniniColors.red))
                                        else if (!e.hasId)
                                          const Text('No ID/passport yet', style: TextStyle(color: NaniniColors.muted)),
                                      ],
                                    ),
                                    trailing: isManager
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined),
                                                onPressed: () => runOnce('employee_list_tab.1', () async {
                                                  final updated = await showEmployeeForm(context, existing: e, groups: groups, farms: farms);
                                                  if (updated != null) {
                                                    await widget.repo.updateEmployee(e.id, updated);
                                                    if (context.mounted) showToast(context, 'Employee updated');
                                                  }
                                                }),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline),
                                                onPressed: () => runOnce('employee_list_tab.2', () async {
                                                  final ok = await confirmDialog(context,
                                                      message: 'Delete ${e.displayName}? Records already logged for them elsewhere are kept.',
                                                      danger: true);
                                                  if (ok) {
                                                    await widget.repo.deleteEmployee(e.id);
                                                    if (context.mounted) showToast(context, 'Employee deleted');
                                                  }
                                                }),
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
                onPressed: () => runOnce('employee_list_tab.3', () async {
                  if (!await requireAdmin(context)) return;
                  if (!context.mounted) return;
                  final groups = await widget.repo.watchGroups().first;
                  if (!context.mounted) return;
                  final all = await widget.repo.watchEmployees().first;
                  if (!context.mounted) return;
                  final created = await showEmployeeForm(context, groups: groups, farms: farms, emp201Column: all.any((e) => e.onEmp201 != null), emp201FromColumn: all.any((e) => e.hasEmp201From));
                  if (created != null) {
                    await widget.repo.addEmployee(created);
                    if (context.mounted) showToast(context, 'Employee added');
                  }
                }),
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
                              final farmEmployees = employees.where((e) => e.farmId == farm.id && !e.isMember).toList()
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
                    onPressed: () => runOnce('employee_list_tab.4', () async {
                      if (!await requireAdmin(context)) return;
                      if (!context.mounted) return;
                      if (farms.isEmpty) return showProblem(context, "Farms haven't loaded yet -- check the internet connection and try again.");
                      final result = await _showAddGroupDialog(context, farms.where((f) => farmUsesWorkGroups(f.name)).toList());
                      if (result != null) {
                        await widget.repo.addGroup(EmployeeGroup(id: '', name: result.$2, farmId: result.$1));
                        if (context.mounted) showToast(context, 'Group added');
                      }
                    }),
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
    if (farms.isEmpty) return null;
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
                if (name.isEmpty) {
                  showProblem(ctx, 'Enter the group name.');
                  return;
                }
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
