import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/update/update_banner.dart';
import '../core/widgets/dialog_error.dart';
import '../features/capture/capture_models.dart';
import '../features/capture/captured_review_screen.dart' show captureDetailLines;
import '../theme/nanini_theme.dart';
import 'capture_store.dart';
import 'capture_widgets.dart';
import 'flows/delivery_flow.dart';
import 'flows/diesel_flow.dart';
import 'flows/employee_flow.dart';
import 'flows/hours_flow.dart';
import 'flows/payslips_flow.dart';
import 'flows/supplier_flow.dart';
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

/// Width of the logo and the "Data Capturing" line in the home header.
const _kHeaderWidth = 170.0;
const _kHeaderIconsWidth = 56.0;

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
      if (store.tasks.contains(CaptureTask.employees)) ('🪪', 'EMPLOYEES', NaniniColors.muted, (_) => const EmployeeFlow()),
      if (store.tasks.contains(CaptureTask.payslips)) ('💵', 'PAYSLIPS', NaniniColors.green, (_) => const PayslipsFlow()),
      if (store.tasks.contains(CaptureTask.suppliers)) ('🧾', 'SUPPLIERS', NaniniColors.amber, (_) => const SupplierFlow()),
    ];
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      appBar: AppBar(
        toolbarHeight: 196,
        backgroundColor: NaniniColors.paper,
        surfaceTintColor: NaniniColors.paper,
        automaticallyImplyLeading: false,
        centerTitle: true,
        titleSpacing: 4,
        title: Row(
          children: [
            // Send status (tick / cross) on the left, send-now on the right.
            SizedBox(width: _kHeaderIconsWidth, child: _SyncStatus(store: store)),
            const Spacer(),
            SizedBox(
              width: _kHeaderWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo as wide as the "Data Capturing" line under it.
                  Image.asset('assets/images/hub-logo.jpg', width: _kHeaderWidth, fit: BoxFit.fitWidth),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.fitWidth,
                    child: Text('Data Capturing', maxLines: 1, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, color: NaniniColors.ink)),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(store.deviceName, maxLines: 1, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: NaniniColors.red)),
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(width: _kHeaderIconsWidth, child: _SyncButton(store: store)),
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
            // Wi-Fi only, like everything else this phone downloads.
            UpdateBanner(enabled: store.onWifi, padding: const EdgeInsets.only(bottom: 12)),
            if (_realError(store) case final err?) ...[
              _ErrorCard(error: err),
              const SizedBox(height: 12),
            ],
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
                                      // Always one line: long names shrink to fit.
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: NaniniColors.ink)),
                                      ),
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

/// A problem worth showing the manager -- the office system refusing
/// something. A Wi-Fi with no internet just shows as the red cross.
String? _realError(CaptureStore store) {
  final e = store.lastError;
  return e == null || !store.onWifi || e.startsWith('No internet') ? null : e;
}

/// Green tick when everything is sent; red cross while entries are still on
/// the phone or the last send failed. Tapping it says why.
class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.store});
  final CaptureStore store;

  @override
  Widget build(BuildContext context) {
    final waiting = store.queue.length;
    final ok = waiting == 0 && store.lastError == null;
    return IconButton(
      iconSize: 40,
      tooltip: ok ? 'Everything is sent' : 'Not sent yet',
      onPressed: () => showNeed(
        context,
        ok
            ? 'Everything is sent'
            : waiting == 0
                ? 'Could not reach the office -- it will try again'
                : '$waiting waiting to send${store.onWifi ? '' : ' -- connect to Wi-Fi'}',
      ),
      icon: Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? NaniniColors.green : NaniniColors.red),
    );
  }
}

/// Send now (black refresh), or a spinner while sending.
class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.store});
  final CaptureStore store;

  @override
  Widget build(BuildContext context) {
    if (store.syncing) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: NaniniColors.ink)),
      );
    }
    return IconButton(
      iconSize: 36,
      tooltip: 'Send now',
      color: NaniniColors.ink,
      onPressed: () => store.onWifi ? store.sync() : showNeed(context, 'Connect to Wi-Fi to send'),
      icon: const Icon(Icons.refresh),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: NaniniColors.red, width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Could not reach the office system. Show this to the manager:',
                style: TextStyle(fontSize: 14, color: NaniniColors.red, fontWeight: FontWeight.w600)),
            SelectableText(error, style: const TextStyle(fontSize: 13, color: NaniniColors.red)),
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
