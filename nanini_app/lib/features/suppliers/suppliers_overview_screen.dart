import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/widgets/dialog_error.dart';
import '../../theme/nanini_theme.dart';
import 'suppliers_data.dart';
import 'suppliers_models.dart';

/// Every supplier and what we owe them, most owed first, with the total.
class SuppliersOverviewScreen extends StatelessWidget {
  const SuppliersOverviewScreen({super.key, required this.data, required this.onOpen});
  final SuppliersData data;

  /// Open this supplier's page.
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (data.error != null && !data.loaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(friendlyDbError(data.error!), textAlign: TextAlign.center),
        ),
      );
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
                      if (accounts.any((a) => a.toCheck.isNotEmpty))
                        Text(
                          '${accounts.fold<int>(0, (n, a) => n + a.toCheck.length)} from email to check',
                          style: const TextStyle(color: NaniniColors.amber, fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ),
                Text(
                  _amount(total),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _colour(total)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (accounts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No suppliers yet -- add the first one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NaniniColors.muted),
            ),
          ),
        for (final a in accounts)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(a.supplier.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: _payableNote(a) == null ? null : Text(_payableNote(a)!),
              trailing: Text(
                _amount(a.due),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _colour(a.due)),
              ),
              onTap: () => onOpen(a.supplier.id),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => editSupplier(context, data), icon: const Icon(Icons.add_business_outlined), label: const Text('Add supplier')),
      ],
    );
  }

  /// Owed: red; in credit: green, with "-" in front.
  static String _amount(double v) => v < -0.005 ? '-${fmtRCents(-v)}' : fmtRCents(v);
  static Color _colour(double v) => v > 0.005
      ? NaniniColors.red
      : v < -0.005
      ? NaniniColors.green
      : NaniniColors.muted;

  /// When what's owed must be paid, and how much: only when something is due.
  String? _payableNote(SupplierAccount a) {
    if (a.due <= 0.005) return null;
    final p = a.payable;
    if (p.isEmpty) return null;
    final today = toDateStr(DateTime.now());
    final overdue = p.where((x) => x.dueDate.compareTo(today) < 0).fold<double>(0, (s, x) => s + x.amount);
    return [
      if (overdue > 0.005) '${fmtRCents(overdue)} due now',
      for (final x in p.where((x) => x.dueDate.compareTo(today) >= 0)) '${fmtRCents(x.amount)} by ${fmtDateDisplay(x.dueDate)}',
    ].join('\n');
  }
}

/// A supplier's details: what's payable when, banking details to pay them,
/// contact and terms, and the way to change them.
List<Widget> supplierDetailsSection(BuildContext ctx, SuppliersData data, SupplierAccount a) {
  final s = a.supplier;
  final today = toDateStr(DateTime.now());
  Widget info(String label, String? value, {bool copy = false}) => (value ?? '').trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 130,
                child: Text(label, style: const TextStyle(color: NaniniColors.muted)),
              ),
              Expanded(
                child: Text(value!.trim(), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (copy)
                IconButton(
                  tooltip: 'Copy',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value.trim()));
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$label copied')));
                  },
                ),
            ],
          ),
        );
  return [
    Text('Payable', style: Theme.of(ctx).textTheme.titleMedium),
    Text(s.termsLabel, style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
    const SizedBox(height: 6),
    if (a.payable.isEmpty) Text(a.due < 0 ? 'In credit -- nothing payable.' : 'Nothing payable.', style: const TextStyle(color: NaniniColors.green)),
    for (final p in a.payable)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.dueDate.compareTo(today) < 0 ? 'Overdue -- was due ${fmtDateDisplay(p.dueDate)}' : 'By ${fmtDateDisplay(p.dueDate)}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: p.dueDate.compareTo(today) < 0 ? NaniniColors.red : null),
                  ),
                  Text(p.invoices.join(', '), style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                ],
              ),
            ),
            Text(
              fmtRCents(p.amount),
              style: TextStyle(fontWeight: FontWeight.w700, color: p.dueDate.compareTo(today) < 0 ? NaniniColors.red : null),
            ),
          ],
        ),
      ),
    const Divider(height: 24),
    Text('Banking details', style: Theme.of(ctx).textTheme.titleMedium),
    const SizedBox(height: 4),
    if (!s.hasBanking) const Text('None yet -- add them with Change details.', style: TextStyle(color: NaniniColors.muted)),
    info('Bank', s.bankName),
    info('Account holder', s.bankAccountHolder, copy: true),
    info('Account number', s.bankAccountNo, copy: true),
    info('Branch code', s.bankBranchCode, copy: true),
    info('Payment reference', s.paymentReference ?? s.accountNo, copy: true),
    const Divider(height: 24),
    Text('Contact', style: Theme.of(ctx).textTheme.titleMedium),
    const SizedBox(height: 4),
    info('Supplier of', s.category),
    if ((s.category ?? '').trim().isNotEmpty)
      info('Contra account', switch (contraAccount(s.category, data.glAccounts)) {
        null => 'Not found in the chart of accounts -- put its code in "Supplier of", e.g. 3740 - Fertilizer',
        final code => data.accountLabel(code),
      }),
    info('Lines with VAT to', s.vatAccount),
    info('Our account no.', s.accountNo),
    if (s.openingBalance != 0) info('Opening balance', '${fmtRCents(s.openingBalance)} on ${s.openingDate == null ? '?' : fmtDateDisplay(s.openingDate)}'),
    info('Contact person', s.contact),
    info('Phone', s.phone, copy: true),
    info('Email', s.email, copy: true),
    info('Proof of payment to', s.popEmail, copy: true),
    info('Address', s.address),
    info('VAT number', s.vatNo),
    const SizedBox(height: 8),
    OutlinedButton.icon(
      onPressed: () => editSupplier(ctx, data, s: s),
      icon: const Icon(Icons.edit_outlined),
      label: const Text('Change details'),
    ),
  ];
}

/// Add a supplier, or change one ([s]).
Future<void> editSupplier(BuildContext context, SuppliersData data, {Supplier? s}) async {
  final name = TextEditingController(text: s?.name);
  final account = TextEditingController(text: s?.accountNo);
  final contact = TextEditingController(text: s?.contact);
  final phone = TextEditingController(text: s?.phone);
  final email = TextEditingController(text: s?.email);
  final opening = TextEditingController(text: s == null || s.openingBalance == 0 ? '' : s.openingBalance.toStringAsFixed(2));
  // Unless set: the start of the tax year (1 March), not today -- an opening
  // balance dated today would replace everything captured before it.
  final now = DateTime.now();
  var openingDate = parseDateStr(s?.openingDate) ?? DateTime(now.month >= 3 ? now.year : now.year - 1, 3, 1);
  final bank = TextEditingController(text: s?.bankName);
  final holder = TextEditingController(text: s?.bankAccountHolder);
  final bankAcc = TextEditingController(text: s?.bankAccountNo);
  final branch = TextEditingController(text: s?.bankBranchCode);
  final payRef = TextEditingController(text: s?.paymentReference);
  final pop = TextEditingController(text: s?.popEmail);
  final address = TextEditingController(text: s?.address);
  final vat = TextEditingController(text: s?.vatNo);
  final category = TextEditingController(text: s?.category);
  final vatContra = TextEditingController(text: s?.vatAccount);
  var terms = s?.termsKind ?? PaymentTerms.daysFromInvoice;
  final days = TextEditingController(text: '${s?.termsDays ?? 30}');
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
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Supplier name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: account,
                  decoration: const InputDecoration(labelText: 'Our account number with them (optional)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: contact,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Contact person (optional)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone (optional)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                    helperText: 'Where their invoices and statements come from -- several: separate with commas',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: opening,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(
                    labelText: 'Opening balance (optional)',
                    prefixText: 'R',
                    helperText: 'What we owed them when the day below began (e.g. 1 March)',
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
                const SizedBox(height: 16),
                const Text('Payment terms', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                SegmentedButton<PaymentTerms>(
                  segments: const [
                    ButtonSegment(value: PaymentTerms.daysFromInvoice, label: Text('From invoice')),
                    ButtonSegment(value: PaymentTerms.daysFromStatement, label: Text('From statement')),
                  ],
                  selected: {terms},
                  onSelectionChanged: (v) => setLocal(() => terms = v.first),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: days,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Days',
                    helperText: terms == PaymentTerms.daysFromStatement
                        ? 'Days after the month-end statement (e.g. 30)'
                        : 'Days after the invoice date (0 = cash)',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Banking details', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(
                  controller: bank,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Bank'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: holder,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Account holder'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bankAcc,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Account number'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: branch,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Branch code'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: payRef,
                  decoration: const InputDecoration(labelText: 'Payment reference (e.g. our account number)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pop,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Send proof of payment to (email)'),
                ),
                const SizedBox(height: 16),
                const Text('Other', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(
                  controller: category,
                  decoration: const InputDecoration(labelText: 'Supplier of / contra account (e.g. 3740 - Fertilizer)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: vatContra,
                  decoration: const InputDecoration(
                    labelText: 'Contra for invoice lines with VAT (optional)',
                    helperText: 'e.g. 4800 for Omnia\'s transport -- its zero-rated lines go to the account above',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: vat,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'VAT number'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: address,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Address'),
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
              final d = int.tryParse(days.text.trim());
              if (d == null || d < 0 || d > 365) return setLocal(() => error = 'Payment terms: type the number of days.');
              final acc = bankAcc.text.replaceAll(' ', '');
              if (acc.isNotEmpty && !RegExp(r'^\d{5,16}$').hasMatch(acc)) return setLocal(() => error = 'Bank account number: numbers only.');
              final updated = Supplier(
                id: s?.id ?? '',
                name: name.text.trim(),
                accountNo: account.text,
                contact: contact.text,
                phone: phone.text,
                email: email.text,
                openingBalance: (ob * 100).roundToDouble() / 100,
                openingDate: ob == 0 ? null : toDateStr(openingDate),
                bankName: bank.text,
                bankAccountHolder: holder.text,
                bankAccountNo: acc,
                bankBranchCode: branch.text,
                paymentReference: payRef.text,
                termsKind: terms,
                termsDays: d,
                popEmail: pop.text,
                address: address.text,
                vatNo: vat.text,
                category: category.text,
                vatAccount: vatContra.text,
              );
              try {
                await data.repo.saveSupplier(updated, isNew: s == null);
                await data.reload();
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
