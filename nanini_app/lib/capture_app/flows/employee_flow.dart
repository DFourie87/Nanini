import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/capture/capture_models.dart';
import '../../features/employees/employees_models.dart' show employeeDetailsProblem;
import '../../theme/nanini_theme.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../ref_data.dart';

enum _Action { add, change, remove }

enum _S { where, action, person, name, idNo, fullNames, surname, farm, pay, bank, account, phone, check }

/// Employee details: first the farm, then a new worker there, changed
/// details of one of its workers, or a worker who left.
/// Goes to the hub's Employees app to approve. The name is what everyone
/// calls them; the ID/passport can come later, but once it's typed the full
/// names and surname (as on the ID) are needed too.
class EmployeeFlow extends StatefulWidget {
  const EmployeeFlow({super.key});
  @override
  State<EmployeeFlow> createState() => _EmployeeFlowState();
}

class _EmployeeFlowState extends State<EmployeeFlow> {
  _Action? action;

  /// The farm chosen first: new workers are added there, and its workers
  /// are listed first for a change or someone who left.
  RefItem? atFarm;
  RefPerson? person;
  final nameCtrl = TextEditingController();
  final idCtrl = TextEditingController();
  final fullNamesCtrl = TextEditingController();
  final surnameCtrl = TextEditingController();
  RefItem? farm;

  /// How they're paid: 'cash', 'bank' or 'atm' (null = not chosen yet).
  String? method;
  final bankCtrl = TextEditingController();
  final accountCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  int i = 0;

  /// Bank transfer needs the bank and account number; ATM the phone number
  /// (it goes on the payslip with the access code).
  List<_S> get _paySteps => [_S.pay, if (method == 'bank') ...[_S.bank, _S.account], if (method == 'atm') _S.phone];

  List<_S> get steps => switch (action) {
        _Action.add => [_S.where, _S.action, _S.name, _S.idNo, _S.fullNames, _S.surname, ..._paySteps, _S.check],
        _Action.change => [_S.where, _S.action, _S.person, _S.name, _S.idNo, _S.fullNames, _S.surname, _S.farm, ..._paySteps, _S.check],
        _Action.remove => const [_S.where, _S.action, _S.person, _S.check],
        null => const [_S.where, _S.action],
      };

  bool get idTyped => idCtrl.text.trim().isNotEmpty;

  void next() => setState(() => i = (i + 1).clamp(0, steps.length - 1));
  void back() => i == 0 ? Navigator.of(context).pop() : setState(() => i--);
  void _need(String msg) => showNeed(context, msg);

  @override
  void dispose() {
    for (final c in [nameCtrl, idCtrl, fullNamesCtrl, surnameCtrl, bankCtrl, accountCtrl, phoneCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Starts from everything the office has on this worker.
  void _pickPerson(RefPerson p, RefData ref) {
    setState(() {
      person = p;
      nameCtrl.text = p.knownName;
      idCtrl.text = p.idOrPassport ?? '';
      fullNamesCtrl.text = p.fullNames ?? '';
      surnameCtrl.text = p.surname ?? '';
      farm = ref.farms.where((f) => f.id == p.farmId).firstOrNull;
      method = p.paymentMethod ?? 'cash';
      bankCtrl.text = p.bankName ?? '';
      accountCtrl.text = p.bankAccountNo ?? '';
      phoneCtrl.text = p.phoneNumber ?? '';
    });
    next();
  }

  /// What differs from what the office has (for a change), or everything
  /// typed (for a new worker).
  Map<String, dynamic> _fields() {
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final p = person;
    final isNew = action == _Action.add;
    return {
      if (isNew || t(nameCtrl) != p?.knownName) 'name': ?t(nameCtrl),
      if (isNew || t(idCtrl) != (p?.idOrPassport ?? '').trim().nullIfEmpty) 'id_or_passport': ?t(idCtrl),
      if (isNew || t(fullNamesCtrl) != (p?.fullNames ?? '').trim().nullIfEmpty) 'full_names': ?t(fullNamesCtrl),
      if (isNew || t(surnameCtrl) != (p?.surname ?? '').trim().nullIfEmpty) 'surname': ?t(surnameCtrl),
      if (farm != null && (isNew || farm!.id != p?.farmId)) ...{'farm_id': farm!.id, 'farm_name': farm!.name},
      if (method != null && (isNew || method != (p?.paymentMethod ?? 'cash'))) 'payment_method': method,
      if (method == 'bank' && (isNew || t(bankCtrl) != (p?.bankName ?? '').trim().nullIfEmpty)) 'bank_name': ?t(bankCtrl),
      if (method == 'bank' && (isNew || t(accountCtrl) != (p?.bankAccountNo ?? '').trim().nullIfEmpty)) 'bank_account_no': ?t(accountCtrl),
      if (method == 'atm' && (isNew || t(phoneCtrl) != (p?.phoneNumber ?? '').trim().nullIfEmpty)) 'phone_number': ?t(phoneCtrl),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<CaptureStore>().ref;
    final s = steps[i];
    StepPage page(String q, Widget child, {VoidCallback? onNext, String? hint, String nextLabel = 'NEXT', IconData nextIcon = Icons.arrow_forward}) =>
        StepPage(task: 'Employee details', step: i + 1, steps: steps.length, question: q, hint: hint, onBack: back, onNext: onNext, nextLabel: nextLabel, nextIcon: nextIcon, child: child);

    Widget textStep(TextEditingController c,
            {required String example, TextCapitalization caps = TextCapitalization.words, String? skipLabel, TextInputType? keyboard, List<Widget> below = const []}) =>
        ListView(
          children: [
            TextField(
              controller: c,
              autofocus: true,
              style: const TextStyle(fontSize: 24),
              textCapitalization: caps,
              keyboardType: keyboard,
              decoration: InputDecoration(hintText: example),
              onChanged: (_) => setState(() {}),
            ),
            if (skipLabel != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // Back to what the office has (nothing, for a new worker).
                  if (c == idCtrl) c.text = person?.idOrPassport ?? '';
                  next();
                },
                child: Text(skipLabel, style: const TextStyle(fontSize: 18)),
              ),
            ],
            ...below,
          ],
        );

    switch (s) {
      case _S.where:
        return page(
          'Which farm?',
          ref.farms.isEmpty
              ? const EmptyListNote()
              : ListView(
                  children: [
                    for (final f in ref.farms)
                      BigChoice(
                        icon: Icons.agriculture,
                        label: f.name,
                        selected: atFarm?.id == f.id,
                        onTap: () {
                          setState(() {
                            if (atFarm?.id != f.id) person = null;
                            atFarm = f;
                            if (action == _Action.add) farm = f;
                          });
                          next();
                        },
                      ),
                  ],
                ),
          onNext: atFarm == null ? null : next,
        );
      case _S.action:
        return page(
          'What must change at ${atFarm?.name ?? 'the farm'}?',
          ListView(
            children: [
              BigChoice(
                emoji: '🆕',
                label: 'NEW WORKER',
                selected: action == _Action.add,
                onTap: () {
                  setState(() {
                    action = _Action.add;
                    person = null;
                    for (final c in [nameCtrl, idCtrl, fullNamesCtrl, surnameCtrl, bankCtrl, accountCtrl, phoneCtrl]) {
                      c.clear();
                    }
                    farm = atFarm;
                    method = null;
                  });
                  next();
                },
              ),
              BigChoice(
                emoji: '✏️',
                label: 'CHANGE DETAILS',
                selected: action == _Action.change,
                onTap: () {
                  setState(() => action = _Action.change);
                  next();
                },
              ),
              BigChoice(
                emoji: '👋',
                label: 'WORKER LEFT',
                highlight: 'LEFT',
                highlightColor: NaniniColors.red,
                selected: action == _Action.remove,
                onTap: () {
                  setState(() => action = _Action.remove);
                  next();
                },
              ),
            ],
          ),
        );
      case _S.person:
        return page(
          action == _Action.remove ? 'Who left?' : 'Whose details?',
          // This farm's workers; others under FROM OTHER FARM.
          PersonPicker(people: ref.people, farmId: atFarm?.id, selectedIds: {?person?.id}, onPick: (p) => _pickPerson(p, ref)),
        );
      case _S.name:
        return page(
          'Name?',
          textStep(nameCtrl, example: 'e.g. Sipho'),
          hint: 'The name everyone knows them by',
          onNext: () => nameCtrl.text.trim().isEmpty ? _need('Type the name') : next(),
        );
      case _S.idNo:
        final onFile = person?.hasId == true;
        final known = (person?.idOrPassport ?? '').isNotEmpty;
        return page(
          'ID or passport number?',
          textStep(idCtrl, example: 'e.g. 9001015009087', caps: TextCapitalization.characters, skipLabel: onFile ? 'NO CHANGE' : 'ADD LATER'),
          hint: known
              ? 'This is what the office has. Change it only if it is wrong.'
              : onFile
                  ? 'The office has one. Only type it to change it.'
                  : 'Not with you now? Press ADD LATER',
          onNext: () {
            if (idTyped) {
              final problem = employeeDetailsProblem(name: 'x', idOrPassport: idCtrl.text, fullNames: 'x', surname: 'x');
              if (problem != null) return _need(problem);
            }
            next();
          },
        );
      case _S.fullNames:
        return page(
          'Full names (as on the ID)?',
          textStep(fullNamesCtrl, example: 'e.g. Sipho Johannes', skipLabel: idTyped ? null : 'ADD LATER'),
          hint: idTyped ? 'Needed with an ID number' : 'All first names, as on the ID',
          onNext: () => idTyped && fullNamesCtrl.text.trim().isEmpty ? _need('Type the full names as on the ID') : next(),
        );
      case _S.surname:
        return page(
          'Surname (as on the ID)?',
          textStep(surnameCtrl, example: 'e.g. Mokoena', skipLabel: idTyped ? null : 'ADD LATER'),
          hint: idTyped ? 'Needed with an ID number' : null,
          onNext: () => idTyped && surnameCtrl.text.trim().isEmpty ? _need('Type the surname as on the ID') : next(),
        );
      case _S.farm:
        return page(
          'Which farm do they work on?',
          ref.farms.isEmpty
              ? const EmptyListNote()
              : ListView(
                  children: [
                    for (final f in ref.farms)
                      BigChoice(
                        icon: Icons.agriculture,
                        label: f.name,
                        selected: farm?.id == f.id,
                        onTap: () {
                          setState(() => farm = f);
                          next();
                        },
                      ),
                  ],
                ),
          onNext: farm == null ? null : next,
        );
      case _S.pay:
        return page(
          'How are they paid?',
          ListView(
            children: [
              for (final (key, emoji, label) in const [('cash', '💵', 'CASH'), ('bank', '🏦', 'BANK TRANSFER'), ('atm', '🏧', 'ATM')])
                BigChoice(
                  emoji: emoji,
                  label: label,
                  selected: method == key,
                  onTap: () {
                    setState(() => method = key);
                    next();
                  },
                ),
            ],
          ),
          onNext: method == null ? null : next,
        );
      case _S.bank:
        return page(
          'Which bank?',
          textStep(bankCtrl, example: 'Or type the bank', below: [
            const SizedBox(height: 12),
            for (final b in const ['Capitec', 'FNB', 'ABSA', 'Standard Bank', 'Nedbank', 'TymeBank', 'African Bank', 'Discovery Bank'])
              BigChoice(
                icon: Icons.account_balance,
                label: b,
                selected: bankCtrl.text.trim().toLowerCase() == b.toLowerCase(),
                onTap: () {
                  setState(() => bankCtrl.text = b);
                  next();
                },
              ),
          ]),
          onNext: () => bankCtrl.text.trim().isEmpty ? _need('Choose or type the bank') : next(),
        );
      case _S.account:
        return page(
          'Account number?',
          textStep(accountCtrl, example: 'e.g. 1234567890', caps: TextCapitalization.none, keyboard: TextInputType.number),
          hint: 'As on the bank card or bank letter',
          onNext: () {
            final n = accountCtrl.text.replaceAll(' ', '');
            if (!RegExp(r'^\d{6,16}$').hasMatch(n)) return _need('Type the account number (numbers only)');
            next();
          },
        );
      case _S.phone:
        return page(
          'Phone number?',
          textStep(phoneCtrl, example: 'e.g. 072 123 4567', caps: TextCapitalization.none, keyboard: TextInputType.phone),
          hint: 'Goes on the payslip with the ATM access code',
          onNext: () {
            final n = phoneCtrl.text.replaceAll(RegExp(r'[\s-]'), '');
            if (!RegExp(r'^(0\d{9}|\+27\d{9})$').hasMatch(n)) return _need('Type a 10-digit phone number, e.g. 0721234567');
            next();
          },
        );
      case _S.check:
        final f = _fields();
        return page(
          'Is this right?',
          ListView(
            children: [
              if (action == _Action.remove)
                CheckLine(icon: Icons.logout, color: NaniniColors.red, text: '${person?.name} has left the farm')
              else ...[
                if (action == _Action.change) CheckLine(icon: Icons.person, text: 'Change for ${person?.name}'),
                if (f['name'] != null) CheckLine(icon: Icons.badge_outlined, text: 'Name: ${f['name']}'),
                if (f['id_or_passport'] != null) CheckLine(icon: Icons.credit_card, text: 'ID: ${f['id_or_passport']}'),
                if (f['full_names'] != null || f['surname'] != null)
                  CheckLine(icon: Icons.assignment_ind_outlined, text: '${f['full_names'] ?? ''} ${f['surname'] ?? ''}'.trim()),
                if (f['farm_name'] != null) CheckLine(icon: Icons.agriculture, text: '${f['farm_name']}'),
                if (f['payment_method'] != null || f['bank_name'] != null || f['bank_account_no'] != null || f['phone_number'] != null)
                  CheckLine(
                    icon: Icons.payments_outlined,
                    text: switch (method) {
                      'bank' => 'Bank transfer: ${bankCtrl.text.trim()} ${accountCtrl.text.trim()}',
                      'atm' => 'ATM: phone ${phoneCtrl.text.trim()}',
                      _ => 'Paid in cash',
                    },
                  ),
                if (action == _Action.change && f.isEmpty) const CheckLine(icon: Icons.info_outline, color: NaniniColors.amber, text: 'Nothing changed'),
              ],
            ],
          ),
          hint: 'If something is wrong, press BACK',
          nextLabel: 'SAVE',
          nextIcon: Icons.check,
          onNext: _save,
        );
    }
  }

  Future<void> _save() async {
    final fields = _fields();
    if (action == _Action.change && fields.isEmpty) return _need('Nothing was changed -- press BACK');
    if (action == _Action.add && fields['farm_id'] == null) return _need('Choose the farm -- press BACK');
    final store = context.read<CaptureStore>();
    final name = fields['name'] ?? person?.name ?? '';
    await store.add(
      CaptureModule.employee,
      {
        'action': action!.name,
        if (person != null) ...{'employee_id': person!.id, 'employee_name': person!.name},
        if (action != _Action.remove) ...fields,
      },
      switch (action!) {
        _Action.add => 'New worker: $name',
        _Action.change => 'Details: ${person?.name}',
        _Action.remove => 'Left: ${person?.name}',
      },
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(task: 'worker', another: (_) => const EmployeeFlow())));
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
