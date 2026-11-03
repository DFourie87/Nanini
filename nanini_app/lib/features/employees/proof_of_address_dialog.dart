import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import '../hours/hours_payslip_preview.dart' show showPdfPreview;
import 'employees_models.dart';
import 'proof_of_address_pdf.dart';

/// Employees > List > Members > Proof of address: pick the member, the farm
/// address, who signs and the date; the letter opens to print or share.
/// [members]: the members of NANINI 121 CC (on file); [farms]: to know a
/// member's farm.
Future<void> showProofOfAddress(BuildContext context, {required List<Employee> members, required List<Farm> farms}) async {
  final today = toDateStr(DateTime.now());
  final people = [for (final m in members) if (!m.hasLeftBy(today)) m]..sort((a, b) => a.legalName.toLowerCase().compareTo(b.legalName.toLowerCase()));
  if (people.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No members on file yet -- add them on the Members tab first.')));
    return;
  }
  String farmOf(Employee e) => farmAddressFor(farms.where((f) => f.id == e.farmId).firstOrNull?.name);
  var member = people.first;
  var address = farmOf(member);
  var signer = people.length > 1 ? people[1] : people.first;
  var date = DateTime.now();
  final since = TextEditingController();
  final to = TextEditingController(text: 'To whom it may concern');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Proof of address'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                key: const Key('poa_member'),
                initialValue: member.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Member'),
                items: [for (final m in people) DropdownMenuItem(value: m.id, child: Text(m.legalName, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setD(() {
                  member = people.firstWhere((m) => m.id == v);
                  address = farmOf(member);
                  // Someone else signs, when there is someone else.
                  if (signer.id == member.id && people.length > 1) signer = people.firstWhere((m) => m.id != member.id);
                }),
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
                items: [for (final e in kFarmAddresses.entries) DropdownMenuItem(value: e.key, child: Text(e.value.join(', '), overflow: TextOverflow.ellipsis))],
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
                items: [for (final m in people) DropdownMenuItem(value: m.id, child: Text(m.legalName, overflow: TextOverflow.ellipsis))],
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
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Show letter')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final letter = ProofOfAddress(
    memberName: member.legalName,
    idNumber: member.idOrPassport,
    address: kFarmAddresses[address]!,
    date: toDateStr(date),
    signedBy: signer.legalName,
    since: since.text.trim().isEmpty ? null : since.text.trim(),
    addressedTo: to.text,
  );
  await showPdfPreview(context, () => buildProofOfAddressPdf(letter), title: 'Proof of address ${member.legalName}');
}
