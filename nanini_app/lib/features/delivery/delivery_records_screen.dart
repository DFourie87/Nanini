import 'package:flutter/material.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'delivery_market_agents_screen.dart';
import 'delivery_models.dart';
import 'delivery_repository.dart';
import 'delivery_note_preview.dart';

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
        if (notes.isEmpty) return const Center(child: Text('No delivery notes yet.'));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: notes.length,
          itemBuilder: (context, i) {
            final n = notes[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(
                  n.isApproved ? Icons.receipt_long : Icons.pending_actions,
                  color: n.isApproved ? NaniniColors.green : NaniniColors.amber,
                ),
                title: Text('Note #${n.noteNumber ?? '-'} · ${n.produceType}'),
                subtitle: Text(n.isApproved
                    ? '${fmtDateDisplay(n.noteDate)} · ${n.reg ?? ''} · Total ${n.total}'
                    : '${fmtDateDisplay(n.noteDate)} · Pending approval · Total ${n.total}'),
                onTap: () => n.isApproved ? showDeliveryNotePreview(context, n) : _showApproveDialog(context, repo, n),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (!await requireAdmin(context)) return;
                    if (!context.mounted) return;
                    final ok = await confirmDialog(context, message: 'Delete delivery note #${n.noteNumber}?', danger: true);
                    if (ok) {
                      await repo.deleteNote(n.id);
                      if (context.mounted) showToast(context, 'Note deleted');
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

Future<void> _showApproveDialog(BuildContext context, DeliveryRepository repo, DeliveryNote note) async {
  final regCtrl = TextEditingController();
  final transportCtrl = TextEditingController();
  List<MarketAgent> agents = [];
  String? agentId;
  String? field;
  Future<void> loadAgents() async {
    try {
      agents = await repo.fetchMarketAgents();
    } catch (_) {}
  }

  await loadAgents();

  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final sortedAgents = [...agents]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return AlertDialog(
          title: Text('Approve note #${note.noteNumber ?? '-'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (note.produceType == 'potato' || note.produceType == 'butternut') ...[
                  DropdownButtonFormField<String>(
                    initialValue: field,
                    decoration: const InputDecoration(labelText: 'Field'),
                    items: kFieldNames.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                    onChanged: (v) => setLocal(() => field = v),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(controller: transportCtrl, decoration: const InputDecoration(labelText: 'Transport company')),
                const SizedBox(height: 10),
                TextField(controller: regCtrl, decoration: const InputDecoration(labelText: 'Truck registration *')),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: agentId,
                        decoration: const InputDecoration(labelText: 'Market agent'),
                        items: sortedAgents.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                        onChanged: (v) => setLocal(() => agentId = v),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: 'Manage market agents (admin)',
                      onPressed: () async {
                        if (!await requireAdmin(ctx)) return;
                        if (!ctx.mounted) return;
                        await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => DeliveryMarketAgentsScreen(repo: repo)));
                        await loadAgents();
                        setLocal(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (regCtrl.text.trim().isEmpty) {
                  showToast(ctx, 'Truck registration is required', isError: true);
                  return;
                }
                final agent = agents.where((a) => a.id == agentId).firstOrNull;
                await repo.approveNote(
                  note.id,
                  reg: regCtrl.text.trim(),
                  transportCompany: transportCtrl.text.trim(),
                  field: field,
                  agent: agent,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (context.mounted) showToast(context, 'Note approved -- ready to print');
              },
              child: const Text('Approve'),
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
