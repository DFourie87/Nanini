import 'package:flutter/material.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'delivery_models.dart';
import 'delivery_repository.dart';
import '../../core/run_once.dart';

/// Admin-only list of the customers a delivery note can go to -- the same
/// list as the note's Customer dropdown: every customer from Sales >
/// Customers (its contact person and market set here), plus recipients that
/// are no customer (added, edited and removed here).
class DeliveryMarketAgentsScreen extends StatefulWidget {
  const DeliveryMarketAgentsScreen({super.key, required this.repo});
  final DeliveryRepository repo;

  @override
  State<DeliveryMarketAgentsScreen> createState() => _DeliveryMarketAgentsScreenState();
}

class _DeliveryMarketAgentsScreenState extends State<DeliveryMarketAgentsScreen> {
  List<MarketAgent>? agents;

  /// The delivery recipients (their own names, for a customer's row).
  List<MarketAgent> recipients = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final fresh = await widget.repo.fetchCustomerChoices();
    final r = await widget.repo.fetchMarketAgents();
    if (mounted) {
      setState(() {
        recipients = r;
        agents = [...fresh]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = agents;
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery note customers')),
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
                          onPressed: () => runOnce('delivery_market_agents_screen.1', () async {
                            if (!await requireAdmin(context)) return;
                            if (!context.mounted) return;
                            await _showAgentDialog(context, widget.repo);
                            await _refresh();
                          }),
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
                            if (a.isCustomer && (a.attention?.trim().isEmpty ?? true) && (a.market?.trim().isEmpty ?? true)) 'No contact or market yet -- tap the pencil to add',
                          ].join(' · ')),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => runOnce('delivery_market_agents_screen.2', () async {
                                  if (!await requireAdmin(context)) return;
                                  if (!context.mounted) return;
                                  await _showAgentDialog(context, widget.repo, existing: a, recipients: recipients);
                                  await _refresh();
                                }),
                              ),
                              // A customer is removed in Sales > Customers.
                              if (!a.isCustomer)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: NaniniColors.red),
                                  onPressed: () => runOnce('delivery_market_agents_screen.3', () async {
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
                                  }),
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
              onPressed: () => runOnce('delivery_market_agents_screen.4', () async {
                if (!await requireAdmin(context)) return;
                if (!context.mounted) return;
                await _showAgentDialog(context, widget.repo);
                await _refresh();
              }),
              child: const Icon(Icons.add),
            ),
    );
  }
}

Future<void> _showAgentDialog(BuildContext context, DeliveryRepository repo, {MarketAgent? existing, List<MarketAgent> recipients = const []}) async {
  final customer = existing?.isCustomer ?? false;
  final nameCtrl = TextEditingController(text: existing?.name);
  final attentionCtrl = TextEditingController(text: existing?.attention);
  final marketCtrl = TextEditingController(text: existing?.market);

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'Add market agent' : customer ? existing.name : 'Edit market agent'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A customer's name comes from Sales > Customers.
          if (!customer) ...[
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Agent name')),
            const SizedBox(height: 10),
          ],
          TextField(controller: attentionCtrl, decoration: const InputDecoration(labelText: 'Attention (contact person)')),
          const SizedBox(height: 10),
          TextField(controller: marketCtrl, decoration: const InputDecoration(labelText: 'Market')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => runOnce('delivery_market_agents_screen.5', () async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return showProblem(ctx, 'Enter the market agent name.');
            if (customer) {
              // Its own recipient row, else a new one with the customer's name.
              final r = recipients.where((r) => r.id == existing!.recipientId).firstOrNull;
              if (r != null) {
                await repo.updateMarketAgent(r.id, name: r.name, attention: attentionCtrl.text.trim(), market: marketCtrl.text.trim());
              } else {
                await repo.addMarketAgent(name: existing!.name, attention: attentionCtrl.text.trim(), market: marketCtrl.text.trim());
              }
            } else if (existing == null) {
              await repo.addMarketAgent(name: name, attention: attentionCtrl.text.trim(), market: marketCtrl.text.trim());
            } else {
              await repo.updateMarketAgent(existing.id, name: name, attention: attentionCtrl.text.trim(), market: marketCtrl.text.trim());
            }
            if (ctx.mounted) Navigator.pop(ctx);
          }),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
