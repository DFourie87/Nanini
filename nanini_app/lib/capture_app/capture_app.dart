import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/widgets/dialog_error.dart';
import '../features/capture/capture_models.dart';
import '../features/capture/captured_review_screen.dart' show captureDetailLines;
import '../theme/nanini_theme.dart';
import 'capture_store.dart';
import 'capture_widgets.dart';
import 'flows/delivery_flow.dart';
import 'flows/diesel_flow.dart';
import 'flows/hours_flow.dart';
import 'flows/tuckshop_flow.dart';

/// "Nanini Capture" -- the separate, offline-first capturing app for farm
/// workers' phones. Not part of the hub: it only writes entries that wait
/// for a manager's approval in the hub apps.
class CaptureApp extends StatelessWidget {
  const CaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CaptureStore()..load(),
      child: MaterialApp(
        title: 'Nanini Capture',
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        theme: NaniniTheme.light,
        home: const _Gate(),
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();
  @override
  Widget build(BuildContext context) {
    final store = context.watch<CaptureStore>();
    if (!store.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return store.isSetUp ? const CaptureHomeScreen() : const _SetupScreen();
  }
}

class _SetupScreen extends StatefulWidget {
  const _SetupScreen();
  @override
  State<_SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<_SetupScreen> {
  final nameCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Image.asset('assets/images/hub-logo.jpg', height: 120),
            const SizedBox(height: 16),
            Text('Set up this phone', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            const Text(
              'For the manager: give this phone a name so the office knows where entries come from, '
              'e.g. "Diesel pump phone" or "Johannes – Haaskraal". Everything captured on it is marked with this name.',
              style: TextStyle(fontSize: 17),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(fontSize: 22),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Phone name'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 64,
              child: FilledButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isEmpty) {
                    showProblem(context, 'Type a name for this phone.');
                    return;
                  }
                  context.read<CaptureStore>().setUp(nameCtrl.text);
                },
                child: const Text('SAVE', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Then connect the phone to Wi-Fi once so it can download the lists of people, tanks and vehicles.',
              style: TextStyle(fontSize: 16, color: NaniniColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class CaptureHomeScreen extends StatelessWidget {
  const CaptureHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CaptureStore>();
    // (emoji, label, accent colour, screen) -- each task has its own colour
    // from the Nanini palette so workers can find it at a glance.
    final tiles = <(String, String, Color, WidgetBuilder)>[
      if (store.tasks.contains(CaptureTask.diesel)) ('⛽', 'DIESEL', NaniniColors.rust, (_) => const DieselFlow()),
      if (store.tasks.contains(CaptureTask.packaging)) ('📦', 'PACKAGING', NaniniColors.amber, (_) => const DeliveryFlow()),
      if (store.tasks.contains(CaptureTask.hours)) ('🕒', 'HOURS', NaniniColors.green, (_) => const HoursFlow()),
      if (store.tasks.contains(CaptureTask.tuckshop)) ('🛒', 'TUCK SHOP', NaniniColors.rustDark, (_) => const TuckshopFlow()),
    ];
    return Scaffold(
      // Warm cream behind the white cards, from the Nanini palette.
      backgroundColor: NaniniColors.disabledBg,
      appBar: AppBar(
        toolbarHeight: 76,
        backgroundColor: NaniniColors.paper,
        surfaceTintColor: NaniniColors.paper,
        title: Row(
          children: [
            Image.asset('assets/images/hub-logo.jpg', height: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Data Capturing', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 24, fontWeight: FontWeight.w700, color: NaniniColors.ink)),
                  Text(store.deviceName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: NaniniColors.red)),
                ],
              ),
            ),
          ],
        ),
        // A brand-red rule under the header.
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(4),
          child: ColoredBox(color: NaniniColors.rust, child: SizedBox(height: 4, width: double.infinity)),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SyncBanner(store: store),
            const SizedBox(height: 12),
            if (!store.deviceApproved)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    store.lastSync == null
                        ? 'Connect this phone to Wi-Fi so the office can see it and approve it.'
                        : 'Waiting for the office to approve this phone. '
                            'Manager: in the Nanini app, open your profile menu > Capture phones > Approve "${store.deviceName}".',
                    style: const TextStyle(fontSize: 20, color: NaniniColors.amber, fontWeight: FontWeight.w700),
                  ),
                ),
              )
            else if (!store.deviceActive)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('This phone has been switched off by the office. Ask the manager.',
                      style: TextStyle(fontSize: 20, color: NaniniColors.red, fontWeight: FontWeight.w700)),
                ),
              )
            else ...[
              if (store.ref.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Connect to Wi-Fi once so the phone can download the lists (people, tanks, vehicles…).',
                        style: TextStyle(fontSize: 18, color: NaniniColors.amber, fontWeight: FontWeight.w600)),
                  ),
                ),
              for (final (emoji, label, accent, builder) in tiles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: NaniniColors.paper,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: accent, width: 2)),
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: builder)),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(width: 12, color: accent),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 76,
                                      height: 76,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), shape: BoxShape.circle),
                                      child: Text(emoji, style: const TextStyle(fontSize: 44)),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      child: Text(label, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: NaniniColors.ink)),
                                    ),
                                    Icon(Icons.chevron_right, size: 40, color: accent),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _SentScreen())),
                icon: const Icon(Icons.list_alt, size: 28),
                label: const Text('WHAT I SENT', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.store});
  final CaptureStore store;

  @override
  Widget build(BuildContext context) {
    final waiting = store.queue.length;
    final (Color color, IconData icon, String text) = store.syncing
        ? (NaniniColors.rust, Icons.sync, 'Sending…')
        : waiting == 0
            ? (NaniniColors.green, Icons.check_circle, 'Everything is sent')
            : (NaniniColors.amber, Icons.cloud_upload, '$waiting waiting to send');
    return Card(
      color: Color.alphaBlend(color.withValues(alpha: 0.12), NaniniColors.paper),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color, width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 40, color: color),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color))),
                if (!store.syncing)
                  IconButton(
                    iconSize: 34,
                    tooltip: 'Send now',
                    color: NaniniColors.ink,
                    onPressed: () => store.onWifi ? store.sync() : showNeed(context, 'Connect to Wi-Fi to send'),
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            if (store.lastError != null && store.onWifi) ...[
              const SizedBox(height: 4),
              Text(
                store.lastError!.startsWith('No internet')
                    ? 'Wi-Fi has no internet right now -- it will try again.'
                    : 'Could not reach the office system. Show this to the manager:',
                style: const TextStyle(fontSize: 14, color: NaniniColors.red, fontWeight: FontWeight.w600),
              ),
              if (!store.lastError!.startsWith('No internet'))
                SelectableText(store.lastError!, style: const TextStyle(fontSize: 13, color: NaniniColors.red)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SentScreen extends StatelessWidget {
  const _SentScreen();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CaptureStore>();
    final all = [...store.queue.reversed.map((e) => (e, true)), ...store.sent.map((e) => (e, false))];
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      appBar: AppBar(title: const Text('What I sent', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
      body: all.isEmpty
          ? const Center(child: Text('Nothing yet.', style: TextStyle(fontSize: 20, color: NaniniColors.muted)))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final (e, onPhone) in all)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            onPhone
                                ? Icons.phone_android
                                : switch (e.status) { 'approved' => Icons.check_circle, 'rejected' => Icons.cancel, _ => Icons.hourglass_top },
                            size: 36,
                            color: onPhone
                                ? NaniniColors.amber
                                : switch (e.status) { 'approved' => NaniniColors.green, 'rejected' => NaniniColors.red, _ => NaniniColors.muted },
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(CaptureModule.label(e.module), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                                for (final line in captureDetailLines(e).take(4)) Text(line, style: const TextStyle(fontSize: 16)),
                                Text(
                                  onPhone
                                      ? 'On the phone -- not sent yet'
                                      : switch (e.status) {
                                          'approved' => 'Approved by the office',
                                          'rejected' => 'NOT accepted${(e.rejectReason ?? '').isEmpty ? '' : ': ${e.rejectReason}'}',
                                          _ => 'Sent -- waiting for the office',
                                        },
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: e.status == 'rejected' && !onPhone ? NaniniColors.red : NaniniColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
