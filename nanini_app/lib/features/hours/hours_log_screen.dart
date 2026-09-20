import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'hours_models.dart';
import 'hours_repository.dart';

enum _LogMode { individual, group, picking }

class HoursLogScreen extends StatefulWidget {
  const HoursLogScreen({super.key, required this.repo});
  final HoursRepository repo;
  @override
  State<HoursLogScreen> createState() => _HoursLogScreenState();
}

class _HoursLogScreenState extends State<HoursLogScreen> {
  final employeesRepo = EmployeesRepository();
  _LogMode mode = _LogMode.individual;
  HoursSettings settings = HoursSettings();

  @override
  void initState() {
    super.initState();
    widget.repo.fetchSettings().then((s) => setState(() => settings = s));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<_LogMode>(
            segments: const [
              ButtonSegment(value: _LogMode.individual, label: Text('Individual', maxLines: 1, overflow: TextOverflow.ellipsis)),
              ButtonSegment(value: _LogMode.group, label: Text('Group', maxLines: 1, overflow: TextOverflow.ellipsis)),
              ButtonSegment(value: _LogMode.picking, label: Text('Picking (kg)', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            selected: {mode},
            onSelectionChanged: (s) => setState(() => mode = s.first),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: NaniniColors.rust,
              selectedForegroundColor: Colors.white,
            ),
          ),
        ),
        Expanded(
          child: switch (mode) {
            _LogMode.individual => _IndividualForm(repo: widget.repo, settings: settings, employeesRepo: employeesRepo),
            _LogMode.group => _GroupForm(repo: widget.repo, settings: settings, employeesRepo: employeesRepo),
            _LogMode.picking => _PickingForm(repo: widget.repo, employeesRepo: employeesRepo),
          },
        ),
      ],
    );
  }
}

class _IndividualForm extends StatefulWidget {
  const _IndividualForm({required this.repo, required this.settings, required this.employeesRepo});
  final HoursRepository repo;
  final HoursSettings settings;
  final EmployeesRepository employeesRepo;
  @override
  State<_IndividualForm> createState() => _IndividualFormState();
}

class _IndividualFormState extends State<_IndividualForm> {
  String? employeeId;
  DateTime date = DateTime.now();
  final hoursCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Employee>>(
      stream: widget.employeesRepo.watchEmployees(),
      builder: (context, snap) {
        final employees = snap.data ?? [];
        final sortedEmployees = [...employees]..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: employeeId,
              decoration: const InputDecoration(labelText: 'Employee'),
              items: sortedEmployees.map((e) => DropdownMenuItem(value: e.id, child: Text(e.displayName))).toList(),
              onChanged: (v) => setState(() => employeeId = v),
            ),
            const SizedBox(height: 12),
            _DateField(date: date, onChanged: (d) => setState(() => date = d)),
            const SizedBox(height: 12),
            TextField(
              controller: hoursCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Hours worked'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                final hours = double.tryParse(hoursCtrl.text) ?? 0;
                final emp = employees.where((e) => e.id == employeeId).firstOrNull;
                if (emp == null || hours <= 0) {
                  showToast(context, 'Select employee and hours', isError: true);
                  return;
                }
                await widget.repo.logIndividual(
                  employeeId: emp.id,
                  date: toDateStr(date),
                  hours: hours,
                  rate: emp.ratePerHour ?? 0,
                  settings: widget.settings,
                );
                if (!context.mounted) return;
                showToast(context, 'Logged ${hours}h for ${emp.displayName}');
                hoursCtrl.clear();
              },
              child: const Text('Log hours'),
            ),
          ],
        );
      },
    );
  }
}

class _GroupForm extends StatefulWidget {
  const _GroupForm({required this.repo, required this.settings, required this.employeesRepo});
  final HoursRepository repo;
  final HoursSettings settings;
  final EmployeesRepository employeesRepo;
  @override
  State<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends State<_GroupForm> {
  List<Farm> farms = [];
  String? farmId;
  String? groupId;
  DateTime date = DateTime.now();
  final hoursCtrl = TextEditingController();
  final Set<String> skipped = {};
  final Map<String, double> overrides = {};

  @override
  void initState() {
    super.initState();
    widget.employeesRepo.fetchFarms().then((f) {
      if (!mounted) return;
      setState(() {
        farms = f;
        farmId = f.isNotEmpty ? f.first.id : null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EmployeeGroup>>(
      stream: widget.employeesRepo.watchGroups(),
      builder: (context, grpSnap) {
        final groups = grpSnap.data ?? [];
        return StreamBuilder<List<Employee>>(
          stream: widget.employeesRepo.watchEmployees(),
          builder: (context, empSnap) {
            final employees = empSnap.data ?? [];
            final members = employees.where((e) => e.currentGroupId == groupId).toList();
            final farmGroups = groups.where((g) => g.farmId == farmId).toList();
            final sortedGroups = [...farmGroups]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: farmId,
                  decoration: const InputDecoration(labelText: 'Farm'),
                  items: farms.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
                  onChanged: (v) => setState(() { farmId = v; groupId = null; skipped.clear(); overrides.clear(); }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: groupId,
                  decoration: const InputDecoration(labelText: 'Group'),
                  items: sortedGroups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))).toList(),
                  onChanged: (v) => setState(() { groupId = v; skipped.clear(); overrides.clear(); }),
                ),
                const SizedBox(height: 12),
                _DateField(date: date, onChanged: (d) => setState(() => date = d)),
                const SizedBox(height: 12),
                TextField(
                  controller: hoursCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Hours (applied to all members)'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                for (final m in members)
                  CheckboxListTile(
                    value: !skipped.contains(m.id),
                    onChanged: (v) => setState(() {
                      if (v == false) {
                        skipped.add(m.id);
                      } else {
                        skipped.remove(m.id);
                      }
                    }),
                    title: Text(m.displayName),
                    subtitle: skipped.contains(m.id) ? const Text('Skipped — worked elsewhere') : null,
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final hours = double.tryParse(hoursCtrl.text) ?? 0;
                    final included = members.where((m) => !skipped.contains(m.id)).toList();
                    if (groupId == null || included.isEmpty || hours <= 0) {
                      showToast(context, 'Select a group and enter hours', isError: true);
                      return;
                    }
                    final group = groups.firstWhere((g) => g.id == groupId);
                    await widget.repo.logGroup(
                      members: included.map((m) => (employeeId: m.id, hours: overrides[m.id] ?? hours, rate: m.ratePerHour ?? 0)).toList(),
                      date: toDateStr(date),
                      settings: widget.settings,
                      groupName: group.name,
                    );
                    if (!context.mounted) return;
                    showToast(context, 'Logged hours for ${included.length} employees');
                    hoursCtrl.clear();
                    setState(() { skipped.clear(); overrides.clear(); });
                  },
                  child: const Text('Log group hours'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PickingForm extends StatefulWidget {
  const _PickingForm({required this.repo, required this.employeesRepo});
  final HoursRepository repo;
  final EmployeesRepository employeesRepo;
  @override
  State<_PickingForm> createState() => _PickingFormState();
}

class _PickingFormState extends State<_PickingForm> {
  DateTime date = DateTime.now();
  final rateCtrl = TextEditingController();
  final Map<String, double> kgByEmployee = {};

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Employee>>(
      stream: widget.employeesRepo.watchEmployees(),
      builder: (context, snap) {
        final employees = snap.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DateField(date: date, onChanged: (d) => setState(() => date = d)),
            const SizedBox(height: 12),
            TextField(
              controller: rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Rate (R/kg)'),
            ),
            const SizedBox(height: 12),
            for (final e in employees)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(e.displayName)),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'kg', isDense: true),
                        onChanged: (v) => kgByEmployee[e.id] = double.tryParse(v) ?? 0,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final rate = double.tryParse(rateCtrl.text) ?? 0;
                if (rate <= 0) {
                  showToast(context, 'Enter a rate per kg', isError: true);
                  return;
                }
                if (kgByEmployee.values.every((v) => v <= 0)) {
                  showToast(context, 'Enter kg picked for at least one employee', isError: true);
                  return;
                }
                await widget.repo.logKg(employeeKg: kgByEmployee, date: toDateStr(date), ratePerKg: rate);
                if (!context.mounted) return;
                showToast(context, 'Saved picking totals');
                setState(() => kgByEmployee.clear());
              },
              child: const Text('Save picking totals'),
            ),
          ],
        );
      },
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onChanged});
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Date'),
        child: Text(fmtDateDisplay(toDateStr(date))),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
