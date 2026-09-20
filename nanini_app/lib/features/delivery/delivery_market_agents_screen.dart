import 'package:flutter/material.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'delivery_models.dart';
import 'delivery_repository.dart';

/// Admin-only market agent / recipient list -- add, edit, and remove the
/// entries the "Market agent" dropdowns across the packaging module offer.
class DeliveryMarketAgentsScreen extends StatefulWidget {
  const DeliveryMarketAgentsScreen({super.key, required this.repo});
  final DeliveryRepository repo;

  @override
  State<DeliveryMarketAgentsScreen> createState() => _DeliveryMarketAgentsScreenState();
}

class _DeliveryMarketAgentsScreenState extends State<DeliveryMarketAgentsScreen> {
  List<MarketAgent>? agents;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final fresh = await widget.repo.fetchMarketAgents();
    if (mounted) setState(() => agents = [...fresh]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
  }

  @override
  Widget build(BuildContext context) {
    final list = agents;
    return Scaffold(
      appBar: AppBar(title: const Text('Market agents')),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No market agents yet.'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () async {
                            if (!await requireAdmin(context)) return;
                            if (!context.mounted) return;
                            await _showAgentDialog(context, widget.repo);
                            await _refresh();
                          },
                          child: const Text('Add market agent'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final a in list)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(a.name),
                          subtitle: Text([
                            if (a.attention?.trim().isNotEmpty ?? false) a.attention!,
                            if (a.market?.trim().isNotEmpty ?? false) a.market!,
                          ].join(' · ')),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () async {
                                  if (!await requireAdmin(context)) return;
                                  if (!context.mounted) return;
                                  await _showAgentDialog(context, widget.repo, existing: a);
                                  await _refresh();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: NaniniColors.red),
                                onPressed: () async {
                                  if (!await requireAdmin(context)) return;
                                  if (!context.mounted) return;
                                  final ok = await confirmDialog(
                                    context,
                                    message: 'Remove "${a.name}"? Past records that reference it are kept.',
                                  );
                                  if (!ok) return;
                                  await widget.repo.deleteMarketAgent(a.id);
                                  if (context.mounted) showToast(context, 'Removed');
                                  await _refresh();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
      floatingActionButton: list == null
          ? null
          : FloatingActionButton(
              onPressed: () async {
                if (!await requireAdmin(context)) return;
                if (!context.mounted) return;
                await _showAgentDialog(context, widget.repo);
                await _refresh();
              },
              child: const Icon(Icons.add),
            ),
    );
  }
}

Future<void> _showAgentDialog(BuildContext context, DeliveryRepository repo, {MarketAgent? existing}) async {
  final nameCtrl = TextEditingController(text: existing?.name);
  final attentionCtrl = TextEditingController(text: existing?.attention);
  final marketCtrl = TextEditingController(text: existing?.market);

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'Add market agent' : 'Edit market agent'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Agent name')),
          const SizedBox(height: 10),
          TextField(controller: attentionCtrl, decoration: const InputDecoration(labelText: 'Attention (contact person)')),
          const SizedBox(height: 10),
          TextField(controller: marketCtrl, decoration: const InputDecoration(labelText: 'Market')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            if (existing == null) {
              await repo.addMarketAgent(name: name, attention: attentionCtrl.text.trim(), market: marketCtrl.text.trim());
            } else {
              await repo.updateMarketAgent(existing.id, name: name, attention: attentionCtrl.text.trim(), market: marketCtrl.text.trim());
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
