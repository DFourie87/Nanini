import 'package:flutter/material.dart';
import 'employees_models.dart';

/// Two-step add/edit flow matching the web app: first ask payment method,
/// then show only the fields relevant to that method.
Future<Employee?> showEmployeeForm(
  BuildContext context, {
  Employee? existing,
  required List<EmployeeGroup> groups,
}) async {
  var method = existing?.paymentMethod;
  if (method == null) {
    method = await showDialog<PaymentMethod>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('How is this employee paid?'),
        children: [
          for (final m in PaymentMethod.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Text(switch (m) {
                PaymentMethod.bank => 'Bank transfer',
                PaymentMethod.atm => 'ATM card',
                PaymentMethod.cash => 'Cash',
              }),
            ),
        ],
      ),
    );
    if (method == null) return null;
    if (!context.mounted) return null;
  }

  final firstNameCtrl = TextEditingController(text: existing?.firstName);
  final lastNameCtrl = TextEditingController(text: existing?.lastName);
  final idCtrl = TextEditingController(text: existing?.idOrPassport);
  final rateCtrl = TextEditingController(text: existing?.ratePerHour?.toString());
  final rentCtrl = TextEditingController(text: existing?.rentDeduction?.toString());
  final loanCtrl = TextEditingController(text: existing?.loanDeduction?.toString());
  final bankNameCtrl = TextEditingController(text: existing?.bankName);
  final bankAccCtrl = TextEditingController(text: existing?.bankAccountNo);
  final phoneCtrl = TextEditingController(text: existing?.phoneNumber);
  final atmCodeCtrl = TextEditingController(text: existing?.atmAccessCode);
  String? groupId = existing?.currentGroupId;
  final sortedGroups = [...groups]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  final result = await showDialog<Employee>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'Add employee' : 'Edit employee'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: firstNameCtrl, decoration: const InputDecoration(labelText: 'First name')),
                const SizedBox(height: 10),
                TextField(controller: lastNameCtrl, decoration: const InputDecoration(labelText: 'Last name')),
                const SizedBox(height: 10),
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ID / passport number',
                    helperText: 'Required for PAYE/UIF to be deducted',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: rateCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Rate per hour (R)'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: groupId,
                  decoration: const InputDecoration(labelText: 'Group'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('No group')),
                    ...sortedGroups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))),
                  ],
                  onChanged: (v) => setState(() => groupId = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: rentCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Rent deduction (R)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: loanCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Loan deduction (R)'),
                ),
                if (method == PaymentMethod.bank) ...[
                  const SizedBox(height: 10),
                  TextField(controller: bankNameCtrl, decoration: const InputDecoration(labelText: 'Bank name')),
                  const SizedBox(height: 10),
                  TextField(controller: bankAccCtrl, decoration: const InputDecoration(labelText: 'Account number')),
                ],
                if (method == PaymentMethod.atm) ...[
                  const SizedBox(height: 10),
                  TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone number')),
                  const SizedBox(height: 10),
                  TextField(controller: atmCodeCtrl, decoration: const InputDecoration(labelText: 'ATM access code')),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (firstNameCtrl.text.trim().isEmpty) return;
              Navigator.pop(
                ctx,
                Employee(
                  id: existing?.id ?? '',
                  firstName: firstNameCtrl.text.trim(),
                  lastName: lastNameCtrl.text.trim(),
                  idOrPassport: idCtrl.text.trim().isEmpty ? null : idCtrl.text.trim(),
                  currentGroupId: groupId,
                  ratePerHour: double.tryParse(rateCtrl.text),
                  rentDeduction: double.tryParse(rentCtrl.text),
                  loanDeduction: double.tryParse(loanCtrl.text),
                  paymentMethod: method!,
                  bankName: bankNameCtrl.text.trim(),
                  bankAccountNo: bankAccCtrl.text.trim(),
                  phoneNumber: phoneCtrl.text.trim(),
                  atmAccessCode: atmCodeCtrl.text.trim(),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  return result;
}
