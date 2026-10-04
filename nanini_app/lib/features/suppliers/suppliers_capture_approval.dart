import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import '../capture/capture_models.dart';
import 'suppliers_models.dart';
import 'suppliers_photo.dart';
import 'suppliers_repository.dart';
import '../../core/run_once.dart';

/// A captured supplier document as checked by the admin: its details and,
/// for an invoice or credit note, its lines each against a contra account.
class SupplierDocApproval {
  SupplierDocApproval({
    required this.kind,
    required this.date,
    required this.amount,
    required this.reference,
    required this.vat,
    required this.lines,
  });
  final SupplierDocKind kind;
  final String date;
  final double amount;
  final String? reference;
  final double? vat;

  /// As they count: negative on a credit note.
  final List<({String? description, double excl, double vat, String glAccount})> lines;
}

/// The photo sent with a captured entry (docs/sql/suppliers_capture.sql), or null.
Future<Uint8List?> capturedPhoto(String entryId) async {
  final row = await sb.from('capture_photos').select('data').eq('entry_id', entryId).maybeSingle();
  final data = row?['data'] as String?;
  return data == null ? null : base64Decode(data);
}

/// Approving a captured supplier document: saves it to the supplier with its
/// photo as a one-page PDF, and its lines with the contra accounts chosen.
Future<void> applySupplierCapture(CaptureEntry entry, SupplierDocApproval a) async {
  final p = entry.payload;
  final photo = p['photo'] == true ? await capturedPhoto(entry.id) : null;
  final repo = SuppliersRepository();
  final id = await repo.addDoc(
    supplierId: p['supplier_id'] as String,
    kind: a.kind,
    date: a.date,
    amount: a.amount,
    reference: a.reference,
    vatAmount: a.vat,
    notes: 'Captured on ${entry.deviceName ?? 'a phone'}',
    pdf: photo == null ? null : await photosToPdf([photo]),
    fileName: photo == null ? null : 'Photo ${(a.reference ?? '').isEmpty ? a.date : a.reference}.pdf',
  );
  await repo.addLines(id, a.lines);
  // Kept in the supplier's documents now (as the PDF).
  await sb.from('capture_photos').delete().eq('entry_id', entry.id);
}

class _Line {
  _Line({String description = '', double? excl, double? vat, this.account})
      : description = TextEditingController(text: description),
        excl = TextEditingController(text: excl == null ? '' : excl.toStringAsFixed(2)),
        vat = TextEditingController(text: vat == null ? '' : vat.toStringAsFixed(2));
  final TextEditingController description;
  final TextEditingController excl;
  final TextEditingController vat;
  String? account;
}

/// The admin's check of a captured supplier document, with the allocation of
/// its lines to GL accounts. Pops a [SupplierDocApproval], or null.
class SupplierCaptureApprovalPage extends StatefulWidget {
  const SupplierCaptureApprovalPage({super.key, required this.entry, this.loadPhoto = capturedPhoto, this.reference});
  final CaptureEntry entry;
  final Future<Uint8List?> Function(String entryId) loadPhoto;

  /// For tests: the supplier and chart instead of the database.
  final ({Supplier? supplier, List<GlAccount> chart})? reference;

  @override
  State<SupplierCaptureApprovalPage> createState() => _SupplierCaptureApprovalPageState();
}

class _SupplierCaptureApprovalPageState extends State<SupplierCaptureApprovalPage> {
  late SupplierDocKind kind;
  late String date;
  late final TextEditingController amount;
  late final TextEditingController vat;
  late final TextEditingController reference;
  final lines = <_Line>[];
  Supplier? supplier;
  List<GlAccount> chart = [];
  bool loading = true;
  String? error;
  Future<Uint8List?>? photo;

  Map<String, dynamic> get p => widget.entry.payload;

  @override
  void initState() {
    super.initState();
    kind = switch (p['kind']) { 'credit_note' => SupplierDocKind.creditNote, 'statement' => SupplierDocKind.statement, _ => SupplierDocKind.invoice };
    date = p['date'] as String? ?? toDateStr(DateTime.now());
    amount = TextEditingController(text: ((p['amount'] as num?) ?? 0).toDouble().toStringAsFixed(2));
    vat = TextEditingController(text: p['vat'] == null ? '' : (p['vat'] as num).toDouble().toStringAsFixed(2));
    reference = TextEditingController(text: p['reference'] as String? ?? '');
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.reference case final r?) {
        supplier = r.supplier;
        chart = r.chart;
      } else {
        final repo = SuppliersRepository();
        final all = await repo.watchSuppliers().first;
        supplier = all.where((s) => s.id == p['supplier_id']).firstOrNull;
        chart = await repo.watchGlAccounts().first;
      }
    } catch (e) {
      error = friendlyDbError(e);
    }
    _defaultLines();
    if (mounted) setState(() => loading = false);
  }

  /// One line against the supplier's contra -- or, when its lines with VAT go
  /// elsewhere (Kalkor: transport), the part with VAT and the zero-rated rest.
  void _defaultLines() {
    final total = (p['amount'] as num?)?.toDouble() ?? 0;
    final v = (p['vat'] as num?)?.toDouble() ?? 0;
    final main = contraAccount(supplier?.category, chart);
    final vatTo = contraAccount(supplier?.vatAccount, chart);
    final rest = _r(total - v - v / 0.15);
    if (vatTo != null && v > 0 && rest > 0.01) {
      lines.add(_Line(description: 'Part with VAT', excl: _r(v / 0.15), vat: v, account: vatTo));
      lines.add(_Line(description: 'Zero-rated part', excl: rest, vat: 0, account: main));
    } else {
      lines.add(_Line(description: supplier?.category ?? '', excl: _r(total - v), vat: v, account: v > 0 ? (vatTo ?? main) : main));
    }
  }

  static double _r(double v) => (v * 100).roundToDouble() / 100;

  @override
  Widget build(BuildContext context) {
    final statement = kind == SupplierDocKind.statement;
    return Scaffold(
      appBar: NaniniAppBar(title: 'Check and allocate'),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(p['supplier_name'] as String? ?? supplier?.name ?? '', style: Theme.of(context).textTheme.titleLarge),
                Text('Captured on ${widget.entry.deviceName ?? 'a phone'}', style: const TextStyle(color: NaniniColors.muted)),
                if (error != null) Text(error!, style: const TextStyle(color: NaniniColors.red)),
                const SizedBox(height: 8),
                if (p['photo'] == true)
                  OutlinedButton.icon(onPressed: () => runOnce('suppliers_capture_approval.1', _showPhoto), icon: const Icon(Icons.image_outlined), label: const Text('Open the photo')),
                const SizedBox(height: 8),
                DropdownButtonFormField<SupplierDocKind>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Document'),
                  items: [for (final k in SupplierDocKind.values) DropdownMenuItem(value: k, child: Text(docKindLabel(k)))],
                  onChanged: (k) => setState(() => kind = k ?? kind),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => runOnce('suppliers_capture_approval.2', () async {
                    final d = await showDatePicker(context: context, initialDate: DateTime.parse(date), firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setState(() => date = toDateStr(d));
                  }),
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Dated ${fmtDateDisplay(date)}'),
                ),
                const SizedBox(height: 8),
                if (!statement) TextField(controller: reference, decoration: InputDecoration(labelText: '${docKindLabel(kind)} number')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: InputDecoration(labelText: statement ? 'Balance on the statement' : 'Total (incl. VAT)', prefixText: 'R'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (!statement) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: vat,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Of it, VAT', prefixText: 'R'),
                        ),
                      ),
                    ],
                  ],
                ),
                if (!statement) ...[
                  const SizedBox(height: 16),
                  Text('Lines -- each to a contra account', style: Theme.of(context).textTheme.titleMedium),
                  const Text('Split the document into its lines as on the photo: amount excl. VAT, VAT and the GL account.',
                      style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
                  for (final (i, l) in lines.indexed) _lineCard(i, l),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(onPressed: () => setState(() => lines.add(_Line())), icon: const Icon(Icons.add), label: const Text('Line')),
                  ),
                  _linesTotal(),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: _approve, icon: const Icon(Icons.check), label: const Text('Approve')),
              ],
            ),
    );
  }

  Widget _lineCard(int i, _Line l) => Card(
        margin: const EdgeInsets.only(top: 8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: TextField(controller: l.description, decoration: InputDecoration(labelText: 'Line ${i + 1}: what'))),
                  if (lines.length > 1)
                    IconButton(tooltip: 'Remove line', icon: const Icon(Icons.close), onPressed: () => setState(() => lines.removeAt(i))),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: l.excl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Excl. VAT', prefixText: 'R'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: l.vat,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'VAT', prefixText: 'R'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              DropdownButtonFormField<String>(
                initialValue: chart.any((g) => g.code == l.account) ? l.account : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Contra account'),
                items: [for (final g in chart) DropdownMenuItem(value: g.code, child: Text(g.label, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => l.account = v),
              ),
            ],
          ),
        ),
      );

  double get _linesSum => lines.fold<double>(0, (s, l) => s + (parseNum(l.excl.text) ?? 0) + (parseNum(l.vat.text) ?? 0));

  Widget _linesTotal() {
    final total = parseNum(amount.text) ?? 0;
    final ok = (_linesSum - total).abs() < 0.01;
    return Text(
      ok ? 'The lines add up to the total.' : 'The lines add up to ${fmtRCents(_linesSum)}, the total is ${fmtRCents(total)}.',
      style: TextStyle(color: ok ? NaniniColors.green : NaniniColors.red, fontWeight: FontWeight.w600),
    );
  }

  Future<void> _showPhoto() async {
    photo ??= widget.loadPhoto(widget.entry.id);
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: FutureBuilder<Uint8List?>(
          future: photo,
          builder: (ctx, snap) => snap.connectionState != ConnectionState.done
              ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
              : snap.data == null
                  ? const Padding(padding: EdgeInsets.all(24), child: Text('The photo is not there.'))
                  : InteractiveViewer(maxScale: 6, child: Image.memory(snap.data!)),
        ),
      ),
    );
  }

  void _approve() {
    final statement = kind == SupplierDocKind.statement;
    final total = parseNum(amount.text);
    if (total == null || (!statement && total <= 0)) return _problem('Type the total.');
    final v = statement || vat.text.trim().isEmpty ? null : parseNum(vat.text);
    if (!statement && vat.text.trim().isNotEmpty && (v == null || v < 0 || v > total)) return _problem('The VAT must be between R0 and the total.');
    final sign = kind == SupplierDocKind.creditNote ? -1 : 1;
    final out = <({String? description, double excl, double vat, String glAccount})>[];
    if (!statement) {
      for (final (i, l) in lines.indexed) {
        final ex = parseNum(l.excl.text);
        final lv = l.vat.text.trim().isEmpty ? 0.0 : parseNum(l.vat.text);
        if (ex == null || lv == null) return _problem('Line ${i + 1}: type its amount excl. VAT and its VAT (0 if none).');
        if (l.account == null) return _problem('Line ${i + 1}: choose its contra account.');
        out.add((description: l.description.text.trim().isEmpty ? null : l.description.text.trim(), excl: sign * _r(ex), vat: sign * _r(lv), glAccount: l.account!));
      }
      if ((_linesSum - total).abs() >= 0.01) return _problem('The lines must add up to the total (${fmtRCents(total)}).');
    }
    Navigator.pop(
      context,
      SupplierDocApproval(
        kind: kind,
        date: date,
        amount: _r(total),
        reference: statement || reference.text.trim().isEmpty ? null : reference.text.trim(),
        vat: v == null ? null : _r(v),
        lines: out,
      ),
    );
  }

  void _problem(String msg) => showProblem(context, msg);
}
