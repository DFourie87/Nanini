import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/auth/session.dart';
import '../../core/formatters.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'capture_models.dart';
import 'capture_repository.dart';

/// App-bar button for a hub module: an inbox icon with a badge counting the
/// capture-app entries waiting for approval. Tapping opens the review list.
class CapturedInboxButton extends StatelessWidget {
  const CapturedInboxButton({super.key, required this.title, required this.modules});
  final String title;
  final List<String> modules;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CaptureEntry>>(
      stream: CaptureRepository().watchPending(modules),
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        return IconButton(
          tooltip: 'Captured -- to approve',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CapturedReviewScreen(title: title, modules: modules)),
          ),
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            backgroundColor: NaniniColors.red,
            child: const Icon(Icons.move_to_inbox_outlined),
          ),
        );
      },
    );
  }
}

class CapturedReviewScreen extends StatefulWidget {
  const CapturedReviewScreen({super.key, required this.title, required this.modules});
  final String title;
  final List<String> modules;
  @override
  State<CapturedReviewScreen> createState() => _CapturedReviewScreenState();
}

class _CapturedReviewScreenState extends State<CapturedReviewScreen> {
  final repo = CaptureRepository();
  bool showDone = false;
  final busy = <String>{};

  String get _reviewer => context.read<Session>().currentUser?.displayName ?? 'admin';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NaniniAppBar(title: '${widget.title} -- Captured'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('To approve')),
                ButtonSegment(value: true, label: Text('Done')),
              ],
              selected: {showDone},
              onSelectionChanged: (s) => setState(() => showDone = s.first),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: NaniniColors.rust,
                selectedForegroundColor: Colors.white,
              ),
            ),
          ),
          Expanded(child: showDone ? _doneList() : _pendingList()),
        ],
      ),
    );
  }

  Widget _pendingList() {
    return StreamBuilder<List<CaptureEntry>>(
      stream: repo.watchPending(widget.modules),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load: ${friendlyDbError(snap.error!)}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final entries = snap.data!;
        if (entries.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nothing waiting. Entries from the Nanini Capture app appear here once the phone is on Wi-Fi.',
                  textAlign: TextAlign.center, style: TextStyle(color: NaniniColors.muted)),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Approving adds the entry to the records exactly as if it was captured here. Reject anything wrong and capture it correctly yourself.',
                  style: TextStyle(color: NaniniColors.muted)),
            ),
            for (final e in entries) _entryCard(e, pending: true),
          ],
        );
      },
    );
  }

  Widget _doneList() {
    return FutureBuilder<List<CaptureEntry>>(
      future: repo.fetchRecentReviewed(widget.modules),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load: ${friendlyDbError(snap.error!)}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final entries = snap.data!;
        if (entries.isEmpty) return const Center(child: Text('Nothing approved or rejected yet.', style: TextStyle(color: NaniniColors.muted)));
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [for (final e in entries) _entryCard(e, pending: false)],
        );
      },
    );
  }

  Widget _entryCard(CaptureEntry e, {required bool pending}) {
    final details = captureDetailLines(e);
    final isBusy = busy.contains(e.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(CaptureModule.label(e.module), style: Theme.of(context).textTheme.titleMedium)),
                if (!pending)
                  Text(
                    e.status == 'approved' ? 'APPROVED' : 'REJECTED',
                    style: TextStyle(fontWeight: FontWeight.w700, color: e.status == 'approved' ? NaniniColors.green : NaniniColors.red),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (final line in details) Text(line),
            if (!pending && (e.rejectReason ?? '').isNotEmpty)
              Text('Reason: ${e.rejectReason}', style: const TextStyle(color: NaniniColors.red)),
            const SizedBox(height: 6),
            Text(
              'Captured on ${e.deviceName ?? 'phone'} · ${fmtDateTimeDisplay(e.capturedAt.toIso8601String())}',
              style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
            ),
            if (pending) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(onPressed: isBusy ? null : () => _reject(e), child: const Text('Reject')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: isBusy ? null : () => _approve(e), child: Text(isBusy ? 'Saving…' : 'Approve')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _approve(CaptureEntry e) async {
    if (!await requireAdmin(context)) return;
    if (!mounted) return;
    double? kgRate;
    if (e.module == CaptureModule.kg) {
      kgRate = await _askKgRate();
      if (kgRate == null || !mounted) return;
    }
    setState(() => busy.add(e.id));
    try {
      await repo.approve(e, reviewedBy: _reviewer, kgRatePerKg: kgRate);
      if (mounted) showToast(context, 'Approved -- added to the records');
    } catch (err) {
      if (mounted) await showProblem(context, friendlyDbError(err), title: 'Could not approve');
    } finally {
      if (mounted) setState(() => busy.remove(e.id));
    }
  }

  Future<double?> _askKgRate() async {
    final ctrl = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rate per kg'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Rate (R/kg)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final rate = parseNum(ctrl.text);
              if (rate == null || rate <= 0) {
                showProblem(ctx, 'Enter the rate per kg.');
                return;
              }
              Navigator.pop(ctx, rate);
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  Future<void> _reject(CaptureEntry e) async {
    if (!await requireAdmin(context)) return;
    if (!mounted) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject entry'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Reason (shown on the phone)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy.add(e.id));
    try {
      await repo.reject(e, reviewedBy: _reviewer, reason: ctrl.text);
      if (mounted) showToast(context, 'Rejected');
    } catch (err) {
      if (mounted) await showProblem(context, friendlyDbError(err), title: 'Could not reject');
    } finally {
      if (mounted) setState(() => busy.remove(e.id));
    }
  }
}

String _num(num? n) {
  if (n == null) return '-';
  return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

/// Human-readable lines describing a captured entry -- used by both the hub
/// review list and the capture app's own "Sent" list.
List<String> captureDetailLines(CaptureEntry e) {
  final p = e.payload;
  final date = fmtDateDisplay(p['date'] as String?);
  switch (e.module) {
    case CaptureModule.dieselUsage:
      final unit = p['unit'] == 'km' ? 'km' : 'hrs';
      return [
        '${_num(p['litres'] as num?)} L from ${p['tank_name'] ?? 'tank'} on $date',
        'Into: ${p['vehicle_name'] ?? '-'}${(p['reading'] as String? ?? '').isEmpty ? '' : ' · reading ${p['reading']} $unit'}',
        if (p['activity_name'] != null) 'Work: ${p['activity_name']}',
        if (p['employee_name'] != null) 'Filled by: ${p['employee_name']}',
      ];
    case CaptureModule.dieselPurchase:
      return [
        '${_num(p['litres'] as num?)} L delivered into ${p['tank_name'] ?? 'tank'} on $date',
        if ((p['supplier'] as String? ?? '').isNotEmpty) 'Supplier: ${p['supplier']}',
        if ((p['delivery_note'] as String? ?? '').isNotEmpty) 'Delivery note: ${p['delivery_note']}',
      ];
    case CaptureModule.hours:
      final lines = ((p['entries'] as List?) ?? const []).cast<Map>();
      return [
        '${p['mode'] == 'group' ? 'Group ${p['group_name'] ?? ''}' : 'Hours'} ${p['since_last_pay'] == true ? 'since the last pay (to $date)' : 'on $date'}',
        for (final l in lines) '${l['employee_name']}: ${_num(l['hours'] as num?)} h',
      ];
    case CaptureModule.kg:
      final lines = ((p['entries'] as List?) ?? const []).cast<Map>();
      return [
        'Picking on $date',
        for (final l in lines) '${l['employee_name']}: ${_num(l['kg'] as num?)} kg',
      ];
    case CaptureModule.tuckshop:
      if (p['manual_total'] != null) {
        return ['${p['employee_name']} · ${p['farm_name'] ?? ''} · $date', 'Amount: ${fmtRCents((p['manual_total'] as num).toDouble())}'];
      }
      final lines = ((p['lines'] as List?) ?? const []).cast<Map>();
      final total = lines.fold<double>(0, (s, l) => s + ((l['qty'] as num) * ((l['price'] as num?) ?? 0)));
      return [
        '${p['employee_name']} · ${p['farm_name'] ?? ''} · $date',
        for (final l in lines) '${_num(l['qty'] as num?)} × ${l['item_name']}',
        'Total about ${fmtRCents(total)} (worked out on approval)',
      ];
    case CaptureModule.delivery:
      final produce = p['produce_type'] as String? ?? '';
      final label = switch (produce) { 'potato' => 'Potatoes', 'pepper' => 'Peppers', 'butternut' => 'Butternuts', _ => produce };
      final unit = switch (produce) { 'potato' => 'pallets', 'pepper' => 'boxes', _ => 'bags' };
      return ['$label truck on $date: ${_num(p['total'] as num?)} $unit', 'Goes to Packaging > Records as a pending note'];
    case CaptureModule.payCheck:
      String r(Object? v) => fmtR(v as num?);
      return [
        'Payslips check: ${p['farm_name'] ?? ''}',
        for (final c in ((p['changes'] as List?) ?? const []).cast<Map>())
          [
            '${c['employee_name']}:',
            if (c['rate_per_hour'] != null) 'tariff ${fmtRCents(c['rate_per_hour'] as num)}/hr',
            if (c['loan_deduction'] != null) 'loan ${r(c['loan_deduction'])}',
            if (c['rent_deduction'] != null) 'rent ${r(c['rent_deduction'])}',
            if (c['hours_since_last_pay'] != null) 'hours since the last pay ${_num(c['hours_since_last_pay'] as num)} (was ${_num(c['hours_was'] as num?)})',
            if (c['tuckshop_debt'] != null) 'tuck shop debt at ${c['tuckshop_farm_name'] ?? 'Haaskraal'} ${r(c['tuckshop_debt'])}',
          ].join(' '),
        for (final x in ((p['extras'] as List?) ?? const []).cast<Map>())
          '${x['employee_name']}: extra ${x['description']} ${r(x['amount'])}',
      ];
    case CaptureModule.workGroups:
      final members = ((p['members'] as List?) ?? const []).cast<Map>();
      final removed = ((p['removed'] as List?) ?? const []).cast<Map>();
      return [
        'Work group ${p['group_name'] ?? ''}${p['group_id'] == null ? ' (new)' : ''} · ${p['farm_name'] ?? ''}',
        if (members.isNotEmpty) 'In it: ${members.map((m) => m['employee_name']).join(', ')}',
        if (removed.isNotEmpty) 'Taken out: ${removed.map((m) => m['employee_name']).join(', ')}',
      ];
    case CaptureModule.employee:
      final fields = [
        if (p['name'] != null) 'Name: ${p['name']}',
        if (p['id_or_passport'] != null) 'ID/passport: ${p['id_or_passport']}',
        if (p['full_names'] != null) 'Full names: ${p['full_names']}',
        if (p['surname'] != null) 'Surname: ${p['surname']}',
        if (p['farm_name'] != null) 'Farm: ${p['farm_name']}',
      ];
      return switch (p['action']) {
        'add' => ['New worker', ...fields],
        'remove' => ['${p['employee_name']} has left -- approving removes them from Employees > List'],
        _ => ['Change for ${p['employee_name']}', ...fields],
      };
    default:
      return [e.summary];
  }
}
