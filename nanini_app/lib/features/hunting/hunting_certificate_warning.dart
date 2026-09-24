import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import 'hunting_models.dart';
import 'hunting_repository.dart';

/// Warns about any farm whose current P3 exemption certificate expires
/// within 3 months (or already has) -- shown each time the Hunting module
/// is opened.
Future<void> showCertificateExpiryWarning(BuildContext context) async {
  try {
    final farms = await fetchHuntingFarms();
    final certs = await HuntingRepository().watchCertificates().first;
    final today = DateTime.now();

    // Latest (by expiry) certificate per farm -- that's the currently active one.
    final latestByFarm = <String, HuntingExemptionCertificate>{};
    for (final c in certs) {
      final existing = latestByFarm[c.farmId];
      if (existing == null || c.expiryDate.compareTo(existing.expiryDate) > 0) latestByFarm[c.farmId] = c;
    }

    final warnings = <(Farm, HuntingExemptionCertificate, int)>[];
    for (final farm in farms) {
      final cert = latestByFarm[farm.id];
      if (cert == null) continue;
      final expiry = parseDateStr(cert.expiryDate);
      if (expiry == null) continue;
      final daysLeft = expiry.difference(today).inDays;
      if (daysLeft <= 90) warnings.add((farm, cert, daysLeft));
    }

    if (warnings.isEmpty || !context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exemption certificate expiry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (farm, cert, daysLeft) in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(farm.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      daysLeft < 0
                          ? 'P3 exemption certificate expired ${-daysLeft} day${daysLeft == -1 ? '' : 's'} ago (${fmtDateDisplay(cert.expiryDate)})'
                          : 'P3 exemption certificate expires in $daysLeft day${daysLeft == 1 ? '' : 's'} (${fmtDateDisplay(cert.expiryDate)})',
                      style: const TextStyle(color: NaniniColors.red),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  } catch (e) {
    debugPrint('Certificate expiry check failed: $e');
  }
}
