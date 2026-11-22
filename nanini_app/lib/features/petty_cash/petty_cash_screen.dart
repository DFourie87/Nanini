import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session.dart';
import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/date_pick.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../capture/capture_models.dart';
import '../capture/capture_repository.dart';
import '../suppliers/suppliers_capture_approval.dart' show capturedPhoto;
import '../suppliers/suppliers_models.dart';
import '../xero/xero_api.dart';
import 'cash_slip_models.dart';
import 'cash_slip_repository.dart';

/// Hub > Financials > Petty cash: the till slips paid from the petty cash.
/// Slips photographed on the phones (Capture > CASH SLIP) wait here to be
/// checked and put against an account; each slip is checked against the
/// bank's money out and the credit and fleet cards -- one of the same amount
/// around its date was paid by bank or card, not from the petty cash. Then
/// they go to Xero as spend money from Petty Cash, with the photo attached.
class PettyCashScreen extends StatefulWidget {
  const PettyCashScreen({super.key, this.repo, this.xero, this.pending, this.loadCapturePhoto, this.approve, this.reject});

  final CashSlipRepository? repo;
  final XeroApi? xero;

  /// Tests: the captured slips waiting, and what approving and rejecting do.
  final Stream<List<CaptureEntry>>? pending;
  final Future<Uint8List?> Function(String entryId)? loadCapturePhoto;
  final Future<void> Function(CaptureEntry e, CashSlip slip)? approve;
  final Future<void> Function(CaptureEntry e, String reason)? reject;

  @override
  State<PettyCashScreen> createState() => _PettyCashScreenState();
}

class _PettyCashScreenState extends State<PettyCashScreen> {
  late final CashSlipRepository repo = widget.repo ?? CashSlipRepository();
  late final XeroApi? xero = widget.xero ?? (Platform.isWindows ? XeroApi() : null);
  late final Stream<List<CaptureEntry>> pending = widget.pending ?? CaptureRepository().watchPending(CaptureModule.cashModules);
  List<CashSlip>? slips;
  List<GlAccount> chart = const [];
  List<BankLine> bank = const [];
  List<PaidElsewhere> cards = const [];
  String? problem;

  String get _reviewer {
    try {
      return context.read<Session>().currentUser?.displayName ?? 'admin';
    } catch (_) {
      return 'admin';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await repo.fetchSlips();
      final c = await repo.fetchChart();
      final b = await repo.fetchBankLines();
      final k = await repo.fetchCardLines();
      if (!mounted) return;
      setState(() {
        slips = s;
        chart = c;
        bank = b;
        cards = k;
        problem = null;
      });
    } catch (e) {
      if (mounted) setState(() => problem = friendlyDbError(e));
    }
  }

  List<PaidElsewhere> _elsewhere(CashSlip s) => paidElsewhere(s, bank, cards);
  bool _heldBack(CashSlip s) => !s.cashConfirmed && _elsewhere(s).isNotEmpty;

  String _account(String? code) {
    if (code == null || code.isEmpty) return 'no account yet';
    final a = chart.where((a) => a.code == code).firstOrNull;
    return a == null ? code : a.label;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      appBar: const NaniniAppBar(title: 'Petty cash'),
      body: problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$problem\n\n(Run nanini_app/docs/sql/cash_slips.sql once?)', textAlign: TextAlign.center),
              ),
            )
          : slips == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(text)),
    );
  }

  Widget _body(TextTheme text) {
    final toSend = [
      for (final s in slips!)
        if (!s.inXero && cashSlipNotReady(s) == null && !_heldBack(s)) s,
    ];
    final byMonth = <String, List<CashSlip>>{};
    for (final s in [...slips!]..sort((a, b) => b.date.compareTo(a.date))) {
      (byMonth[s.date.substring(0, 7)] ??= []).add(s);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        StreamBuilder<List<CaptureEntry>>(
          stream: pending,
          builder: (context, snap) {
            final waiting = snap.data ?? const <CaptureEntry>[];
            if (waiting.isEmpty) return const SizedBox.shrink();
            return Card(
              key: const Key('petty_pending'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('From the phones -- to check (${waiting.length})', style: text.titleSmall),
                    for (final e in waiting) _pendingTile(e),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('petty_send'),
              onPressed: toSend.isEmpty || xero == null ? null : () => runOnce('petty_send', () => _send(toSend)),
              icon: const Icon(Icons.upload),
              label: Text(toSend.isEmpty ? 'Nothing for Xero' : 'Send ${toSend.length} to Xero'),
            ),
            OutlinedButton.icon(key: const Key('petty_add'), onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('Add a slip')),
          ],
        ),
        if (xero == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Sending to Xero is on the PC hub.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
          ),
        if (bank.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Not checked against the bank yet: run docs/sql/bank_lines.sql once, then the bank import on the office PC.',
              style: TextStyle(color: NaniniColors.muted, fontSize: 12),
            ),
          ),
        const SizedBox(height: 8),
        if (slips!.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No cash slips yet.', style: TextStyle(color: NaniniColors.muted)),
          ),
        for (final e in byMonth.entries)
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      Expanded(child: Text(fmtMonth(e.key), style: text.titleSmall)),
                      Text(fmtRCents(e.value.fold<double>(0, (s, x) => s + x.amount)), style: text.titleSmall),
                    ],
                  ),
                ),
                for (final s in e.value) _slipTile(s),
              ],
            ),
          ),
      ],
    );
  }

  String fmtMonth(String ym) {
    const m = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final p = ym.split('-');
    return '${m[int.parse(p[1]) - 1]} ${p[0]}';
  }

  Widget _pendingTile(CaptureEntry e) {
    final s = _fromCapture(e);
    final elsewhere = _elsewhere(s);
    return ListTile(
      key: Key('petty_pending_${e.id}'),
      contentPadding: EdgeInsets.zero,
      title: Text('${fmtDateDisplay(s.date)}  ${s.shop}  ${fmtRCents(s.amount)}'),
      subtitle: Text(
        elsewhere.isEmpty ? '${s.description ?? ''} -- from ${e.deviceName ?? 'a phone'}' : 'Paid by bank already? ${_elsewhereText(elsewhere.first)}',
        style: TextStyle(color: elsewhere.isEmpty ? null : NaniniColors.red),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _edit(s, capture: e),
    );
  }

  Widget _slipTile(CashSlip s) {
    final elsewhere = s.cashConfirmed ? const <PaidElsewhere>[] : _elsewhere(s);
    final notReady = cashSlipNotReady(s);
    return ListTile(
      key: Key('petty_slip_${s.id}'),
      dense: true,
      title: Text('${fmtDateDisplay(s.date)}  ${s.shop}${(s.description ?? '').isEmpty ? '' : ' -- ${s.description}'}'),
      subtitle: Text(
        elsewhere.isNotEmpty
            ? 'Paid by bank already: ${_elsewhereText(elsewhere.first)} -- not sent to Xero'
            : '${_account(s.glAccount)}${s.vat > 0 ? ' · VAT ${fmtRCents(s.vat)}' : ' · no VAT'}'
                  '${s.inXero
                      ? '  ✓ Xero'
                      : notReady == null
                      ? ''
                      : ' · $notReady'}',
        style: TextStyle(color: elsewhere.isNotEmpty ? NaniniColors.red : null),
      ),
      trailing: Text(fmtRCents(s.amount)),
      onTap: () => _edit(s),
    );
  }

  String _elsewhereText(PaidElsewhere p) => '${p.where} ${fmtDateDisplay(p.date)} ${fmtRCents(p.amount.abs())} (${p.description})';

  CashSlip _fromCapture(CaptureEntry e) {
    final p = e.payload;
    final shop = '${p['shop'] ?? ''}'.trim();
    return CashSlip(
      id: '',
      date: p['date'] as String? ?? toDateStr(e.capturedAt),
      shop: shop,
      description: p['description'] as String?,
      amount: (p['amount'] as num?)?.toDouble() ?? 0,
      vat: (p['vat'] as num?)?.toDouble() ?? 0,
      glAccount: lastAccountFor(shop, slips ?? const []),
      source: 'Phone: ${e.deviceName ?? 'capture'}',
    );
  }

  /// Checks a slip: from a phone ([capture]: approve or reject), a new one
  /// ([s] null) or one kept ([s]).
  Future<void> _edit(CashSlip? s, {CaptureEntry? capture}) async {
    final editable = s == null || !s.inXero;
    final shop = TextEditingController(text: s?.shop ?? '');
    final what = TextEditingController(text: s?.description ?? '');
    final amount = TextEditingController(text: s == null ? '' : s.amount.toStringAsFixed(2));
    final vat = TextEditingController(text: s == null || s.vat == 0 ? '' : s.vat.toStringAsFixed(2));
    var date = s?.date ?? toDateStr(DateTime.now());
    String? account = s?.glAccount;
    var confirmed = s?.cashConfirmed ?? false;
    Uint8List? newPhoto;
    final photo = capture != null
        ? (widget.loadCapturePhoto ?? capturedPhoto)(capture.id)
        : (s == null || s.id.isEmpty ? Future<Uint8List?>.value(null) : repo.photo(s.id));
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final draft = CashSlip(
            id: s?.id ?? '',
            date: date,
            shop: shop.text.trim(),
            amount: double.tryParse(amount.text.replaceAll(' ', '').replaceAll(',', '')) ?? 0,
          );
          final elsewhere = _elsewhere(draft);
          return AlertDialog(
            title: Text(capture != null ? 'Cash slip from ${capture.deviceName ?? 'a phone'}' : (s == null ? 'Add a cash slip' : 'Cash slip')),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<Uint8List?>(
                      future: photo,
                      builder: (_, snap) {
                        final bytes = newPhoto ?? snap.data;
                        if (bytes == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () => showDialog<void>(
                              context: ctx,
                              builder: (_) => Dialog(child: InteractiveViewer(child: Image.memory(bytes))),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(bytes, height: 220, fit: BoxFit.contain),
                            ),
                          ),
                        );
                      },
                    ),
                    if (elsewhere.isNotEmpty)
                      Container(
                        key: const Key('petty_elsewhere'),
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: NaniniColors.red),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Paid by bank or card already?',
                              style: TextStyle(color: NaniniColors.red, fontWeight: FontWeight.bold),
                            ),
                            for (final p in elsewhere) Text(_elsewhereText(p), style: const TextStyle(color: NaniniColors.red)),
                            const Text('Then it was not paid from the petty cash.', style: TextStyle(color: NaniniColors.red)),
                            if (editable)
                              CheckboxListTile(
                                key: const Key('petty_confirm_cash'),
                                contentPadding: EdgeInsets.zero,
                                value: confirmed,
                                onChanged: (v) => setLocal(() => confirmed = v ?? false),
                                title: const Text('It was paid from the petty cash after all'),
                              ),
                          ],
                        ),
                      ),
                    TextField(
                      key: const Key('petty_shop'),
                      controller: shop,
                      enabled: editable,
                      decoration: const InputDecoration(labelText: 'Shop'),
                      onChanged: (_) => setLocal(() {}),
                    ),
                    TextField(
                      key: const Key('petty_what'),
                      controller: what,
                      enabled: editable,
                      decoration: const InputDecoration(labelText: 'What it was for'),
                    ),
                    TextField(
                      key: const Key('petty_amount'),
                      controller: amount,
                      enabled: editable,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Total paid, with VAT (R)'),
                      onChanged: (_) => setLocal(() {}),
                    ),
                    TextField(
                      key: const Key('petty_vat'),
                      controller: vat,
                      enabled: editable,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'VAT on it (R) -- empty: no VAT, or not a tax invoice'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('petty_date'),
                      onPressed: !editable
                          ? null
                          : () async {
                              final d = await pickDate(ctx, initialDate: DateTime.parse(date), firstDate: DateTime(2026, 3, 1), lastDate: DateTime(2100));
                              if (d != null) setLocal(() => date = toDateStr(d));
                            },
                      icon: const Icon(Icons.event),
                      label: Text(fmtDateDisplay(date)),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: const Key('petty_account'),
                      initialValue: chart.any((a) => a.code == account) ? account : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Account'),
                      items: [
                        for (final a in chart)
                          DropdownMenuItem(
                            value: a.code,
                            child: Text(a.label, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: editable ? (v) => setLocal(() => account = v) : null,
                    ),
                    if (capture == null && s == null)
                      TextButton.icon(
                        key: const Key('petty_photo'),
                        onPressed: () async {
                          final f = (await FilePicker.platform.pickFiles(type: FileType.image, withData: true))?.files.firstOrNull;
                          if (f?.bytes != null) setLocal(() => newPhoto = f!.bytes);
                        },
                        icon: const Icon(Icons.photo),
                        label: Text(newPhoto == null ? 'Add the photo of the slip' : 'Photo added'),
                      ),
                    if (s?.inXero == true) const Text('In Xero: change it there.', style: TextStyle(color: NaniniColors.muted)),
                  ],
                ),
              ),
            ),
            actions: [
              if (capture != null) TextButton(key: const Key('petty_reject'), onPressed: () => Navigator.pop(ctx, 'reject'), child: const Text('Reject')),
              if (capture == null && s != null && !s.inXero)
                TextButton(key: const Key('petty_delete'), onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Delete')),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              if (editable)
                FilledButton(key: const Key('petty_save'), onPressed: () => Navigator.pop(ctx, 'save'), child: Text(capture != null ? 'Approve' : 'Save')),
            ],
          );
        },
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'reject' && capture != null) {
      final why = _elsewhere(_fromCapture(capture));
      final reason = why.isEmpty ? 'Not a petty cash slip' : 'Paid by bank already: ${_elsewhereText(why.first)}';
      if (await trySave(context, () => (widget.reject ?? (e, r) => CaptureRepository().reject(e, reviewedBy: _reviewer, reason: r))(capture, reason))) {
        if (mounted) showToast(context, 'Rejected');
      }
      return;
    }
    if (choice == 'delete' && s != null) {
      if (await confirmDialog(context, message: 'Delete the slip of ${s.shop}, ${fmtRCents(s.amount)}?') && mounted) {
        if (await trySave(context, () => repo.delete(s.id))) await _load();
      }
      return;
    }
    final total = double.tryParse(amount.text.replaceAll(' ', '').replaceAll(',', ''));
    final v = double.tryParse(vat.text.replaceAll(' ', '').replaceAll(',', '')) ?? 0;
    if (shop.text.trim().isEmpty || total == null || total <= 0 || v < 0 || v >= total) {
      await showProblem(context, 'Give the shop and the total; the VAT must be less than the total.');
      return;
    }
    final slip = CashSlip(
      id: s?.id ?? '',
      date: date,
      shop: shop.text.trim(),
      description: what.text.trim().isEmpty ? null : what.text.trim(),
      amount: total,
      vat: v,
      glAccount: account,
      source: s?.source ?? 'Hub',
      cashConfirmed: confirmed,
    );
    final ok = await trySave(context, () async {
      if (capture != null) {
        await (widget.approve ?? (e, x) => CaptureRepository().approve(e, reviewedBy: _reviewer, cashSlip: x))(capture, slip);
      } else if (s == null || s.id.isEmpty) {
        await repo.add(slip, photo: newPhoto);
      } else {
        await repo.update(slip);
      }
    });
    if (ok) await _load();
  }

  /// Sends [toSend] to Xero as spend money from the Petty Cash bank account,
  /// each with its photo; says what Xero refused.
  Future<void> _send(List<CashSlip> toSend) async {
    final api = xero!;
    try {
      final account = pettyCashAccount(await api.bankAccounts());
      if (account == null) {
        if (mounted) {
          await showProblem(
            context,
            'Xero has no bank account "Cash" with code 8430 (the petty cash). Add it in Xero (Accounting > Bank accounts > Add bank account, "Other"), then send again.',
            title: 'Xero',
          );
        }
        return;
      }
      final total = toSend.fold(0.0, (s, x) => s + x.amount);
      if (!mounted) return;
      final go = await confirmDialog(context, message: 'Send ${toSend.length} cash slip(s), ${fmtRCents(total)}, to Xero as spend money from ${account.name}?');
      if (!go) return;
      final taxTypes = await api.taxTypes();
      final results = await api.sendBankTransactions([for (final s in toSend) xeroSpendMoneyJson(s, account.id, taxTypes)]);
      final refused = <String>[];
      final noPhoto = <String>[];
      var sent = 0;
      for (var i = 0; i < toSend.length; i++) {
        final s = toSend[i];
        final r = results[i];
        if (r.id == null) {
          refused.add('${s.shop} ${fmtRCents(s.amount)}: ${r.error}');
          continue;
        }
        await repo.markSent(s.id, r.id!);
        sent++;
        final bytes = await repo.photo(s.id);
        if (bytes != null) {
          try {
            await api.attachToBankTransaction(r.id!, 'Cash slip ${s.date} ${s.shop}.jpg'.replaceAll(RegExp(r'[\\/:*?"<>|]'), ''), bytes);
          } catch (e) {
            noPhoto.add('${s.shop}: $e');
          }
        }
      }
      await _load();
      if (!mounted) return;
      await showProblem(
        context,
        'Sent $sent cash slip(s) to Xero as spend money from ${account.name}. In Xero they are in ${account.name} > Account transactions; '
        'at the month\'s cash count, mark them as reconciled.'
        '${refused.isEmpty ? '' : '\n\nXero refused ${refused.length}:\n${refused.join('\n')}'}'
        '${noPhoto.isEmpty ? '' : '\n\nPhoto not attached (${noPhoto.length}):\n${noPhoto.take(3).join('\n')}'}',
        title: refused.isEmpty ? 'Sent to Xero' : 'Sent to Xero, with problems',
      );
    } on XeroProblem catch (e) {
      if (mounted) await showProblem(context, e.message, title: 'Xero');
    }
  }
}
