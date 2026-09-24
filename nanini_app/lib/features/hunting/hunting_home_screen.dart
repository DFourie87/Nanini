import 'package:flutter/material.dart';
import '../../core/widgets/nanini_app_bar.dart';
import 'hunting_bookings_screen.dart';
import 'hunting_certificate_warning.dart';
import 'hunting_certificates_screen.dart';
import 'hunting_invoices_screen.dart';
import 'hunting_price_lists_screen.dart';
import 'hunting_repository.dart';
import 'hunting_reports_screen.dart';

class HuntingHomeScreen extends StatefulWidget {
  const HuntingHomeScreen({super.key});
  @override
  State<HuntingHomeScreen> createState() => _HuntingHomeScreenState();
}

class _HuntingHomeScreenState extends State<HuntingHomeScreen> {
  final repo = HuntingRepository();
  int index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => showCertificateExpiryWarning(context));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HuntingBookingsScreen(repo: repo),
      HuntingInvoicesScreen(repo: repo),
      HuntingPriceListsScreen(repo: repo),
      HuntingCertificatesScreen(repo: repo),
      HuntingReportsScreen(repo: repo),
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
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Reports'),
        ],
      ),
    );
  }
}
