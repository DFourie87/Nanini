import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import 'capture_models.dart';
import 'capture_repository.dart';

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
                'Phones appear here after the Nanini Capture app is set up on them and has been on Wi-Fi once. '
                'Install it from: github.com/DFourie87/Nanini/releases/latest/download/nanini-capture.apk',
                style: TextStyle(color: NaniniColors.muted),
              ),
              const SizedBox(height: 12),
              if (devices.isEmpty) const Text('No phones yet.'),
              for (final d in devices)
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
}
