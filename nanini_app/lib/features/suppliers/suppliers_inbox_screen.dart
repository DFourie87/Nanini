import 'package:flutter/material.dart';

import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import '../capture/capture_models.dart';
import '../capture/capture_repository.dart';
import '../capture/captured_review_screen.dart';
import 'suppliers_data.dart';
import 'suppliers_recon_screen.dart';

/// Top right of Suppliers: everything waiting to be approved -- invoices
/// and statements photographed on a capture phone, and those brought in from
/// email. Nothing counts in a supplier's account until approved here.
class SuppliersInboxButton extends StatefulWidget {
  const SuppliersInboxButton({super.key, required this.data, this.captured = true});
  final SuppliersData data;

  /// Also the capture phones' (off in tests: no database).
  final bool captured;

  @override
  State<SuppliersInboxButton> createState() => _SuppliersInboxButtonState();
}

class _SuppliersInboxButtonState extends State<SuppliersInboxButton> {
  late final Stream<List<CaptureEntry>>? _pending = widget.captured ? CaptureRepository().watchPending(CaptureModule.supplierModules) : null;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CaptureEntry>>(
      stream: _pending,
      builder: (context, snap) => ListenableBuilder(
        listenable: widget.data,
        builder: (context, _) {
          final count = emailToApprove(widget.data) + (snap.data?.length ?? 0);
          return IconButton(
            tooltip: 'To approve',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SuppliersInboxScreen(data: widget.data, captured: widget.captured)),
            ),
            icon: Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              backgroundColor: NaniniColors.red,
              child: const Icon(Icons.move_to_inbox_outlined),
            ),
          );
        },
      ),
    );
  }
}

/// Documents from email still to approve, all suppliers.
int emailToApprove(SuppliersData data) => data.accounts.fold<int>(0, (n, a) => n + a.toCheck.length);

class SuppliersInboxScreen extends StatelessWidget {
  const SuppliersInboxScreen({super.key, required this.data, this.captured = true});
  final SuppliersData data;
  final bool captured;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Suppliers -- to approve'),
      body: ListenableBuilder(
        listenable: data,
        builder: (context, _) {
          final accounts = data.accounts.where((a) => a.toCheck.isNotEmpty).toList()
            ..sort((a, b) => a.supplier.name.toLowerCase().compareTo(b.supplier.name.toLowerCase()));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (captured) _phones(context),
              const SizedBox(height: 8),
              Text('From email', style: Theme.of(context).textTheme.titleLarge),
              const Text('Check each against its PDF and confirm -- only then does it count in the supplier\'s account.',
                  style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
              const SizedBox(height: 8),
              if (accounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Nothing from email to approve.', style: TextStyle(color: NaniniColors.green, fontWeight: FontWeight.w700)),
                ),
              for (final a in accounts) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(a.supplier.name, style: Theme.of(context).textTheme.titleMedium),
                ),
                ...supplierToCheckSection(context, data, a),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _phones(BuildContext context) => StreamBuilder<List<CaptureEntry>>(
        stream: CaptureRepository().watchPending(CaptureModule.supplierModules),
        builder: (context, snap) {
          final n = snap.data?.length ?? 0;
          return Card(
            child: ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: NaniniColors.rust),
              title: const Text('From capture phones', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(n == 0 ? 'Nothing photographed to approve.' : '$n photographed -- allocate the lines to GL accounts and approve.',
                  style: TextStyle(color: n == 0 ? NaniniColors.muted : NaniniColors.amber)),
              trailing: const Icon(Icons.chevron_right, color: NaniniColors.muted),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CapturedReviewScreen(title: 'Suppliers', modules: CaptureModule.supplierModules)),
              ),
            ),
          );
        },
      );
}
