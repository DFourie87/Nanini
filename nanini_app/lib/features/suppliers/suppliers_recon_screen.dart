import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../hours/pdf_view_page.dart';
import 'suppliers_data.dart';
import 'suppliers_models.dart';
import 'suppliers_overview_screen.dart';

/// The work page for one supplier: upload invoices, credit notes and
/// statements (PDF), type in payments, see the account with its running
/// balance, and each statement checked against it.
class SuppliersReconScreen extends StatelessWidget {
  const SuppliersReconScreen({super.key, required this.data, required this.supplierId, required this.onSupplier});
  final SuppliersData data;
  final String? supplierId;
  final ValueChanged<String> onSupplier;

  @override
  Widget build(BuildContext context) {
    if (!data.loaded) return const Center(child: CircularProgressIndicator());
    final accounts = data.accounts..sort((a, b) => a.supplier.name.toLowerCase().compareTo(b.supplier.name.toLowerCase()));
    if (accounts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add a supplier first.', style: TextStyle(color: NaniniColors.muted)),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: () => editSupplier(context, data), icon: const Icon(Icons.add_business_outlined), label: const Text('Add supplier')),
            ],
          ),
        ),
      );
    }
    final a = accounts.where((x) => x.supplier.id == supplierId).firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        DropdownButtonFormField<String>(
          initialValue: a?.supplier.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Supplier'),
          items: [for (final x in accounts) DropdownMenuItem(value: x.supplier.id, child: Text(x.supplier.name))],
          onChanged: (id) {
            if (id != null) onSupplier(id);
          },
        ),
        const SizedBox(height: 12),
        if (a == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Choose a supplier to work on.', textAlign: TextAlign.center, style: TextStyle(color: NaniniColors.muted)),
          )
        else ..._account(context, a),
      ],
    );
  }

  List<Widget> _account(BuildContext context, SupplierAccount a) {
    final checks = a.statements;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.supplier.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if ((a.supplier.accountNo ?? '').isNotEmpty) Text('Account ${a.supplier.accountNo}', style: const TextStyle(color: NaniniColors.muted)),
                    const Text('Amount due', style: TextStyle(color: NaniniColors.muted)),
                  ],
                ),
              ),
              Text(fmtRCents(a.due), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: NaniniColors.rustDark)),
              IconButton(tooltip: 'Change supplier details', icon: const Icon(Icons.edit_outlined), onPressed: () => editSupplier(context, data, s: a.supplier)),
            ],
          ),
        ),
      ),
      if (a.toCheck.isNotEmpty) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text('From email -- to check (${a.toCheck.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: NaniniColors.amber)),
            ),
            if (_readyToConfirm(a.toCheck).isNotEmpty)
              TextButton.icon(
                onPressed: () => _confirmAll(context, data, _readyToConfirm(a.toCheck)),
                icon: const Icon(Icons.done_all),
                label: Text('Confirm all (${_readyToConfirm(a.toCheck).length})'),
              ),
          ],
        ),
        const Text('Brought in from Gmail. Check each against its PDF and confirm -- only then does it count.',
            style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
        const SizedBox(height: 4),
        for (final d in a.toCheck)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: NaniniColors.amber)),
            child: ListTile(
              leading: const Icon(Icons.mark_email_unread_outlined, color: NaniniColors.amber),
              title: Text('${docKindLabel(d.kind)}${(d.reference ?? '').isEmpty ? '' : ' ${d.reference}'} · ${fmtDateDisplay(d.date)}'),
              subtitle: Text([
                if ((d.emailSubject ?? '').isNotEmpty) d.emailSubject!,
                if ((d.fileName ?? '').isNotEmpty) d.fileName!,
              ].join('\n')),
              trailing: Text(d.amount == 0 ? 'amount ?' : fmtRCents(d.amount),
                  style: TextStyle(fontWeight: FontWeight.w700, color: d.amount == 0 ? NaniniColors.red : null)),
              onTap: () => confirmEmailDoc(context, data, a.supplier, d),
            ),
          ),
      ],
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => addSupplierDoc(context, data, a.supplier, SupplierDocKind.invoice),
            icon: const Icon(Icons.upload_file),
            label: const Text('Invoice'),
          ),
          FilledButton.icon(
            onPressed: () => addSupplierDoc(context, data, a.supplier, SupplierDocKind.statement),
            icon: const Icon(Icons.upload_file),
            label: const Text('Statement'),
          ),
          OutlinedButton.icon(
            onPressed: () => addSupplierDoc(context, data, a.supplier, SupplierDocKind.creditNote),
            icon: const Icon(Icons.upload_file),
            label: const Text('Credit note'),
          ),
          OutlinedButton.icon(
            onPressed: () => addSupplierPayment(context, data, a.supplier),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Payment'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Text('Statements', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      if (checks.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('No statement uploaded yet.', style: TextStyle(color: NaniniColors.muted)),
        ),
      for (final c in checks) _StatementCard(check: c, data: data),
      const SizedBox(height: 8),
      const Text('The account line by line, for any period: the Account tab.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
    ];
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({required this.check, required this.data});
  final StatementCheck check;
  final SuppliersData data;

  @override
  Widget build(BuildContext context) {
    final s = check.statement;
    final color = !check.checked ? NaniniColors.ink : check.matches ? NaniniColors.green : NaniniColors.red;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: s.filePath == null ? null : () => openSupplierPdf(context, data, s),
        onLongPress: () => _deleteDoc(context, data, s),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(!check.checked ? Icons.receipt_long_outlined : check.matches ? Icons.check_circle : Icons.error_outline, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Statement ${fmtDateDisplay(s.date)}${(s.reference ?? '').isEmpty ? '' : ' · ${s.reference}'}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (s.filePath != null) const Icon(Icons.picture_as_pdf_outlined, color: NaniniColors.muted),
                ],
              ),
              const SizedBox(height: 6),
              _row('Statement says we owe', s.amount, bold: !check.checked),
              if (check.overdue > 0) _row('Already due', check.overdue),
              if (check.overdue > 0 || s.dueDate != null) _row('Due by ${fmtDateDisplay(check.currentDueDate)}', check.current),
              if (check.checked) ...[
                _row('Our invoices and payments to ${fmtDateDisplay(s.date)}', check.ours!),
                _row('Difference', check.difference, bold: true, color: color),
                const SizedBox(height: 4),
                Text(
                  check.matches
                      ? 'Matches -- nothing to follow up.'
                      : check.difference > 0
                          ? 'The statement shows more: an invoice not captured here, interest, or a payment they haven\'t received.'
                          : 'The statement shows less: a payment or credit note captured here they don\'t show, or an invoice captured twice.',
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ] else ...[
                const SizedBox(height: 4),
                const Text('No invoices captured up to this statement -- nothing to check it against.',
                    style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, double v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null, color: color))),
            Text(fmtRCents(v), style: TextStyle(fontWeight: bold ? FontWeight.w700 : null, color: color)),
          ],
        ),
      );
}

/// A line of a supplier's account: tap opens its PDF, a long press removes it.
class LedgerTile extends StatelessWidget {
  const LedgerTile({super.key, required this.line, required this.data});
  final LedgerLine line;
  final SuppliersData data;

  /// An Eskom bill's account summary: brought forward, the payments it
  /// received (checked against the bank payments), this month's charges
  /// excl. VAT, the VAT, interest, and its amount due.
  String _billSummary(SupplierDoc d) {
    final lines = data.docLines.where((l) => l.docId == d.id);
    final excl = lines.where((l) => (l.vat ?? 0) != 0).fold<double>(0, (t, l) => t + l.excl);
    final other = lines.where((l) => (l.vat ?? 0) == 0).fold<double>(0, (t, l) => t + l.excl);
    bool inBank(({String? date, double amount}) p) {
      final day = parseDateStr(p.date);
      return (data.payments ?? const <SupplierPayment>[]).any((x) =>
          x.supplierId == d.supplierId &&
          (x.amount - p.amount).abs() < 0.01 &&
          (day == null || (parseDateStr(x.date)!.difference(day).inDays).abs() <= 7));
    }

    return [
      if (d.broughtForward != null) 'Brought forward ${fmtRCents(d.broughtForward!)}',
      for (final p in d.paymentsReceived)
        'Paid ${fmtRCents(p.amount)}${p.date == null ? '' : ' ${fmtDateDisplay(p.date)}'} ${inBank(p) ? '✓ bank' : '-- not in the bank payments'}',
      if (excl != 0) 'Charges excl. ${fmtRCents(excl)}',
      'VAT ${fmtRCents(d.vatAmount ?? 0)}',
      if (other != 0) 'Interest etc. ${fmtRCents(other)}',
      'Amount due ${fmtRCents(d.amount)}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final doc = line.doc;
    final pay = line.payment;
    final isStatementLine = line.kind == LedgerKind.statement;
    final bill = line.kind == LedgerKind.invoice && doc != null && doc.isBill ? _billSummary(doc) : null;
    return ListTile(
      dense: true,
      isThreeLine: bill != null,
      leading: Icon(
        isStatementLine
            ? Icons.receipt_long_outlined
            : pay != null
            ? Icons.payments_outlined
            : doc == null
                ? Icons.start
                : doc.filePath != null
                    ? Icons.picture_as_pdf_outlined
                    : Icons.receipt_outlined,
        color: line.amount < 0 ? NaniniColors.green : NaniniColors.muted,
      ),
      title: Text(line.label),
      subtitle: Text('${fmtDateDisplay(line.date)}${doc?.dueDate == null || isStatementLine ? '' : ' · due ${fmtDateDisplay(doc!.dueDate)}'}'
          '${bill == null ? '' : '\n$bill'}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isStatementLine) ...[
            Text(fmtRCents(line.balance), style: const TextStyle(fontWeight: FontWeight.w700, color: NaniniColors.ink)),
            Text(line.amount.abs() < 0.005 || line.label == 'Balance per statement' ? 'per statement' : '${line.amount > 0 ? '+' : '-'}${fmtRCents(line.amount.abs())}',
                style: const TextStyle(fontSize: 11, color: NaniniColors.muted)),
          ] else ...[
            Text(line.amount < 0 ? '-${fmtRCents(-line.amount)}' : fmtRCents(line.amount),
                style: TextStyle(fontWeight: FontWeight.w700, color: line.amount < 0 ? NaniniColors.green : NaniniColors.ink)),
            Text('owed ${fmtRCents(line.balance)}', style: const TextStyle(fontSize: 11, color: NaniniColors.muted)),
          ],
        ],
      ),
      onTap: doc?.filePath == null ? null : () => openSupplierPdf(context, data, doc!),
      onLongPress: doc != null
          ? () => _deleteDoc(context, data, doc)
          : pay != null
              ? () async {
                  if (await confirmDialog(context,
                      title: 'Remove payment?', message: '${fmtRCents(pay.amount)} on ${fmtDateDisplay(pay.date)}', confirmLabel: 'Remove', danger: true)) {
                    try {
                      await data.repo.deletePayment(pay.id);
                    } catch (e) {
                      if (context.mounted) showToast(context, friendlyDbError(e), isError: true);
                    }
                  }
                }
              : null,
    );
  }
}

Future<void> _deleteDoc(BuildContext context, SuppliersData data, SupplierDoc d) async {
  final ok = await confirmDialog(
    context,
    title: 'Remove ${docKindLabel(d.kind).toLowerCase()}?',
    message: '${docKindLabel(d.kind)} ${d.reference ?? ''} of ${fmtDateDisplay(d.date)} (${fmtRCents(d.amount)}) and its PDF.',
    confirmLabel: 'Remove',
    danger: true,
  );
  if (!ok) return;
  try {
    await data.repo.deleteDoc(d);
  } catch (e) {
    if (context.mounted) showToast(context, friendlyDbError(e), isError: true);
  }
}

/// The document's PDF, full screen (print and share there too).
Future<void> openSupplierPdf(BuildContext context, SuppliersData data, SupplierDoc d) => Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PdfViewPage(
        title: '${docKindLabel(d.kind)} ${d.reference ?? fmtDateDisplay(d.date)}',
        pdf: () => data.repo.downloadPdf(d.filePath!),
        fileName: d.fileName ?? 'supplier-document.pdf',
      ),
    ));

/// Upload an invoice, credit note or statement: the PDF, its date,
/// reference and amount (for a statement, its closing balance).
/// From email, with everything read from the PDF: an amount, an invoice's
/// number, the supplier sure, not a notice.
List<SupplierDoc> _readyToConfirm(List<SupplierDoc> toCheck) => [
      for (final d in toCheck)
        if (d.amount > 0 &&
            (d.kind == SupplierDocKind.statement || (d.reference ?? '').trim().isNotEmpty) &&
            !(d.notes ?? '').contains('Could be:') &&
            !(d.notes ?? '').contains('NOTICE'))
          d,
    ];

/// Confirms them all as read from their PDFs (the rest stay to check).
Future<void> _confirmAll(BuildContext context, SuppliersData data, List<SupplierDoc> docs) async {
  final total = docs.where((d) => d.kind == SupplierDocKind.invoice).fold<double>(0, (s, d) => s + d.amount);
  final ok = await confirmDialog(
    context,
    title: 'Confirm ${docs.length} from email?',
    message: 'They count in the account as read from their PDFs'
        '${total > 0 ? ' (invoices ${fmtRCents(total)})' : ''}. '
        'Ones without an amount or number, notices, and ones where the supplier wasn\'t sure stay to check.',
    confirmLabel: 'Confirm all',
  );
  if (!ok) return;
  var done = 0;
  try {
    for (final d in docs) {
      await data.repo.confirmDoc(d.id,
          supplierId: d.supplierId,
          kind: d.kind,
          date: d.date,
          amount: d.amount,
          reference: d.reference,
          notes: d.notes,
          dueDate: d.dueDate,
          overdueAmount: d.overdueAmount);
      done++;
    }
    if (context.mounted) showToast(context, '$done confirmed.');
  } catch (e) {
    if (context.mounted) showToast(context, '$done confirmed, then: ${friendlyDbError(e)}', isError: true);
  }
}

Future<void> addSupplierDoc(BuildContext context, SuppliersData data, Supplier s, SupplierDocKind kind) async {
  final ref = TextEditingController();
  final amount = TextEditingController();
  final overdue = TextEditingController();
  final notes = TextEditingController();
  var date = DateTime.now();
  DateTime? due;
  Uint8List? pdf;
  String? fileName;
  String? error;
  var saving = false;
  final what = docKindLabel(kind);
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: dialogTitleWithError('$what -- ${s.name}', error),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf'], withData: true);
                    final f = picked?.files.firstOrNull;
                    if (f == null) return;
                    if (f.bytes == null) return setLocal(() => error = 'Could not read that file -- try again.');
                    if (f.size > 15 * 1024 * 1024) return setLocal(() => error = 'That PDF is over 15 MB.');
                    setLocal(() {
                      pdf = f.bytes;
                      fileName = f.name;
                      error = null;
                    });
                  },
                  icon: Icon(pdf == null ? Icons.upload_file : Icons.picture_as_pdf),
                  label: Text(pdf == null ? 'Choose the PDF' : fileName ?? 'PDF chosen', overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setLocal(() => date = d);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text('$what date: ${fmtDateDisplay(toDateStr(date))}'),
                ),
                if (kind != SupplierDocKind.creditNote) ...[
                  const SizedBox(height: 10),
                  _DueDateButton(due: due, onChanged: (v) => setLocal(() => due = v)),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: ref,
                  decoration: InputDecoration(labelText: kind == SupplierDocKind.statement ? 'Statement reference (optional)' : '$what number'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(
                    labelText: kind == SupplierDocKind.statement ? 'Closing balance on the statement' : '$what total (incl. VAT)',
                    prefixText: 'R',
                  ),
                ),
                if (kind == SupplierDocKind.statement) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: overdue,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Of it, already due (optional)',
                      helperText: 'Overdue / "reeds betaalbaar" -- the rest is due by the due date',
                      prefixText: 'R',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(controller: notes, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Notes (optional)')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    final v = parseNum(amount.text);
                    if (pdf == null) return setLocal(() => error = 'Choose the PDF.');
                    if (kind != SupplierDocKind.statement && ref.text.trim().isEmpty) return setLocal(() => error = 'Type the $what number.');
                    if (v == null || (kind != SupplierDocKind.statement && v <= 0)) return setLocal(() => error = 'Type the amount.');
                    final od = kind == SupplierDocKind.statement && overdue.text.trim().isNotEmpty ? parseNum(overdue.text) : null;
                    if (kind == SupplierDocKind.statement && overdue.text.trim().isNotEmpty && (od == null || od < 0 || od > v)) {
                      return setLocal(() => error = 'Already due must be between R0 and the balance.');
                    }
                    setLocal(() => saving = true);
                    try {
                      await data.repo.addDoc(
                        supplierId: s.id,
                        kind: kind,
                        date: toDateStr(date),
                        amount: (v * 100).roundToDouble() / 100,
                        reference: ref.text,
                        notes: notes.text,
                        pdf: pdf,
                        fileName: fileName,
                        dueDate: kind == SupplierDocKind.creditNote || due == null ? null : toDateStr(due!),
                        overdueAmount: od == null ? null : (od * 100).roundToDouble() / 100,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setLocal(() {
                        saving = false;
                        error = friendlyDbError(e);
                      });
                    }
                  },
            child: Text(saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
    ),
  );
}

/// A payment to the supplier, typed in by hand.
Future<void> addSupplierPayment(BuildContext context, SuppliersData data, Supplier s) async {
  final amount = TextEditingController();
  final ref = TextEditingController();
  final notes = TextEditingController();
  var date = DateTime.now();
  String? error;
  var saving = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: dialogTitleWithError('Payment -- ${s.name}', error),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setLocal(() => date = d);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Paid on ${fmtDateDisplay(toDateStr(date))}'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount paid', prefixText: 'R'),
                ),
                const SizedBox(height: 10),
                TextField(controller: ref, decoration: const InputDecoration(labelText: 'Reference (e.g. EFT ref, optional)')),
                const SizedBox(height: 10),
                TextField(controller: notes, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Notes (optional)')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    final v = parseNum(amount.text);
                    if (v == null || v <= 0) return setLocal(() => error = 'Type the amount paid.');
                    setLocal(() => saving = true);
                    try {
                      await data.repo.addPayment(supplierId: s.id, date: toDateStr(date), amount: (v * 100).roundToDouble() / 100, reference: ref.text, notes: notes.text);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setLocal(() {
                        saving = false;
                        error = friendlyDbError(e);
                      });
                    }
                  },
            child: Text(saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
    ),
  );
}

/// A document from email: check it against its PDF, correct what was read
/// from it, and confirm (it then counts) -- or remove it.
Future<void> confirmEmailDoc(BuildContext context, SuppliersData data, Supplier s, SupplierDoc d) async {
  var kind = d.kind;
  var date = parseDateStr(d.date) ?? DateTime.now();
  var due = parseDateStr(d.dueDate);
  var supplierId = d.supplierId;
  final suppliers = [...?data.suppliers]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final ref = TextEditingController(text: d.reference);
  final amount = TextEditingController(text: d.amount == 0 ? '' : d.amount.toStringAsFixed(2));
  final overdue = TextEditingController(text: d.overdueAmount == null ? '' : d.overdueAmount!.toStringAsFixed(2));
  final notes = TextEditingController(text: d.notes);
  String? error;
  var saving = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: dialogTitleWithError('From email -- ${s.name}', error),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if ((d.emailSubject ?? '').isNotEmpty || (d.emailFrom ?? '').isNotEmpty)
                  Text(
                    [
                      if ((d.emailSubject ?? '').isNotEmpty) '"${d.emailSubject}"',
                      if ((d.emailFrom ?? '').isNotEmpty) 'from ${d.emailFrom}',
                      if ((d.emailDate ?? '').isNotEmpty) 'on ${fmtDateDisplay(d.emailDate)}',
                    ].join(' '),
                    style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: d.filePath == null ? null : () => openSupplierPdf(ctx, data, d),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Open the PDF'),
                ),
                const SizedBox(height: 12),
                // Shared addresses (Eskom's accounts, Kanaan / Oorvloed...):
                // put it on the right account.
                DropdownButtonFormField<String>(
                  initialValue: supplierId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Supplier / account'),
                  items: [
                    for (final x in suppliers)
                      DropdownMenuItem(value: x.id, child: Text('${x.name}${(x.accountNo ?? '').isEmpty ? '' : ' · ${x.accountNo}'}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setLocal(() => supplierId = v ?? supplierId),
                ),
                const SizedBox(height: 12),
                SegmentedButton<SupplierDocKind>(
                  segments: const [
                    ButtonSegment(value: SupplierDocKind.invoice, label: Text('Invoice')),
                    ButtonSegment(value: SupplierDocKind.creditNote, label: Text('Credit')),
                    ButtonSegment(value: SupplierDocKind.statement, label: Text('Statement')),
                  ],
                  selected: {kind},
                  onSelectionChanged: (v) => setLocal(() => kind = v.first),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final p = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (p != null) setLocal(() => date = p);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text('${docKindLabel(kind)} date: ${fmtDateDisplay(toDateStr(date))}'),
                ),
                if (kind != SupplierDocKind.creditNote) ...[
                  const SizedBox(height: 10),
                  _DueDateButton(due: due, onChanged: (v) => setLocal(() => due = v)),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: ref,
                  decoration: InputDecoration(labelText: kind == SupplierDocKind.statement ? 'Statement reference (optional)' : '${docKindLabel(kind)} number'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(
                    labelText: kind == SupplierDocKind.statement ? 'Closing balance on the statement' : '${docKindLabel(kind)} total (incl. VAT)',
                    prefixText: 'R',
                  ),
                ),
                if (kind == SupplierDocKind.statement) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: overdue,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Of it, already due (optional)',
                      helperText: 'Overdue / "reeds betaalbaar" -- the rest is due by the due date',
                      prefixText: 'R',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(controller: notes, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Notes (optional)')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving
                ? null
                : () async {
                    Navigator.pop(ctx);
                    await _deleteDoc(context, data, d);
                  },
            style: TextButton.styleFrom(foregroundColor: NaniniColors.red),
            child: const Text('Remove'),
          ),
          TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    final v = parseNum(amount.text);
                    if (kind != SupplierDocKind.statement && ref.text.trim().isEmpty) return setLocal(() => error = 'Type the ${docKindLabel(kind).toLowerCase()} number.');
                    if (v == null || (kind != SupplierDocKind.statement && v <= 0)) return setLocal(() => error = 'Type the amount.');
                    final od = kind == SupplierDocKind.statement && overdue.text.trim().isNotEmpty ? parseNum(overdue.text) : null;
                    if (kind == SupplierDocKind.statement && overdue.text.trim().isNotEmpty && (od == null || od < 0 || od > v)) {
                      return setLocal(() => error = 'Already due must be between R0 and the balance.');
                    }
                    setLocal(() => saving = true);
                    try {
                      await data.repo.confirmDoc(d.id,
                          supplierId: supplierId,
                          dueDate: kind == SupplierDocKind.creditNote || due == null ? null : toDateStr(due!),
                          overdueAmount: od == null ? null : (od * 100).roundToDouble() / 100,
                          kind: kind, date: toDateStr(date), amount: (v * 100).roundToDouble() / 100, reference: ref.text, notes: notes.text);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setLocal(() {
                        saving = false;
                        error = friendlyDbError(e);
                      });
                    }
                  },
            child: Text(saving ? 'Saving...' : 'Confirm'),
          ),
        ],
      ),
    ),
  );
}

/// The due date printed on the document (optional): it then decides when
/// this one is payable instead of the supplier's terms.
class _DueDateButton extends StatelessWidget {
  const _DueDateButton({required this.due, required this.onChanged});
  final DateTime? due;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: due ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) onChanged(d);
              },
              icon: const Icon(Icons.event_available_outlined),
              label: Text(due == null ? 'Due date on it (optional)' : 'Due ${fmtDateDisplay(toDateStr(due!))}'),
            ),
          ),
          if (due != null) IconButton(tooltip: 'No due date', icon: const Icon(Icons.clear), onPressed: () => onChanged(null)),
        ],
      );
}
