import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import 'capture_models.dart';
import 'capture_repository.dart';

/// Where phones download the Nanini Capture app (the latest build).
const _captureApkUrl = 'https://github.com/DFourie87/Nanini/releases/latest/download/nanini-capture.apk';

/// Admin list of phones running the Nanini Capture app: rename them, choose
/// which tasks each shows, or switch one off (e.g. a lost phone).
class CapturePhonesScreen extends StatelessWidget {
  const CapturePhonesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = CaptureRepository();
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Capture phones'),
      body: StreamBuilder<List<CaptureDevice>>(
        stream: repo.watchDevices(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Could not load: ${friendlyDbError(snap.error!)}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final devices = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Phones appear here after the Nanini Capture app is set up on them and has been on Wi-Fi once. Approve each new phone before it can be used. '
                'Install the app on a phone from this link:',
                style: TextStyle(color: NaniniColors.muted),
              ),
              const SizedBox(height: 6),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.link, color: NaniniColors.rust),
                  title: const SelectableText(_captureApkUrl, style: TextStyle(fontSize: 13)),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                    onPressed: () async {
                      await Clipboard.setData(const ClipboardData(text: _captureApkUrl));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied -- paste it in WhatsApp or a message to the phone')));
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (devices.isEmpty) const Text('No phones yet.'),
              for (final d in devices.where((d) => !d.approved))
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.new_releases, color: NaniniColors.amber),
                          const SizedBox(width: 8),
                          Expanded(child: Text(d.name, style: Theme.of(context).textTheme.titleMedium)),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          'NEW PHONE -- waiting for approval. First seen ${d.lastSeenAt == null ? '' : fmtDateTimeDisplay(d.lastSeenAt!.toIso8601String())}. '
                          'Only approve a phone you set up yourself.',
                          style: const TextStyle(color: NaniniColors.muted),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: () async {
                                if (await confirmDialog(context, message: 'Remove "${d.name}"? It will not be able to send anything.', danger: true) &&
                                    context.mounted) {
                                  await trySave(context, () => repo.deleteDevice(d.id));
                                }
                              },
                              child: const Text('Remove'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => trySave(context, () => repo.updateDevice(d.id, approved: true, active: true)),
                              child: const Text('Approve'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              for (final d in devices.where((d) => d.approved))
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Icon(Icons.phone_android, color: d.active ? NaniniColors.green : NaniniColors.muted),
                    title: Text(d.name),
                    subtitle: Text(
                      '${d.modules.map(CaptureTask.label).join(', ')}\n'
                      'Last on Wi-Fi: ${d.lastSeenAt == null ? 'never' : fmtDateTimeDisplay(d.lastSeenAt!.toIso8601String())}'
                      '${d.active ? '' : ' · SWITCHED OFF'}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _edit(context, repo, d),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, CaptureRepository repo, CaptureDevice d) async {
    final nameCtrl = TextEditingController(text: d.name);
    final modules = d.modules.toSet();
    var active = d.active;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Capture phone'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Phone name')),
                const SizedBox(height: 12),
                Text('Tasks shown on this phone', style: Theme.of(ctx).textTheme.titleSmall),
                for (final t in CaptureTask.all)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(CaptureTask.label(t)),
                    value: modules.contains(t),
                    onChanged: (v) => setLocal(() => v == true ? modules.add(t) : modules.remove(t)),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Phone switched on'),
                  subtitle: const Text('Off: the phone can no longer capture'),
                  value: active,
                  onChanged: (v) => setLocal(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (await _remove(ctx, repo, d) && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Remove phone', style: TextStyle(color: NaniniColors.red)),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return showProblem(ctx, 'Enter a name for the phone.');
                if (modules.isEmpty) return showProblem(ctx, 'Choose at least one task.');
                final ok = await trySave(
                  ctx,
                  () => repo.updateDevice(d.id, name: name, modules: CaptureTask.all.where(modules.contains).toList(), active: active),
                );
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Asks first (warning about entries still waiting for approval), then
  /// deletes the phone. True if it was removed.
  Future<bool> _remove(BuildContext context, CaptureRepository repo, CaptureDevice d) async {
    int pending;
    try {
      pending = await repo.pendingCountForDevice(d.id);
    } catch (e) {
      if (context.mounted) await showProblem(context, friendlyDbError(e), title: 'Could not check the phone');
      return false;
    }
    if (!context.mounted) return false;
    final ok = await confirmDialog(
      context,
      message: pending > 0
          ? 'Remove "${d.name}"?\n\n$pending entr${pending == 1 ? 'y' : 'ies'} from this phone ${pending == 1 ? 'is' : 'are'} still waiting for approval '
              'and will be deleted. Approve or reject ${pending == 1 ? 'it' : 'them'} first if you want to keep ${pending == 1 ? 'it' : 'them'}.\n\n'
              'Entries already approved stay in the records. The phone will need to be set up and approved again to capture.'
          : 'Remove "${d.name}"?\n\nEntries already approved stay in the records. The phone will need to be set up and approved again to capture.',
      title: 'Remove phone?',
      confirmLabel: 'Remove',
      danger: true,
    );
    if (!ok || !context.mounted) return false;
    return trySave(context, () => repo.deleteDevice(d.id));
  }
}
