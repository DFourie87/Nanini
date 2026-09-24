import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'hunting_bookings_screen.dart';
import 'hunting_certificates_screen.dart';
import 'hunting_invoices_screen.dart';
import 'hunting_models.dart';
import 'hunting_price_lists_screen.dart';
import 'hunting_repository.dart';

class HuntingHomeScreen extends StatefulWidget {
  const HuntingHomeScreen({super.key});
  @override
  State<HuntingHomeScreen> createState() => _HuntingHomeScreenState();
}

class _HuntingHomeScreenState extends State<HuntingHomeScreen> {
  final repo = HuntingRepository();
  final employeesRepo = EmployeesRepository();
  int index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkCertificateExpiry());
  }

  Future<void> _checkCertificateExpiry() async {
    final farms = await employeesRepo.fetchFarms();
    final certs = await repo.watchCertificates().first;
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

    if (warnings.isEmpty || !mounted) return;
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
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HuntingBookingsScreen(repo: repo),
      HuntingInvoicesScreen(repo: repo),
      HuntingPriceListsScreen(repo: repo),
      HuntingCertificatesScreen(repo: repo),
    ];
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Hunting'),
      body: pages[index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.event_available), label: 'Bookings'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'Invoices'),
          BottomNavigationBarItem(icon: Icon(Icons.price_change_outlined), label: 'Price Lists'),
          BottomNavigationBarItem(icon: Icon(Icons.upload_file), label: 'Certificates'),
        ],
      ),
    );
  }
}
