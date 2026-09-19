import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'diesel_models.dart';
import 'diesel_repository.dart';

class DieselLogScreen extends StatefulWidget {
  const DieselLogScreen({super.key, required this.repo});
  final DieselRepository repo;

  @override
  State<DieselLogScreen> createState() => _DieselLogScreenState();
}

class _DieselLogScreenState extends State<DieselLogScreen> {
  bool isUsage = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Usage')),
              ButtonSegment(value: false, label: Text('Purchase')),
            ],
            selected: {isUsage},
            onSelectionChanged: (s) => setState(() => isUsage = s.first),
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: NaniniColors.rust,
              selectedForegroundColor: Colors.white,
            ),
          ),
        ),
        Expanded(child: isUsage ? _UsageForm(repo: widget.repo) : _PurchaseForm(repo: widget.repo)),
      ],
    );
  }
}

class _UsageForm extends StatefulWidget {
  const _UsageForm({required this.repo});
  final DieselRepository repo;
  @override
  State<_UsageForm> createState() => _UsageFormState();
}

class _UsageFormState extends State<_UsageForm> {
  final employeesRepo = EmployeesRepository();
  String? tankId;
  String? activityId;
  String? equipmentId;
  String? employeeId;
  DateTime date = DateTime.now();
  final litresCtrl = TextEditingController();
  final hourMeterCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DieselTank>>(
      stream: widget.repo.watchTanks(),
      builder: (context, tankSnap) {
        final tanks = tankSnap.data ?? [];
        return StreamBuilder<List<DieselActivity>>(
          stream: widget.repo.watchActivities(),
          builder: (context, actSnap) {
            final activities = actSnap.data ?? [];
            return StreamBuilder<List<DieselVehicle>>(
              stream: widget.repo.watchVehicles(),
              builder: (context, vehSnap) {
                final vehicles = vehSnap.data ?? [];
                return StreamBuilder<List<Employee>>(
                  stream: employeesRepo.watchEmployees(),
                  builder: (context, empSnap) {
                    final employees = empSnap.data ?? [];
                    tankId ??= tanks.isNotEmpty ? tanks.first.id : null;

                    final sortedTanks = [...tanks]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                    final sortedVehicles = [...vehicles]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                    final sortedEmployees = [...employees]..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
                    final sortedActivities = [...activities]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                    final dropdownStyle = Theme.of(context).textTheme.bodyLarge;

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: tankId,
                          style: dropdownStyle,
                          decoration: const InputDecoration(labelText: 'Tank'),
                          items: sortedTanks.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                          onChanged: (v) => setState(() => tankId = v),
                        ),
                        const SizedBox(height: 12),
                        _DatePickerField(label: 'Date', date: date, onChanged: (d) => setState(() => date = d)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: litresCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Litres'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: equipmentId,
                          style: dropdownStyle,
                          decoration: const InputDecoration(labelText: 'Equipment / vehicle'),
                          items: sortedVehicles.map((v) => DropdownMenuItem(value: v.id, child: Text(v.name))).toList(),
                          onChanged: (v) => setState(() => equipmentId = v),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          initialValue: employeeId,
                          style: dropdownStyle,
                          decoration: const InputDecoration(labelText: 'Refuelled by'),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Employee')),
                            ...sortedEmployees.map((e) => DropdownMenuItem(value: e.id, child: Text(e.displayName))),
                          ],
                          onChanged: (v) => setState(() => employeeId = v),
                        ),
                        const SizedBox(height: 12),
                        TextField(controller: hourMeterCtrl, decoration: const InputDecoration(labelText: 'Hour meter / odometer')),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: activityId,
                          style: dropdownStyle,
                          decoration: const InputDecoration(labelText: 'Activity'),
                          items: sortedActivities.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                          onChanged: (v) => setState(() => activityId = v),
                        ),
                        const SizedBox(height: 12),
                        TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () async {
                            final litres = double.tryParse(litresCtrl.text) ?? 0;
                            if (tankId == null || litres <= 0) {
                              showToast(context, 'Enter tank and litres', isError: true);
                              return;
                            }
                            final activity = activities.where((a) => a.id == activityId).firstOrNull;
                            final vehicle = vehicles.where((v) => v.id == equipmentId).firstOrNull;
                            await widget.repo.logUsage(DieselUsage(
                              id: '',
                              tankId: tankId!,
                              date: toDateStr(date),
                              litres: litres,
                              equipment: vehicle?.name,
                              asset: vehicle?.asset,
                              hours: hourMeterCtrl.text.trim(),
                              activity: activity?.name,
                              eligible: activity?.eligible ?? false,
                              notes: notesCtrl.text.trim(),
                              employeeId: employeeId,
                              createdAt: DateTime.now(),
                            ));
                            if (!context.mounted) return;
                            showToast(context, 'Usage logged');
                            litresCtrl.clear();
                            hourMeterCtrl.clear();
                            notesCtrl.clear();
                          },
                          child: const Text('Log usage'),
                        ),
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

class _PurchaseForm extends StatefulWidget {
  const _PurchaseForm({required this.repo});
  final DieselRepository repo;
  @override
  State<_PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<_PurchaseForm> {
  String? tankId;
  DateTime date = DateTime.now();
  final litresCtrl = TextEditingController();
  final supplierCtrl = TextEditingController();
  final deliveryNoteCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DieselTank>>(
      stream: widget.repo.watchTanks(),
      builder: (context, tankSnap) {
        final tanks = tankSnap.data ?? [];
        tankId ??= tanks.isNotEmpty ? tanks.first.id : null;
        final sortedTanks = [...tanks]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            DropdownButtonFormField<String>(
              initialValue: tankId,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(labelText: 'Tank'),
              items: sortedTanks.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
              onChanged: (v) => setState(() => tankId = v),
            ),
            const SizedBox(height: 12),
            _DatePickerField(label: 'Date', date: date, onChanged: (d) => setState(() => date = d)),
            const SizedBox(height: 12),
            TextField(
              controller: litresCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Litres'),
            ),
            const SizedBox(height: 12),
            TextField(controller: supplierCtrl, decoration: const InputDecoration(labelText: 'Supplier')),
            const SizedBox(height: 12),
            TextField(controller: deliveryNoteCtrl, decoration: const InputDecoration(labelText: 'Delivery note no.')),
            const SizedBox(height: 12),
            TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
            const SizedBox(height: 8),
            const Text('Cost & invoice no. can be added afterwards from Reports once the invoice arrives.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                final litres = double.tryParse(litresCtrl.text) ?? 0;
                if (tankId == null || litres <= 0) {
                  showToast(context, 'Enter tank and litres', isError: true);
                  return;
                }
                await widget.repo.logPurchase(DieselPurchase(
                  id: '',
                  tankId: tankId!,
                  date: toDateStr(date),
                  litres: litres,
                  supplier: supplierCtrl.text.trim(),
                  invoiceNote: deliveryNoteCtrl.text.trim(),
                  notes: notesCtrl.text.trim(),
                  createdAt: DateTime.now(),
                ));
                if (!context.mounted) return;
                showToast(context, 'Purchase logged');
                litresCtrl.clear();
                supplierCtrl.clear();
                deliveryNoteCtrl.clear();
                notesCtrl.clear();
              },
              child: const Text('Log purchase'),
            ),
          ],
        );
      },
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({required this.label, required this.date, required this.onChanged});
  final String label;
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
        decoration: InputDecoration(labelText: label),
        child: Text(fmtDateDisplay(toDateStr(date))),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
