import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import '../hours/hours_payslip_preview.dart' show showPdfPreview;
import 'employees_models.dart';
import 'proof_of_address_pdf.dart';
import 'proof_of_address_utility.dart';
import '../../core/widgets/dialog_error.dart';

/// Employees > List > Members > Proof of address: pick the member, the farm
/// address, who signs and the date; the letter opens to print or share.
/// [members]: the members of NANINI 121 CC (on file); [farms]: to know a
/// member's farm.
/// [loadUtility]: the member's latest Eskom bill (a stand-in in tests).
Future<void> showProofOfAddress(BuildContext context,
    {required List<Employee> members,
    required List<Farm> farms,
    Future<(UtilityBill?, String?)> Function(String account, String letterDate) loadUtility = loadUtilityBill}) async {
  final today = toDateStr(DateTime.now());
  final people = [for (final m in members) if (!m.hasLeftBy(today)) m]..sort((a, b) => a.legalName.toLowerCase().compareTo(b.legalName.toLowerCase()));
  if (people.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No members on file yet -- add them on the Members tab first.')));
    return;
  }
  // The member's own address (on file, as on the CK2) first, else their farm's.
  const own = 'own';
  String defaultAddress(Employee e) =>
      addressLines(e.residentialAddress).isNotEmpty ? own : farmAddressFor(farms.where((f) => f.id == e.farmId).firstOrNull?.name);
  // Two members can share their full names (a father and son): the name
  // they're known by too.
  String label(Employee e) {
    final known = e.firstName.trim();
    return known.isEmpty || e.legalName.toLowerCase().contains(known.toLowerCase()) ? e.legalName : '${e.legalName} ($known)';
  }

  var member = people.first;
  var address = defaultAddress(member);
  var signer = people.length > 1 ? people[1] : people.first;
  var date = DateTime.now();
  final since = TextEditingController();
  final to = TextEditingController(text: 'To whom it may concern');
  String? error;
  var loading = false;
  UtilityBill? utility;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: dialogTitleWithError('Proof of address', error),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                key: const Key('poa_member'),
                initialValue: member.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Member'),
                items: [for (final m in people) DropdownMenuItem(value: m.id, child: Text(label(m), overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setD(() {
                  member = people.firstWhere((m) => m.id == v);
                  address = defaultAddress(member);
                  // Someone else signs, when there is someone else.
                  if (signer.id == member.id && people.length > 1) signer = people.firstWhere((m) => m.id != member.id);
                }),
              ),
              if ((member.utilityAccount ?? '').trim().isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('No Eskom account on file: the letter goes without a utility bill (add it on the Members tab).',
                      style: TextStyle(color: NaniniColors.amber, fontSize: 12)),
                ),
              if (!member.hasId)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('No ID number on file: the letter goes without it (add it on the Members tab).', style: TextStyle(color: NaniniColors.amber, fontSize: 12)),
                ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('poa_address_$address'),
                initialValue: address,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Address'),
                items: [
                  if (addressLines(member.residentialAddress).isNotEmpty)
                    DropdownMenuItem(value: own, child: Text('Own: ${addressLines(member.residentialAddress).join(', ')}', overflow: TextOverflow.ellipsis)),
                  for (final e in kFarmAddresses.entries) DropdownMenuItem(value: e.key, child: Text(e.value.join(', '), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setD(() => address = v ?? address),
              ),
              const SizedBox(height: 8),
              TextField(controller: since, decoration: const InputDecoration(labelText: 'Living there since (optional)', hintText: 'e.g. 2005')),
              const SizedBox(height: 8),
              TextField(controller: to, decoration: const InputDecoration(labelText: 'Addressed to')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('poa_signer_${signer.id}'),
                initialValue: signer.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Signed by'),
                items: [for (final m in people) DropdownMenuItem(value: m.id, child: Text(label(m), overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setD(() => signer = people.firstWhere((m) => m.id == v)),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (picked != null) setD(() => date = picked);
                },
                child: InputDecorator(decoration: const InputDecoration(labelText: 'Date'), child: Text(fmtDateDisplay(toDateStr(date)))),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: loading
                ? null
                : () async {
                    // The latest Eskom bill, not older than 3 months: else no letter.
                    final account = (member.utilityAccount ?? '').trim();
                    if (account.isEmpty) return Navigator.pop(ctx, true);
                    setD(() {
                      loading = true;
                      error = null;
                    });
                    try {
                      final (bill, problem) = await loadUtility(account, toDateStr(date));
                      if (!ctx.mounted) return;
                      if (bill == null) return setD(() => error = problem);
                      utility = bill;
                      Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) setD(() => error = 'Could not get the Eskom bill: $e');
                    } finally {
                      if (ctx.mounted) setD(() => loading = false);
                    }
                  },
            child: Text(loading ? 'Getting the Eskom bill…' : 'Show letter'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final letter = ProofOfAddress(
    memberName: member.legalName,
    idNumber: member.idOrPassport,
    address: address == own ? addressLines(member.residentialAddress) : kFarmAddresses[address]!,
    note: address == own ? null : addressNote(address),
    // The CC's address at the top: the farm chosen, else its registered office.
    letterhead: address == own ? kFarmAddresses[kRegisteredOffice] : null,
    utilityPage: utility?.page,
    utilityLabel: utility?.label,
    date: toDateStr(date),
    signedBy: signer.legalName,
    since: since.text.trim().isEmpty ? null : since.text.trim(),
    addressedTo: to.text,
  );
  await showPdfPreview(context, () => buildProofOfAddressPdf(letter), title: 'Proof of address ${member.legalName}');
}
