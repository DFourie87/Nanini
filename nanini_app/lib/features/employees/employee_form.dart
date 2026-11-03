import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/session.dart';
import '../../core/formatters.dart';
import '../../core/widgets/dialog_error.dart';
import '../../theme/nanini_theme.dart';
import 'employees_models.dart';

/// Add or edit an employee: the person, where they work, how they're paid,
/// SARS (admins) and whether they still work here -- one clear form.
/// [member]: adding a member of Nanini 121 CC (from the Members list).
Future<Employee?> showEmployeeForm(
  BuildContext context, {
  Employee? existing,
  required List<EmployeeGroup> groups,
  required List<Farm> farms,
  // The database has "on EMP201" (emp201_declared.sql) and its "from" day
  // (emp201_from.sql).
  bool emp201Column = false,
  bool emp201FromColumn = false,
  bool member = false,
}) async {
  // Members are all paid by bank transfer: their bank account is asked for.
  final isMember = existing?.isMember ?? member;
  PaymentMethod? method = isMember ? PaymentMethod.bank : existing?.paymentMethod;

  // One "Name" field: the name everyone knows them by (existing first + last
  // name, as entered before). Names as on the ID are separate.
  final nameCtrl = TextEditingController(text: existing == null ? null : '${existing.firstName} ${existing.lastName}'.trim());
  final idCtrl = TextEditingController(text: existing?.idOrPassport);
  final taxNoCtrl = TextEditingController(text: existing?.incomeTaxNo);
  // The day they left the farm: kept, never deleted (payslips stay for SARS).
  var leftOn = existing?.leftOn;
  final fullNamesCtrl = TextEditingController(text: existing?.fullNames);
  final surnameCtrl = TextEditingController(text: existing?.surname);
  final bankNameCtrl = TextEditingController(text: existing?.bankName);
  final bankAccCtrl = TextEditingController(text: existing?.bankAccountNo);
  final phoneCtrl = TextEditingController(text: existing?.phoneNumber);
  // Members: their residential address (proof of address letters).
  final addressCtrl = TextEditingController(text: existing?.residentialAddress);
  final utilityCtrl = TextEditingController(text: existing?.utilityAccount);
  String? groupId = existing?.currentGroupId;
  String? farmId = existing?.farmId ?? (farms.isNotEmpty ? farms.first.id : null);
  final isAdmin = context.read<Session>().isAdmin;
  var onPayroll = existing?.onPayroll ?? true;
  // Declared to SARS on the EMP201: admins only; null = column not there yet.
  var onEmp201 = existing?.onEmp201 ?? (emp201Column ? false : null);
  // On EMP201 from (registered for UIF): pay before it isn't declared.
  final hasFrom = existing?.hasEmp201From ?? emp201FromColumn;
  var emp201From = existing?.emp201From;
  final salaryCtrl = TextEditingController(text: existing?.monthlySalary == null ? null : existing!.monthlySalary!.toStringAsFixed(2));
  final sortedGroups = [...groups]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Widget section(String title) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: NaniniColors.rustDark)),
      );
  Widget pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]);
  const gap = SizedBox(height: 10);
  Future<String?> pickDate(BuildContext ctx, String? current) async {
    final d = await showDatePicker(context: ctx, initialDate: current == null ? DateTime.now() : DateTime.parse(current), firstDate: DateTime(2015), lastDate: DateTime(2100));
    return d == null ? null : toDateStr(d);
  }

  final result = await showDialog<Employee>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? (isMember ? 'Add member' : 'Add employee') : existing.displayName),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                section('Person'),
                TextField(controller: nameCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Known as *')),
                gap,
                pair(
                  TextField(controller: fullNamesCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full names (as on ID)')),
                  TextField(controller: surnameCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Surname')),
                ),
                gap,
                pair(
                  TextField(controller: idCtrl, decoration: const InputDecoration(labelText: 'ID / passport no.')),
                  TextField(controller: taxNoCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Income tax no.')),
                ),
                if (isMember) ...[
                  gap,
                  TextField(
                    key: const Key('member_address'),
                    controller: addressCtrl,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Residential address', helperText: 'A line each -- used on the proof of address'),
                  ),
                  gap,
                  TextField(
                    key: const Key('member_utility'),
                    controller: utilityCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Eskom account no. at this address', helperText: "Its latest bill's first page goes with the proof of address"),
                  ),
                ],
                section('Work'),
                pair(
                  DropdownButtonFormField<String?>(
                    initialValue: farmId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Farm'),
                    items: farms.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => farmId = v),
                  ),
                  isMember
                      ? const SizedBox()
                      : DropdownButtonFormField<String?>(
                          initialValue: groupId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Group'),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('No group')),
                            ...sortedGroups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name, overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: (v) => setState(() => groupId = v),
                        ),
                ),
                if (existing?.hasLeftColumn ?? false) ...[
                  gap,
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(leftOn == null ? Icons.check_circle_outline : Icons.logout, color: leftOn == null ? NaniniColors.green : NaniniColors.red),
                    title: Text(leftOn == null ? 'Still working here' : 'Left on ${fmtDateDisplay(leftOn)}'),
                    trailing: leftOn == null
                        ? TextButton(onPressed: () async { final d = await pickDate(ctx, null); if (d != null) setState(() => leftOn = d); }, child: const Text('Set day left'))
                        : IconButton(tooltip: 'Still working here', icon: const Icon(Icons.clear), onPressed: () => setState(() => leftOn = null)),
                    onTap: () async {
                      final d = await pickDate(ctx, leftOn);
                      if (d != null) setState(() => leftOn = d);
                    },
                  ),
                ],
                section('Pay'),
                if (isMember) ...[
                  SwitchListTile(contentPadding: EdgeInsets.zero, value: onPayroll, onChanged: (v) => setState(() => onPayroll = v), title: const Text('On payroll')),
                  if (onPayroll)
                    TextField(
                      controller: salaryCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Monthly salary', prefixText: 'R'),
                    ),
                  gap,
                ] else ...[
                  SegmentedButton<PaymentMethod>(
                    segments: const [
                      ButtonSegment(value: PaymentMethod.bank, label: Text('Bank')),
                      ButtonSegment(value: PaymentMethod.atm, label: Text('ATM')),
                      ButtonSegment(value: PaymentMethod.cash, label: Text('Cash')),
                    ],
                    emptySelectionAllowed: true,
                    selected: {?method},
                    onSelectionChanged: (v) => setState(() => method = v.firstOrNull),
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
                  ),
                  gap,
                ],
                if (method == PaymentMethod.bank)
                  pair(
                    TextField(controller: bankNameCtrl, decoration: const InputDecoration(labelText: 'Bank')),
                    TextField(controller: bankAccCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Account no.')),
                  ),
                if (method == PaymentMethod.atm)
                  TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number *')),
                if (isAdmin && onEmp201 != null) ...[
                  section('SARS'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: onEmp201!,
                    onChanged: (v) => setState(() {
                      onEmp201 = v;
                      // Newly on it: from today, unless changed.
                      if (v && existing?.onEmp201 != true) emp201From ??= toDateStr(DateTime.now());
                    }),
                    title: const Text('On EMP201'),
                  ),
                  if (onEmp201 == true && hasFrom)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event),
                      title: Text(emp201From == null ? 'From the start' : 'From ${fmtDateDisplay(emp201From)}'),
                      trailing: emp201From == null ? null : IconButton(tooltip: 'From the start', icon: const Icon(Icons.clear), onPressed: () => setState(() => emp201From = null)),
                      onTap: () async {
                        final d = await pickDate(ctx, emp201From);
                        if (d != null) setState(() => emp201From = d);
                      },
                    ),
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
              if (method == null) {
                showProblem(ctx, 'Choose how they are paid: Bank, ATM or Cash.');
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
                  incomeTaxNo: taxNoCtrl.text.replaceAll(' ', '').isEmpty ? null : taxNoCtrl.text.replaceAll(' ', ''),
                  hasTaxNoColumn: existing?.hasTaxNoColumn ?? false,
                  leftOn: leftOn,
                  hasLeftColumn: existing?.hasLeftColumn ?? false,
                  fullNames: opt(fullNamesCtrl),
                  surname: opt(surnameCtrl),
                  currentGroupId: groupId,
                  farmId: farmId,
                  // Set in Summary (tap the worker); kept as they are.
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
                  onEmp201: onEmp201,
                  emp201From: onEmp201 == true ? emp201From : null,
                  hasEmp201From: hasFrom,
                  residentialAddress: isMember ? opt(addressCtrl) : existing?.residentialAddress,
                  utilityAccount: isMember ? opt(utilityCtrl) : existing?.utilityAccount,
                  hasAddressColumn: existing?.hasAddressColumn ?? false,
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
