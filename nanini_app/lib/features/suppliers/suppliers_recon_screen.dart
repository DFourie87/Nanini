import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../hours/pdf_view_page.dart';
import 'suppliers_allocation.dart';
import 'suppliers_data.dart';
import 'suppliers_models.dart';
import 'suppliers_photo.dart';
import '../../core/run_once.dart';

/// One supplier's documents from email still to check, with Confirm all
/// (nothing when there are none).
List<Widget> supplierToCheckSection(BuildContext context, SuppliersData data, SupplierAccount a) {
  return [
    if (a.toCheck.isNotEmpty) ...[
      Row(
        children: [
          Expanded(
            child: Text('To check (${a.toCheck.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: NaniniColors.amber)),
          ),
          if (_readyToConfirm(data, a).isNotEmpty)
            TextButton.icon(
              onPressed: () => runOnce('suppliers_recon_screen.1', () => _confirmAll(context, data, a.supplier, _readyToConfirm(data, a))),
              icon: const Icon(Icons.done_all),
              label: Text('Confirm all (${_readyToConfirm(data, a).length})'),
            ),
        ],
      ),
      const Text('From email: check each against its PDF and confirm -- only then does it count.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
      const SizedBox(height: 4),
      for (final d in a.toCheck)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: NaniniColors.amber),
          ),
          child: ListTile(
            leading: const Icon(Icons.mark_email_unread_outlined, color: NaniniColors.amber),
            title: Text('${docKindLabel(d.kind)}${(d.reference ?? '').isEmpty ? '' : ' ${d.reference}'} · ${fmtDateDisplay(d.date)}'),
            subtitle: Text([if ((d.emailSubject ?? '').isNotEmpty) d.emailSubject!, if ((d.fileName ?? '').isNotEmpty) d.fileName!].join('\n')),
            trailing: Text(
              _amountUnknown(d) ? 'amount ?' : (d.amount < 0 ? '-${fmtRCents(-d.amount)}' : fmtRCents(d.amount)),
              style: TextStyle(fontWeight: FontWeight.w700, color: _amountUnknown(d) ? NaniniColors.red : null),
            ),
            onTap: () => runOnce('suppliers_recon_screen.2', () => confirmEmailDoc(context, data, a.supplier, d)),
          ),
        ),
    ],
  ];
}

/// A line of a supplier's account: tap opens its PDF, a long press removes it.
class LedgerTile extends StatelessWidget {
  const LedgerTile({super.key, required this.line, required this.data});
  final LedgerLine line;
  final SuppliersData data;

  @override
  Widget build(BuildContext context) {
    final doc = line.doc;
    final pay = line.payment;
    final isStatementLine = line.kind == LedgerKind.statement;
    return ListTile(
      dense: true,
      leading: Icon(
        isStatementLine
            ? Icons.receipt_long_outlined
            : pay != null || (line.kind == LedgerKind.payment && doc == null)
            ? Icons.payments_outlined
            : doc == null
            ? Icons.start
            : doc.filePath != null
            ? Icons.picture_as_pdf_outlined
            : Icons.receipt_outlined,
        color: line.amount < 0 ? NaniniColors.green : NaniniColors.muted,
      ),
      title: Text(line.label),
      subtitle: Text(
        '${fmtDateDisplay(line.date)}${doc?.dueDate == null || isStatementLine ? '' : ' · due ${fmtDateDisplay(doc!.dueDate)}'}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (line.check) ...[
            Text(
              fmtRCents(doc!.amount),
              style: const TextStyle(fontWeight: FontWeight.w700, color: NaniniColors.ink),
            ),
            Text(
              line.amount.abs() < 0.005
                  ? 'per statement = ours'
                  : 'ours ${fmtRCents(line.balance)} · ${line.amount > 0 ? '+' : '-'}${fmtRCents(line.amount.abs())}',
              style: TextStyle(fontSize: 11, color: line.amount.abs() < 0.005 ? NaniniColors.green : NaniniColors.amber),
            ),
          ] else if (isStatementLine) ...[
            Text(
              fmtRCents(line.balance),
              style: const TextStyle(fontWeight: FontWeight.w700, color: NaniniColors.ink),
            ),
            Text(
              line.amount.abs() < 0.005 || line.label == 'Balance per statement'
                  ? 'per statement'
                  : '${line.amount > 0 ? '+' : '-'}${fmtRCents(line.amount.abs())}',
              style: const TextStyle(fontSize: 11, color: NaniniColors.muted),
            ),
          ] else ...[
            Text(
              line.amount < 0 ? '-${fmtRCents(-line.amount)}' : fmtRCents(line.amount),
              style: TextStyle(fontWeight: FontWeight.w700, color: line.amount < 0 ? NaniniColors.green : NaniniColors.ink),
            ),
            Text('owed ${fmtRCents(line.balance)}', style: const TextStyle(fontSize: 11, color: NaniniColors.muted)),
          ],
        ],
      ),
      onTap: doc?.filePath == null ? null : () => openSupplierPdf(context, data, doc!),
      onLongPress: doc != null
          ? () => _deleteDoc(context, data, doc)
          : pay != null
          ? () async {
              if (await confirmDialog(
                context,
                title: 'Remove payment?',
                message: '${fmtRCents(pay.amount)} on ${fmtDateDisplay(pay.date)}',
                confirmLabel: 'Remove',
                danger: true,
              )) {
                try {
                  await data.repo.deletePayment(pay.id);
                  await data.reload();
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
    await data.reload();
  } catch (e) {
    if (context.mounted) showToast(context, friendlyDbError(e), isError: true);
  }
}

/// The document's PDF, full screen (print and share there too).
Future<void> openSupplierPdf(BuildContext context, SuppliersData data, SupplierDoc d) => Navigator.of(context).push(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => PdfViewPage(
      title: '${docKindLabel(d.kind)} ${d.reference ?? fmtDateDisplay(d.date)}',
      pdf: () => data.repo.downloadPdf(d.filePath!),
      fileName: d.fileName ?? 'supplier-document.pdf',
    ),
  ),
);

/// Upload an invoice, credit note or statement: the PDF, its date,
/// reference and amount (for a statement, its closing balance).
/// No amount read from the PDF (stored as 0). A statement may truly be
/// R0.00 (all paid) or in credit: only when its amount wasn't found.
bool _amountUnknown(SupplierDoc d) =>
    d.amount == 0 && (d.kind != SupplierDocKind.statement || (d.notes ?? '').contains('Amount not found'));

/// From email, with everything read from the PDF: an amount (a statement's
/// may be R0.00 or in credit), an invoice's number, the supplier sure, not
/// a notice -- and every line of an invoice with its contra account (one
/// remembered for its item, or the supplier's).
List<SupplierDoc> _readyToConfirm(SuppliersData data, SupplierAccount a) => [
  for (final d in a.toCheck)
    if (!_amountUnknown(d) &&
        (d.kind == SupplierDocKind.statement || d.amount > 0) &&
        (d.kind == SupplierDocKind.statement || (d.reference ?? '').trim().isNotEmpty) &&
        !(d.notes ?? '').contains('Could be:') &&
        !(d.notes ?? '').contains('NOTICE') &&
        (d.kind == SupplierDocKind.statement || allAllocated(data, allocationFor(data, a.supplier, d, d.amount, d.vatAmount))))
      d,
];

/// Confirms them all as read from their PDFs (the rest stay to check).
Future<void> _confirmAll(BuildContext context, SuppliersData data, Supplier s, List<SupplierDoc> docs) async {
  final total = docs.where((d) => d.kind == SupplierDocKind.invoice).fold<double>(0, (s, d) => s + d.amount);
  final ok = await confirmDialog(
    context,
    title: 'Confirm ${docs.length} from email?',
    message:
        'They count in the account as read from their PDFs'
        '${total > 0 ? ' (invoices ${fmtRCents(total)})' : ''}. '
        'Each line goes to its contra account (remembered for its item, else the supplier\'s). '
        'Ones without an amount or number or a line\'s account, notices, and ones where the supplier wasn\'t sure stay to check.',
    confirmLabel: 'Confirm all',
  );
  if (!ok) return;
  var done = 0;
  try {
    for (final d in docs) {
      await data.repo.confirmDoc(
        d.id,
        supplierId: d.supplierId,
        kind: d.kind,
        date: d.date,
        amount: d.amount,
        reference: d.reference,
        notes: d.notes,
        dueDate: d.dueDate,
        overdueAmount: d.overdueAmount,
      );
      if (d.kind != SupplierDocKind.statement) {
        await saveAllocation(data, s.id, d, d.kind, allocationFor(data, s, d, d.amount, d.vatAmount));
      }
      done++;
    }
    await data.reload();
    if (context.mounted) showToast(context, '$done confirmed.');
  } catch (e) {
    if (context.mounted) showToast(context, '$done confirmed, then: ${friendlyDbError(e)}', isError: true);
  }
}

Future<void> addSupplierDoc(BuildContext context, SuppliersData data, Supplier s, SupplierDocKind kind) async {
  final ref = TextEditingController();
  final amount = TextEditingController();
  final overdue = TextEditingController();
  final vat = TextEditingController();
  final notes = TextEditingController();
  var date = DateTime.now();
  DateTime? due;
  Uint8List? pdf;
  String? fileName;
  Uint8List? photo; // or the invoice photographed (one page)
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
                  onPressed: () => runOnce('suppliers_recon_screen.3', () async {
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
                  }),
                  icon: Icon(pdf == null ? Icons.upload_file : Icons.picture_as_pdf),
                  label: Text(pdf == null ? 'Choose the PDF' : fileName ?? 'PDF chosen', overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: 6),
                // Or photograph it (one page), made into a PDF on Save.
                OutlinedButton.icon(
                  onPressed: () => runOnce('suppliers_recon_screen.4', () async {
                    try {
                      final shot = await takeInvoicePhoto();
                      if (shot == null) return;
                      setLocal(() {
                        photo = shot;
                        pdf = null;
                        fileName = null;
                        error = null;
                      });
                    } catch (e) {
                      setLocal(() => error = 'The camera could not be opened ($e).');
                    }
                  }),
                  icon: Icon(photo == null ? Icons.photo_camera_outlined : Icons.check_circle_outline),
                  label: Text(photo == null ? 'Take a photo' : 'Photo taken -- retake'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => runOnce('suppliers_recon_screen.5', () async {
                    final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setLocal(() => date = d);
                  }),
                  icon: const Icon(Icons.event_outlined),
                  label: Text('$what date: ${fmtDateDisplay(toDateStr(date))}'),
                ),
                if (kind != SupplierDocKind.creditNote) ...[const SizedBox(height: 10), _DueDateButton(due: due, onChanged: (v) => setLocal(() => due = v))],
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
                if (kind != SupplierDocKind.statement) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: vat,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Of it, VAT (optional -- for the purchases report)', prefixText: 'R'),
                  ),
                ],
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
                TextField(
                  controller: notes,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: saving
                ? null
                : () => runOnce('suppliers_recon_screen.6', () async {
                    final v = parseNum(amount.text);
                    if (pdf == null && photo == null) return setLocal(() => error = 'Choose the PDF, or take a photo.');
                    if (kind != SupplierDocKind.statement && ref.text.trim().isEmpty) return setLocal(() => error = 'Type the $what number.');
                    if (v == null || (kind != SupplierDocKind.statement && v <= 0)) return setLocal(() => error = 'Type the amount.');
                    // In credit (they owe us) or all paid: nothing is already due.
                    final od = kind == SupplierDocKind.statement && v > 0 && overdue.text.trim().isNotEmpty ? parseNum(overdue.text) : null;
                    if (kind == SupplierDocKind.statement && v > 0 && overdue.text.trim().isNotEmpty && (od == null || od < 0 || od > v)) {
                      return setLocal(() => error = 'Already due must be between R0 and the balance.');
                    }
                    final vatAmount = kind != SupplierDocKind.statement && vat.text.trim().isNotEmpty ? parseNum(vat.text) : null;
                    if (vat.text.trim().isNotEmpty && kind != SupplierDocKind.statement && (vatAmount == null || vatAmount < 0 || vatAmount > v)) {
                      return setLocal(() => error = 'The VAT must be between R0 and the total.');
                    }
                    setLocal(() => saving = true);
                    try {
                      if (photo != null) {
                        pdf = await photosToPdf([photo!]);
                        fileName = 'Photo ${ref.text.trim().isEmpty ? toDateStr(date) : ref.text.trim()}.pdf';
                      }
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
                        vatAmount: vatAmount == null ? null : (vatAmount * 100).roundToDouble() / 100,
                      );
                      await data.reload();
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setLocal(() {
                        saving = false;
                        error = friendlyDbError(e);
                      });
                    }
                  }),
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
                  onPressed: () => runOnce('suppliers_recon_screen.7', () async {
                    final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setLocal(() => date = d);
                  }),
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
                TextField(
                  controller: ref,
                  decoration: const InputDecoration(labelText: 'Reference (e.g. EFT ref, optional)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: saving
                ? null
                : () => runOnce('suppliers_recon_screen.8', () async {
                    final v = parseNum(amount.text);
                    if (v == null || v <= 0) return setLocal(() => error = 'Type the amount paid.');
                    setLocal(() => saving = true);
                    try {
                      await data.repo.addPayment(
                        supplierId: s.id,
                        date: toDateStr(date),
                        amount: (v * 100).roundToDouble() / 100,
                        reference: ref.text,
                        notes: notes.text,
                      );
                      await data.reload();
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setLocal(() {
                        saving = false;
                        error = friendlyDbError(e);
                      });
                    }
                  }),
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
  final amount = TextEditingController(text: _amountUnknown(d) ? '' : d.amount.toStringAsFixed(2));
  final overdue = TextEditingController(text: d.overdueAmount == null ? '' : d.overdueAmount!.toStringAsFixed(2));
  final notes = TextEditingController(text: d.notes);
  String? error;
  var saving = false;
  Supplier supplierOf(String id) => suppliers.where((x) => x.id == id).firstOrNull ?? s;
  // Each line of an invoice / credit note to its contra account.
  var rows = allocationFor(data, s, d, d.amount.abs(), d.vatAmount);
  void refreshRows() {
    final total = parseNum(amount.text)?.abs() ?? 0;
    final fresh = allocationFor(data, supplierOf(supplierId), d, total, d.vatAmount);
    // Keep the accounts already chosen when the lines are the same ones.
    if (fresh.length == rows.length) {
      for (final (i, r) in fresh.indexed) {
        r.account = rows[i].account ?? r.account;
      }
    }
    rows = fresh;
  }

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
                      DropdownMenuItem(
                        value: x.id,
                        child: Text('${x.name}${(x.accountNo ?? '').isEmpty ? '' : ' · ${x.accountNo}'}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setLocal(() {
                    supplierId = v ?? supplierId;
                    rows = allocationFor(data, supplierOf(supplierId), d, parseNum(amount.text)?.abs() ?? 0, d.vatAmount);
                  }),
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
                  onPressed: () => runOnce('suppliers_recon_screen.9', () async {
                    final p = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (p != null) setLocal(() => date = p);
                  }),
                  icon: const Icon(Icons.event_outlined),
                  label: Text('${docKindLabel(kind)} date: ${fmtDateDisplay(toDateStr(date))}'),
                ),
                if (kind != SupplierDocKind.creditNote) ...[const SizedBox(height: 10), _DueDateButton(due: due, onChanged: (v) => setLocal(() => due = v))],
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
                  onChanged: (_) => setLocal(refreshRows),
                ),
                if (kind != SupplierDocKind.statement) ...[
                  const SizedBox(height: 12),
                  AllocationLines(data: data, rows: rows, onChanged: () => setLocal(() {})),
                ],
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
                TextField(
                  controller: notes,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving
                ? null
                : () => runOnce('suppliers_recon_screen.10', () async {
                    Navigator.pop(ctx);
                    await _deleteDoc(context, data, d);
                  }),
            style: TextButton.styleFrom(foregroundColor: NaniniColors.red),
            child: const Text('Remove'),
          ),
          TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton(
            onPressed: saving
                ? null
                : () => runOnce('suppliers_recon_screen.11', () async {
                    final v = parseNum(amount.text);
                    if (kind != SupplierDocKind.statement && ref.text.trim().isEmpty) {
                      return setLocal(() => error = 'Type the ${docKindLabel(kind).toLowerCase()} number.');
                    }
                    if (v == null || (kind != SupplierDocKind.statement && v <= 0)) return setLocal(() => error = 'Type the amount.');
                    // In credit (they owe us) or all paid: nothing is already due.
                    final od = kind == SupplierDocKind.statement && v > 0 && overdue.text.trim().isNotEmpty ? parseNum(overdue.text) : null;
                    if (kind == SupplierDocKind.statement && v > 0 && overdue.text.trim().isNotEmpty && (od == null || od < 0 || od > v)) {
                      return setLocal(() => error = 'Already due must be between R0 and the balance.');
                    }
                    if (kind != SupplierDocKind.statement && !allAllocated(data, rows)) {
                      return setLocal(() => error = 'Choose the contra account of each line.');
                    }
                    setLocal(() => saving = true);
                    try {
                      await data.repo.confirmDoc(
                        d.id,
                        supplierId: supplierId,
                        dueDate: kind == SupplierDocKind.creditNote || due == null ? null : toDateStr(due!),
                        overdueAmount: od == null ? null : (od * 100).roundToDouble() / 100,
                        kind: kind,
                        date: toDateStr(date),
                        amount: (v * 100).roundToDouble() / 100,
                        reference: ref.text,
                        notes: notes.text,
                      );
                      await saveAllocation(data, supplierId, d, kind, rows);
                      await data.reload();
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setLocal(() {
                        saving = false;
                        error = friendlyDbError(e);
                      });
                    }
                  }),
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
          onPressed: () => runOnce('suppliers_recon_screen.12', () async {
            final d = await showDatePicker(context: context, initialDate: due ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (d != null) onChanged(d);
          }),
          icon: const Icon(Icons.event_available_outlined),
          label: Text(due == null ? 'Due date on it (optional)' : 'Due ${fmtDateDisplay(toDateStr(due!))}'),
        ),
      ),
      if (due != null) IconButton(tooltip: 'No due date', icon: const Icon(Icons.clear), onPressed: () => onChanged(null)),
    ],
  );
}
