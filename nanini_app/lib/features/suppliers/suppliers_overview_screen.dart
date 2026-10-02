import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/widgets/dialog_error.dart';
import '../../theme/nanini_theme.dart';
import 'suppliers_data.dart';
import 'suppliers_models.dart';

/// Every supplier and what we owe them, most owed first, with the total.
class SuppliersOverviewScreen extends StatelessWidget {
  const SuppliersOverviewScreen({super.key, required this.data, required this.onOpen});
  final SuppliersData data;

  /// Open this supplier on the Recon tab.
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (data.error != null && !data.loaded) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendlyDbError(data.error!), textAlign: TextAlign.center)));
    }
    if (!data.loaded) return const Center(child: CircularProgressIndicator());
    final accounts = data.accounts..sort((a, b) => b.due.compareTo(a.due));
    final total = accounts.fold<double>(0, (s, a) => s + a.due);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total due to suppliers', style: Theme.of(context).textTheme.titleMedium),
                      Text('${accounts.length} supplier${accounts.length == 1 ? '' : 's'}', style: const TextStyle(color: NaniniColors.muted)),
                    ],
                  ),
                ),
                Text(fmtRCents(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: NaniniColors.rustDark)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (accounts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No suppliers yet -- add the first one.', textAlign: TextAlign.center, style: TextStyle(color: NaniniColors.muted)),
          ),
        for (final a in accounts)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(a.supplier.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(_lastStatementNote(a)),
              trailing: Text(
                fmtRCents(a.due),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: a.due > 0 ? NaniniColors.ink : NaniniColors.green),
              ),
              onTap: () => onOpen(a.supplier.id),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => editSupplier(context, data),
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('Add supplier'),
        ),
      ],
    );
  }

  String _lastStatementNote(SupplierAccount a) {
    final s = a.statements.firstOrNull;
    if (s == null) return 'No statement yet';
    return s.matches
        ? 'Statement ${fmtDateDisplay(s.statement.date)}: matches'
        : 'Statement ${fmtDateDisplay(s.statement.date)}: differs by ${fmtRCents(s.difference)}';
  }
}

/// Add a supplier, or change one ([s]).
Future<void> editSupplier(BuildContext context, SuppliersData data, {Supplier? s}) async {
  final name = TextEditingController(text: s?.name);
  final account = TextEditingController(text: s?.accountNo);
  final contact = TextEditingController(text: s?.contact);
  final phone = TextEditingController(text: s?.phone);
  final email = TextEditingController(text: s?.email);
  final opening = TextEditingController(text: s == null || s.openingBalance == 0 ? '' : s.openingBalance.toStringAsFixed(2));
  var openingDate = parseDateStr(s?.openingDate) ?? DateTime.now();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: dialogTitleWithError(s == null ? 'Add supplier' : 'Change ${s.name}', error),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Supplier name')),
                const SizedBox(height: 10),
                TextField(controller: account, decoration: const InputDecoration(labelText: 'Our account number with them (optional)')),
                const SizedBox(height: 10),
                TextField(controller: contact, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Contact person (optional)')),
                const SizedBox(height: 10),
                TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
                const SizedBox(height: 10),
                TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (optional)')),
                const SizedBox(height: 10),
                TextField(
                  controller: opening,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(
                    labelText: 'Opening balance (optional)',
                    prefixText: 'R',
                    helperText: 'What we owed them before the first invoice captured here',
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(context: ctx, initialDate: openingDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setLocal(() => openingDate = d);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Opening balance on ${fmtDateDisplay(toDateStr(openingDate))}'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return setLocal(() => error = 'Type the supplier name.');
              final ob = opening.text.trim().isEmpty ? 0.0 : parseNum(opening.text);
              if (ob == null) return setLocal(() => error = 'Opening balance: type an amount.');
              final updated = Supplier(
                id: s?.id ?? '',
                name: name.text.trim(),
                accountNo: account.text,
                contact: contact.text,
                phone: phone.text,
                email: email.text,
                openingBalance: (ob * 100).roundToDouble() / 100,
                openingDate: ob == 0 ? null : toDateStr(openingDate),
              );
              try {
                await data.repo.saveSupplier(updated, isNew: s == null);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                setLocal(() => error = friendlyDbError(e));
              }
            },
            child: Text(s == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    ),
  );
}
