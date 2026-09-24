import 'package:flutter/material.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import 'hunting_models.dart';
import 'hunting_repository.dart';

/// Each farm's current P3 government exemption certificate. Its permit
/// number fills in the permission-to-hunt letter, and its expiry drives the
/// warning shown on opening the Hunting app. Renewing replaces the old
/// certificate -- only the current one is kept.
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
    return StreamBuilder<List<HuntingExemptionCertificate>>(
      stream: widget.repo.watchCertificates(),
      builder: (context, snap) {
        final certs = snap.data ?? [];
        if (farms.isEmpty) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final farm in farms) ...[
              _certificateCard(context, farm, _currentFor(certs, farm.id)),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  /// Latest-expiring certificate for the farm (older rows may still exist
  /// from before renewals replaced them).
  HuntingExemptionCertificate? _currentFor(List<HuntingExemptionCertificate> certs, String farmId) {
    final forFarm = certs.where((c) => c.farmId == farmId).toList()..sort((a, b) => b.expiryDate.compareTo(a.expiryDate));
    return forFarm.isEmpty ? null : forFarm.first;
  }

  Widget _certificateCard(BuildContext context, Farm farm, HuntingExemptionCertificate? cert) {
    final expiry = cert == null ? null : parseDateStr(cert.expiryDate);
    final daysLeft = expiry?.difference(DateTime.now()).inDays;
    final Color statusColor = daysLeft == null
        ? NaniniColors.muted
        : daysLeft < 0
            ? NaniniColors.red
            : daysLeft <= 90
                ? NaniniColors.amber
                : NaniniColors.green;
    final status = daysLeft == null
        ? ''
        : daysLeft < 0
            ? 'EXPIRED ${-daysLeft} day${daysLeft == -1 ? '' : 's'} ago'
            : daysLeft <= 90
                ? 'Expires in $daysLeft day${daysLeft == 1 ? '' : 's'} -- renew soon'
                : 'Valid -- $daysLeft days left';

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(width: 130, child: Text(label, style: const TextStyle(color: NaniniColors.muted))),
              Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(farm.name, style: Theme.of(context).textTheme.titleMedium)),
                TextButton(
                  onPressed: () async {
                    if (!await requireAdmin(context)) return;
                    if (!context.mounted) return;
                    await _showCertificateDialog(context, farm, cert);
                  },
                  child: Text(cert == null ? 'Add' : 'Renew / edit'),
                ),
              ],
            ),
            const Text('P3 exemption certificate (exemption on enclosed land)', style: TextStyle(color: NaniniColors.muted)),
            const SizedBox(height: 8),
            if (cert == null)
              const Text('Not recorded yet.', style: TextStyle(color: NaniniColors.muted))
            else ...[
              row('Permit number', (cert.permitNumber ?? '').isEmpty ? '-' : cert.permitNumber!),
              row('Issue date', (cert.issueDate ?? '').isEmpty ? '-' : fmtDateDisplay(cert.issueDate)),
              row('Expiry date', fmtDateDisplay(cert.expiryDate)),
              const SizedBox(height: 6),
              Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showCertificateDialog(BuildContext context, Farm farm, HuntingExemptionCertificate? existing) async {
    final permitCtrl = TextEditingController(text: existing?.permitNumber);
    var issueDate = existing?.issueDate ?? todayStr();
    var expiryDate = existing?.expiryDate ?? todayStr();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'P3 certificate -- ${farm.name}' : 'Renew P3 certificate -- ${farm.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (existing != null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Saving replaces the current certificate.', style: TextStyle(color: NaniniColors.muted)),
                  ),
                TextField(controller: permitCtrl, decoration: const InputDecoration(labelText: 'Exemption permit number *')),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Issue date: ${fmtDateDisplay(issueDate)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final d = await showDatePicker(context: ctx, initialDate: parseDateStr(issueDate) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (d != null) setLocal(() => issueDate = toDateStr(d));
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Expiry date: ${fmtDateDisplay(expiryDate)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final d = await showDatePicker(context: ctx, initialDate: parseDateStr(expiryDate) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
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
                final permit = permitCtrl.text.trim();
                if (permit.isEmpty) {
                  showToast(ctx, 'Enter the exemption permit number', isError: true);
                  return;
                }
                try {
                  await widget.repo.saveCertificate(farmId: farm.id, permitNumber: permit, issueDate: issueDate, expiryDate: expiryDate);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) showToast(ctx, 'Could not save: $e', isError: true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
