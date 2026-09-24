import 'package:flutter/material.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import 'hunting_models.dart';
import 'hunting_repository.dart';

/// P3 government exemption certificates -- one certificate's permit number
/// auto-fills the transport permit's blank "EXEMPTION PERMIT NUMBER" line
/// for that farm (see hunting_document_preview.dart), and the nearest
/// expiry drives the renewal warning shown on opening the module. Just the
/// certificate's details are recorded here, not the document itself.
class HuntingCertificatesScreen extends StatefulWidget {
  const HuntingCertificatesScreen({super.key, required this.repo});
  final HuntingRepository repo;
  @override
  State<HuntingCertificatesScreen> createState() => _HuntingCertificatesScreenState();
}

class _HuntingCertificatesScreenState extends State<HuntingCertificatesScreen> {
  List<Farm> farms = [];

  @override
  void initState() {
    super.initState();
    fetchHuntingFarms().then((f) {
      if (!mounted) return;
      setState(() => farms = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<List<HuntingExemptionCertificate>>(
          stream: widget.repo.watchCertificates(),
          builder: (context, snap) {
            final certs = (snap.data ?? []).toList()..sort((a, b) => b.expiryDate.compareTo(a.expiryDate));
            return certs.isEmpty
                ? const Center(child: Text('No certificates recorded yet.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    itemCount: certs.length,
                    itemBuilder: (context, i) {
                      final c = certs[i];
                      final farm = farms.where((f) => f.id == c.farmId).firstOrNull;
                      final expiry = parseDateStr(c.expiryDate);
                      final daysLeft = expiry == null ? null : expiry.difference(DateTime.now()).inDays;
                      final Color statusColor = daysLeft == null
                          ? NaniniColors.muted
                          : daysLeft < 0
                              ? NaniniColors.red
                              : daysLeft <= 90
                                  ? NaniniColors.amber
                                  : NaniniColors.green;
                      return Card(
                        child: ListTile(
                          title: Text(farm?.name ?? 'Unknown farm'),
                          subtitle: Text(
                            '${(c.permitNumber ?? '').isEmpty ? 'No permit number' : 'No: ${c.permitNumber}'} · '
                            'Expires ${fmtDateDisplay(c.expiryDate)}'
                            '${daysLeft != null ? (daysLeft < 0 ? ' · EXPIRED' : ' · $daysLeft days left') : ''}',
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              if (!await requireAdmin(context)) return;
                              if (!context.mounted) return;
                              final ok = await confirmDialog(context, message: 'Delete this certificate record?', danger: true);
                              if (ok) await widget.repo.deleteCertificate(c.id);
                            },
                          ),
                        ),
                      );
                    },
                  );
          },
        ),
        Positioned(
          right: 16,
          bottom: 32,
          child: FloatingActionButton.extended(
            onPressed: () async {
              if (!await requireAdmin(context)) return;
              if (!context.mounted) return;
              await _showAddDialog(context);
            },
            icon: const Icon(Icons.add),
            label: const Text('Add certificate'),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    if (farms.isEmpty) return;
    var farmId = farms.first.id;
    final permitCtrl = TextEditingController();
    var issueDate = todayStr();
    var expiryDate = todayStr();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add certificate'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: farmId,
                  decoration: const InputDecoration(labelText: 'Farm'),
                  items: farms.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
                  onChanged: (v) => setLocal(() => farmId = v!),
                ),
                const SizedBox(height: 10),
                TextField(controller: permitCtrl, decoration: const InputDecoration(labelText: 'Exemption permit number')),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Issue date: ${fmtDateDisplay(issueDate)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final d = await showDatePicker(context: ctx, initialDate: parseDateStr(issueDate) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setLocal(() => issueDate = toDateStr(d));
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Expiry date: ${fmtDateDisplay(expiryDate)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final d = await showDatePicker(context: ctx, initialDate: parseDateStr(expiryDate) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setLocal(() => expiryDate = toDateStr(d));
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                await widget.repo.addCertificate(
                  farmId: farmId,
                  permitNumber: permitCtrl.text.trim().isEmpty ? null : permitCtrl.text.trim(),
                  issueDate: issueDate,
                  expiryDate: expiryDate,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
