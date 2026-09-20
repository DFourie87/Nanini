import 'package:flutter/material.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
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
                title: Text('Note #${n.noteNumber ?? '-'} · ${n.produceType}'),
                subtitle: Text('${fmtDateDisplay(n.noteDate)} · ${n.reg ?? ''} · Total ${n.total}'),
                onTap: () => showDeliveryNotePreview(context, n),
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
