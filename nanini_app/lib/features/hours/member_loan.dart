import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/dialog_error.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';

/// One line of a member's loan to Nanini 121 CC: lent ([isLoan]), or a
/// repayment to the member. Never on payroll (admins only, see
/// member_loans.sql).
class MemberLoanEntry {
  const MemberLoanEntry({required this.id, required this.date, required this.isLoan, required this.amount, this.note});
  final String id;
  final String date;
  final bool isLoan;
  final double amount;
  final String? note;

  factory MemberLoanEntry.fromJson(Map<String, dynamic> j) => MemberLoanEntry(
        id: j['id'] as String,
        date: j['entry_date'] as String,
        isLoan: j['kind'] == 'loan',
        amount: (j['amount'] as num).toDouble(),
        note: j['note'] as String?,
      );
}

/// What the CC still owes on the loan: lent less repaid.
double memberLoanBalance(Iterable<MemberLoanEntry> entries) => entries.fold(0, (s, e) => s + (e.isLoan ? e.amount : -e.amount));

/// The members loan on a member's card in Summary > Members: balance,
/// repayments, and recording a repayment (not on payroll).
class MemberLoanSection extends StatefulWidget {
  const MemberLoanSection(this.member, {super.key});
  final Employee member;
  @override
  State<MemberLoanSection> createState() => _MemberLoanSectionState();
}

class _MemberLoanSectionState extends State<MemberLoanSection> {
  List<MemberLoanEntry>? entries;
  String? error;
  bool showAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = (await sb.from('member_loan_entries').select().eq('employee_id', widget.member.id).order('entry_date').order('created_at')) as List;
      if (!mounted) return;
      setState(() {
        entries = rows.cast<Map<String, dynamic>>().map(MemberLoanEntry.fromJson).toList();
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = friendlyDbError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: NaniniColors.muted);
    final list = entries;
    if (error != null) return Padding(padding: const EdgeInsets.only(top: 8), child: Text('Members loan: $error', style: muted));
    if (list == null) return const SizedBox.shrink();
    final lent = list.where((e) => e.isLoan).fold<double>(0, (s, e) => s + e.amount);
    final repaid = list.where((e) => !e.isLoan).fold<double>(0, (s, e) => s + e.amount);
    final newestFirst = list.reversed.toList();
    final shown = showAll ? newestFirst : newestFirst.take(6).toList();
    Widget row(String label, double v, {bool bold = false}) {
      final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Expanded(child: Text(label, style: style)), Text(fmtRCents(v), style: style)]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        Text('Members loan', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const Text('Not on payroll -- only admins see this.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
        if (list.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Nothing recorded yet.', style: muted))
        else ...[
          const SizedBox(height: 4),
          if (lent > 0) row('Loan', lent),
          row('Repaid', -repaid),
          if (lent > 0) row('Still owed to ${widget.member.displayName}', lent - repaid, bold: true),
          const SizedBox(height: 4),
          for (final e in shown)
            InkWell(
              onTap: () => runOnce('member_loan.edit', () => _edit(e)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 92, child: Text(fmtDateDisplay(e.date), style: muted)),
                  Expanded(child: Text([e.isLoan ? 'Loan' : 'Repayment', if ((e.note ?? '').isNotEmpty) e.note!].join(' · '))),
                  Text(fmtRCents(e.isLoan ? e.amount : -e.amount)),
                ]),
              ),
            ),
          if (newestFirst.length > shown.length)
            TextButton(onPressed: () => setState(() => showAll = true), child: Text('Show all ${newestFirst.length}')),
        ],
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          FilledButton.icon(
            onPressed: () => runOnce('member_loan.repay', () => _edit(null)),
            icon: const Icon(Icons.add),
            label: const Text('Record repayment'),
          ),
          OutlinedButton(
            onPressed: () => runOnce('member_loan.loan', () => _edit(null, loan: true)),
            child: const Text('Add loan amount'),
          ),
        ]),
      ],
    );
  }

  /// Adds a repayment (or loan amount), or changes / deletes [existing]. A
  /// new repayment starts at the last one's amount (the monthly amount).
  Future<void> _edit(MemberLoanEntry? existing, {bool loan = false}) async {
    final isLoan = existing?.isLoan ?? loan;
    final last = (entries ?? const <MemberLoanEntry>[]).where((e) => !e.isLoan).lastOrNull;
    final amountCtrl = TextEditingController(
        text: existing != null ? existing.amount.toStringAsFixed(2) : (!isLoan && last != null ? last.amount.toStringAsFixed(2) : null));
    final noteCtrl = TextEditingController(text: existing?.note);
    var date = existing != null ? DateTime.parse(existing.date) : DateTime.now();
    String? problem;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${existing == null ? '' : 'Change '}${isLoan ? 'loan amount' : 'repayment'} -- ${widget.member.displayName}'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(isLoan ? 'Lent to Nanini 121 CC: the amount still owed goes up.' : 'Paid back to the member by bank transfer. Not on payroll or a payslip.',
                  style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(fmtDateDisplay(toDateStr(date))),
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2015), lastDate: DateTime(2100));
                  if (d != null) setLocal(() => date = d);
                },
              ),
              TextField(
                controller: amountCtrl,
                autofocus: existing == null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Amount', prefixText: 'R', errorText: problem),
              ),
              const SizedBox(height: 8),
              TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. October 2026')),
            ]),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: const Text('Delete', style: TextStyle(color: NaniniColors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final v = parseNum(amountCtrl.text);
                if (v == null || v <= 0) return setLocal(() => problem = 'Type the amount');
                Navigator.pop(ctx, 'save');
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'delete') {
        final ok = await confirmDialog(context,
            message: 'Delete the ${isLoan ? 'loan amount' : 'repayment'} of ${fmtRCents(existing!.amount)} on ${fmtDateDisplay(existing.date)}?',
            confirmLabel: 'Delete',
            danger: true);
        if (!ok) return;
        await sb.from('member_loan_entries').delete().eq('id', existing.id);
      } else {
        final row = {
          'employee_id': widget.member.id,
          'entry_date': toDateStr(date),
          'kind': isLoan ? 'loan' : 'repayment',
          'amount': parseNum(amountCtrl.text),
          'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        };
        if (existing == null) {
          await sb.from('member_loan_entries').insert(row);
        } else {
          await sb.from('member_loan_entries').update(row).eq('id', existing.id);
        }
      }
    } catch (e) {
      if (mounted) await showProblem(context, friendlyDbError(e));
      return;
    }
    await _load();
  }
}

/// A member's bank account (members are all paid by bank transfer): their
/// salary and loan repayments go there.
Future<void> editMemberBank(BuildContext context, Employee m) async {
  final bankCtrl = TextEditingController(text: m.bankName);
  final accCtrl = TextEditingController(text: m.bankAccountNo);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Bank account -- ${m.displayName}'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Salary and members loan repayments are paid here.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(controller: bankCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Bank name')),
          const SizedBox(height: 10),
          TextField(controller: accCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Account number')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
  try {
    await sb.from('employees').update({'payment_method': 'bank', 'bank_name': opt(bankCtrl), 'bank_account_no': opt(accCtrl)}).eq('id', m.id);
  } catch (e) {
    if (context.mounted) await showProblem(context, friendlyDbError(e));
  }
}
