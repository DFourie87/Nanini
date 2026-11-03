import 'package:flutter/material.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../diesel/diesel_models.dart';
import '../diesel/diesel_repository.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'delivery_market_agents_screen.dart';
import 'delivery_models.dart';
import 'delivery_repository.dart';
import 'delivery_note_preview.dart';
import '../hours/hours_payslip_preview.dart' show confirmPdfPreview;
import '../../core/run_once.dart';

class DeliveryRecordsScreen extends StatelessWidget {
  const DeliveryRecordsScreen({super.key, required this.repo});
  final DeliveryRepository repo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DeliveryNote>>(
      stream: repo.watchNotes(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load delivery notes: ${snap.error}', textAlign: TextAlign.center),
            ),
          );
        }
        final notes = (snap.data ?? []).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        // Per produce sent; a truck with two produce (two notes, the same
        // day and registration) shows under both, each pointing to the other.
        final groups = deliveryNotesByProduce(notes);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // The delivery contacts and markets, any time (not only when approving).
            Align(alignment: Alignment.centerLeft, child: MarketAgentsButton(repo: repo)),
            if (notes.isEmpty) const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No delivery notes yet.'))),
            for (final (produce, list) in groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                child: Text('${produceLabel(produce)} (${list.length})', style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final n in list) _noteCard(context, n, sameTruck(n, notes)),
            ],
          ],
        );
      },
    );
  }

  Widget _noteCard(BuildContext context, DeliveryNote n, List<DeliveryNote> others) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: Icon(
            n.isApproved ? Icons.receipt_long : Icons.pending_actions,
            color: n.isApproved ? NaniniColors.green : NaniniColors.amber,
          ),
          title: Text('Note #${n.noteNumber ?? '-'} · ${produceLabel(n.produceType)}'),
          subtitle: Text([
            n.isApproved ? '${fmtDateDisplay(n.noteDate)} · ${n.reg ?? ''} · Total ${n.total}' : '${fmtDateDisplay(n.noteDate)} · Pending approval · Total ${n.total}',
            for (final o in others) 'Same truck as note #${o.noteNumber ?? '-'} (${produceLabel(o.produceType)})',
          ].join('\n')),
          isThreeLine: others.isNotEmpty,
          onTap: () => n.isApproved ? showDeliveryNotePreview(context, n) : _showApproveDialog(context, repo, n),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => runOnce('delivery_records_screen.1', () async {
              if (!await requireAdmin(context)) return;
              if (!context.mounted) return;
              final ok = await confirmDialog(context, message: 'Delete delivery note #${n.noteNumber}?', danger: true);
              if (ok) {
                await repo.deleteNote(n.id);
                if (context.mounted) showToast(context, 'Note deleted');
              }
            }),
          ),
        ),
      );
}

/// 'Potatoes', 'Peppers', 'Butternuts' for a note's produce.
String produceLabel(String produce) => switch (produce) {
      'potato' => 'Potatoes',
      'pepper' => 'Peppers',
      'butternut' => 'Butternuts',
      _ => produce.isEmpty ? 'Other' : '${produce[0].toUpperCase()}${produce.substring(1)}',
    };

/// The notes per produce (potatoes, peppers, butternuts, then any other),
/// each list in the order given; produce with no notes left out.
List<(String, List<DeliveryNote>)> deliveryNotesByProduce(List<DeliveryNote> notes) {
  const order = ['potato', 'pepper', 'butternut'];
  final kinds = {...order.where((p) => notes.any((n) => n.produceType == p)), ...notes.map((n) => n.produceType)};
  return [for (final p in kinds) (p, notes.where((n) => n.produceType == p).toList())];
}

/// The other produce's notes on the same truck: the same day and
/// registration (spaces and case aside), another produce.
List<DeliveryNote> sameTruck(DeliveryNote n, List<DeliveryNote> notes) {
  String reg(DeliveryNote x) => (x.reg ?? '').replaceAll(RegExp(r'\s'), '').toUpperCase();
  if (reg(n).isEmpty) return const [];
  return [for (final o in notes) if (o.id != n.id && o.produceType != n.produceType && o.noteDate == n.noteDate && reg(o) == reg(n)) o];
}

Future<void> _showApproveDialog(BuildContext context, DeliveryRepository repo, DeliveryNote note) async {
  final regCtrl = TextEditingController();
  final transportCtrl = TextEditingController();
  final extraCtrl = TextEditingController(text: note.agentExtra);
  List<MarketAgent> agents = [];
  List<Farm> farms = [];
  List<DieselVehicle> vehicles = [];
  String? agentId;
  String? field;
  String? farm = note.farm;
  bool isSelfTransport = note.isSelfTransport;
  // The day the truck left: as logged, but it can be corrected here (e.g.
  // a truck loaded over several days, or logged on a phone with the wrong
  // date) -- it's the date printed on the note.
  var noteDate = parseDateStr(note.noteDate) ?? DateTime.now();
  Future<void> loadAgents() async {
    try {
      agents = await repo.fetchCustomerChoices();
    } catch (_) {}
  }

  Future<void> loadFarms() async {
    try {
      farms = await EmployeesRepository().fetchFarms();
      farm ??= farms.isNotEmpty ? farms.first.name : null;
    } catch (_) {}
  }

  Future<void> loadVehicles() async {
    try {
      vehicles = await DieselRepository().watchVehicles().first;
    } catch (_) {}
  }

  await loadAgents();
  await loadFarms();
  await loadVehicles();

  // The FAW truck's registration from Diesel > Vehicles, if one is recorded.
  // Only lock the field when there's actually a registration to fill in.
  final fawTruck = vehicles.where((v) => v.name.toLowerCase().contains('faw')).firstOrNull;
  final fawReg = (fawTruck?.asset ?? '').trim();
  if (isSelfTransport && fawReg.isNotEmpty) regCtrl.text = fawReg;
  String? error;
  var saving = false;

  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final sortedAgents = [...agents]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return AlertDialog(
          title: dialogTitleWithError('Approve note #${note.noteNumber ?? '-'}', error),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => runOnce('delivery_records_screen.date', () async {
                    final d = await showDatePicker(context: ctx, initialDate: noteDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setLocal(() => noteDate = d);
                  }),
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date on the note', suffixIcon: Icon(Icons.calendar_today_outlined)),
                    child: Text(fmtDateDisplay(toDateStr(noteDate))),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: farm,
                  decoration: const InputDecoration(labelText: 'Farm'),
                  items: farms.map((f) => DropdownMenuItem(value: f.name, child: Text(f.name))).toList(),
                  onChanged: (v) => setLocal(() => farm = v),
                ),
                const SizedBox(height: 10),
                if (note.produceType == 'potato' || note.produceType == 'butternut') ...[
                  DropdownButtonFormField<String>(
                    initialValue: field,
                    decoration: const InputDecoration(labelText: 'Field'),
                    items: kFieldNames.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                    onChanged: (v) => setLocal(() => field = v),
                  ),
                  const SizedBox(height: 10),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Self transport'),
                  subtitle: const Text('Own truck -- no transport company to bill'),
                  value: isSelfTransport,
                  onChanged: (v) => setLocal(() {
                    isSelfTransport = v;
                    regCtrl.text = v ? fawReg : '';
                  }),
                ),
                const SizedBox(height: 10),
                if (!isSelfTransport) ...[
                  TextField(controller: transportCtrl, decoration: const InputDecoration(labelText: 'Transport company (optional)')),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: regCtrl,
                  readOnly: isSelfTransport && fawReg.isNotEmpty,
                  decoration: InputDecoration(
                    labelText: 'Truck registration (optional)',
                    helperText: isSelfTransport
                        ? (fawReg.isNotEmpty
                            ? 'FAW truck (from Diesel > Vehicles)'
                            : fawTruck == null
                                ? 'No FAW truck found in Diesel > Vehicles -- enter manually'
                                : 'FAW truck has no registration in Diesel > Vehicles -- enter manually')
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: agentId,
                        decoration: const InputDecoration(labelText: 'Customer'),
                        items: sortedAgents.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                        onChanged: (v) => setLocal(() => agentId = v),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: 'Delivery contacts and markets (admin)',
                      onPressed: () => runOnce('delivery_records_screen.2', () async {
                        if (!await requireAdmin(ctx)) return;
                        if (!ctx.mounted) return;
                        await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => DeliveryMarketAgentsScreen(repo: repo)));
                        await loadAgents();
                        setLocal(() {});
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Printed under the customer's name, when needed.
                TextField(
                  key: const Key('delivery_extra_line'),
                  controller: extraCtrl,
                  decoration: const InputDecoration(labelText: 'Extra line under the customer (optional)', helperText: 'Printed on the note below the agent\'s name'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () => runOnce('delivery_records_screen.3', () async {
                      // Truck registration and transport company are optional.
                      final agent = agents.where((a) => a.id == agentId).firstOrNull;
                      // First the note as it will be printed: approve it, or
                      // back to this window to change things (as for a payroll run).
                      final draft = DeliveryNote(
                        id: note.id,
                        noteNumber: note.noteNumber,
                        reg: _orNull(regCtrl.text),
                        transportCompany: isSelfTransport ? null : _orNull(transportCtrl.text),
                        isSelfTransport: isSelfTransport,
                        agentName: agent?.name,
                        agentAttention: agent?.attention,
                        agentMarket: agent?.market,
                        agentExtra: _orNull(extraCtrl.text),
                        noteDate: toDateStr(noteDate),
                        target: note.target,
                        field: field ?? '',
                        farm: farm,
                        pallets: note.pallets,
                        mixedPallets: note.mixedPallets,
                        produceType: note.produceType,
                        produceDetail: note.produceDetail,
                        total: note.total,
                        createdAt: note.createdAt,
                      );
                      final ok = await confirmPdfPreview(
                        ctx,
                        () => buildDeliveryNotePdf(draft),
                        title: 'Delivery note #${note.noteNumber ?? '-'}',
                        approveLabel: 'Approve note',
                      );
                      if (!ok || !ctx.mounted) return;
                      setLocal(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await repo.approveNote(
                          note.id,
                          reg: _orNull(regCtrl.text),
                          transportCompany: _orNull(transportCtrl.text),
                          isSelfTransport: isSelfTransport,
                          field: field,
                          agent: agent,
                          farm: farm,
                          noteDate: toDateStr(noteDate),
                          agentExtra: _orNull(extraCtrl.text),
                        );
                      } catch (e) {
                        if (ctx.mounted) {
                          setLocal(() {
                            saving = false;
                            error = 'Could not approve: ${friendlyDbError(e)}';
                          });
                        }
                        return;
                      }
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (context.mounted) showToast(context, 'Note approved -- ready to print');
                    }),
              child: Text(saving ? 'Approving…' : 'Approve'),
            ),
          ],
        );
      },
    ),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Trimmed text, or null when nothing was typed (optional fields).
String? _orNull(String text) => text.trim().isEmpty ? null : text.trim();
