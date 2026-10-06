import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/session.dart';
import '../../core/formatters.dart';
import '../../core/widgets/dialog_error.dart';
import '../../theme/nanini_theme.dart';
import 'employees_models.dart';

/// Two-step add/edit flow matching the web app: first ask payment method,
/// then show only the fields relevant to that method.
Future<Employee?> showEmployeeForm(
  BuildContext context, {
  Employee? existing,
  required List<EmployeeGroup> groups,
  required List<Farm> farms,
}) async {
  // Members are all paid by bank transfer: their bank account is asked for.
  var method = existing?.isMember == true ? PaymentMethod.bank : existing?.paymentMethod;
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
                PaymentMethod.atm => 'ATM',
                PaymentMethod.cash => 'Cash',
              }),
            ),
        ],
      ),
    );
    if (method == null) return null;
    if (!context.mounted) return null;
  }

  // One "Name" field: the name everyone knows them by (existing first + last
  // name, as entered before). Names as on the ID are separate.
  final nameCtrl = TextEditingController(text: existing == null ? null : '${existing.firstName} ${existing.lastName}'.trim());
  final idCtrl = TextEditingController(text: existing?.idOrPassport);
  final fullNamesCtrl = TextEditingController(text: existing?.fullNames);
  final surnameCtrl = TextEditingController(text: existing?.surname);
  final bankNameCtrl = TextEditingController(text: existing?.bankName);
  final bankAccCtrl = TextEditingController(text: existing?.bankAccountNo);
  final phoneCtrl = TextEditingController(text: existing?.phoneNumber);
  String? groupId = existing?.currentGroupId;
  String? farmId = existing?.farmId ?? (farms.isNotEmpty ? farms.first.id : null);
  // Members of Nanini 121 CC: admins only.
  final isAdmin = context.read<Session>().isAdmin;
  var isMember = existing?.isMember ?? false;
  var onPayroll = existing?.onPayroll ?? true;
  final salaryCtrl = TextEditingController(text: existing?.monthlySalary == null ? null : existing!.monthlySalary!.toStringAsFixed(2));
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
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name', helperText: 'The name everyone knows them by'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: idCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'ID / passport number',
                    helperText: 'Needed for PAYE/UIF -- can be added later',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: fullNamesCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: idCtrl.text.trim().isEmpty ? 'Full names (as on ID)' : 'Full names (as on ID) *',
                    helperText: idCtrl.text.trim().isEmpty ? 'Can be added later' : 'Required with an ID/passport',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: surnameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: idCtrl.text.trim().isEmpty ? 'Surname' : 'Surname *'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: farmId,
                  decoration: const InputDecoration(labelText: 'Farm'),
                  items: farms.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
                  onChanged: (v) => setState(() => farmId = v),
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
                const SizedBox(height: 8),
                const Text('Tariff, rent and loan: tap the worker in Summary, or Nanini Capture > Payslips.',
                    style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
                if (isAdmin) ...[
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isMember,
                    onChanged: (v) => setState(() {
                      isMember = v ?? false;
                      // Members are all paid by bank transfer.
                      if (isMember) method = PaymentMethod.bank;
                    }),
                    title: const Text('Member of Nanini 121 CC'),
                    subtitle: const Text('Private: only admins see them, paid by bank transfer in a separate Members payroll', style: TextStyle(fontSize: 12)),
                  ),
                  if (isMember) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: onPayroll,
                      onChanged: (v) => setState(() => onPayroll = v ?? true),
                      title: const Text('On payroll'),
                    ),
                    if (onPayroll)
                      TextField(
                        controller: salaryCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Monthly salary', prefixText: 'R'),
                      ),
                  ],
                ],
                if (method == PaymentMethod.bank) ...[
                  const SizedBox(height: 10),
                  TextField(controller: bankNameCtrl, decoration: const InputDecoration(labelText: 'Bank name')),
                  const SizedBox(height: 10),
                  TextField(controller: bankAccCtrl, decoration: const InputDecoration(labelText: 'Account number')),
                ],
                if (method == PaymentMethod.atm) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone number *', helperText: 'Printed on the payslip with the ATM access code'),
                  ),
                  const SizedBox(height: 6),
                  const Text('The ATM access code is new every payday -- made at Run payroll and printed on the payslip.',
                      style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final problem = employeeDetailsProblem(
                name: nameCtrl.text,
                idOrPassport: idCtrl.text,
                fullNames: fullNamesCtrl.text,
                surname: surnameCtrl.text,
              );
              if (problem != null) {
                showProblem(ctx, problem);
                return;
              }
              if (method == PaymentMethod.atm && phoneCtrl.text.trim().isEmpty) {
                showProblem(ctx, 'Paid by ATM: enter the phone number (it goes on the payslip with the access code).');
                return;
              }
              String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
              Navigator.pop(
                ctx,
                Employee(
                  id: existing?.id ?? '',
                  firstName: nameCtrl.text.trim(),
                  lastName: '',
                  idOrPassport: opt(idCtrl),
                  fullNames: opt(fullNamesCtrl),
                  surname: opt(surnameCtrl),
                  currentGroupId: groupId,
                  farmId: farmId,
                  // Set in Summary / Payslips; kept as they are.
                  ratePerHour: existing?.ratePerHour,
                  rentDeduction: existing?.rentDeduction,
                  loanDeduction: existing?.loanDeduction,
                  paymentMethod: isMember ? PaymentMethod.bank : method!,
                  bankName: bankNameCtrl.text.trim(),
                  bankAccountNo: bankAccCtrl.text.trim(),
                  phoneNumber: phoneCtrl.text.trim(),
                  atmAccessCode: existing?.atmAccessCode,
                  isMember: isMember,
                  onPayroll: !isMember || onPayroll,
                  monthlySalary: isMember && onPayroll ? parseNum(salaryCtrl.text) : null,
                  hasMemberColumns: existing?.hasMemberColumns ?? false,
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
