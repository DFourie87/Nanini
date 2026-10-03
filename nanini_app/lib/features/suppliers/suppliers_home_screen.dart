import 'package:flutter/material.dart';

import '../../core/widgets/nanini_app_bar.dart';
import 'suppliers_account_screen.dart';
import 'suppliers_data.dart';
import 'suppliers_electricity_screen.dart';
import 'suppliers_overview_screen.dart';
import 'suppliers_period.dart';
import 'suppliers_purchases_screen.dart';
import 'suppliers_recon_screen.dart';
import 'suppliers_repository.dart';

/// Hub > Suppliers: Overview (who we owe what), Recon (the work page --
/// invoices, credit notes and statements as PDFs, payments typed in, and
/// each statement checked), Account (a supplier's GL account for a period)
/// and Purchases (per contra account, for a period).
class SuppliersHomeScreen extends StatefulWidget {
  const SuppliersHomeScreen({super.key, this.data});

  /// For tests: fixed data instead of the database.
  final SuppliersData? data;

  @override
  State<SuppliersHomeScreen> createState() => _SuppliersHomeScreenState();
}

class _SuppliersHomeScreenState extends State<SuppliersHomeScreen> {
  late final SuppliersData data = widget.data ?? SuppliersData(SuppliersRepository());
  int tab = 0;
  String? supplierId;
  SupplierPeriod period = SupplierPeriod.taxYearToDate(DateTime.now());

  @override
  void dispose() {
    if (widget.data == null) data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Suppliers'),
      body: ListenableBuilder(
        listenable: data,
        builder: (context, _) => switch (tab) {
          0 => SuppliersOverviewScreen(
              data: data,
              onOpen: (id) => setState(() {
                supplierId = id;
                tab = 1;
              }),
            ),
          1 => SuppliersReconScreen(data: data, supplierId: supplierId, onSupplier: (id) => setState(() => supplierId = id)),
          2 => SuppliersAccountScreen(
              data: data,
              supplierId: supplierId,
              onSupplier: (id) => setState(() => supplierId = id),
              period: period,
              onPeriod: (p) => setState(() => period = p),
            ),
          3 => SuppliersPurchasesScreen(data: data, period: period, onPeriod: (p) => setState(() => period = p)),
          _ => SuppliersElectricityScreen(data: data, period: period, onPeriod: (p) => setState(() => period = p)),
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tab,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Overview'),
          BottomNavigationBarItem(icon: Icon(Icons.fact_check_outlined), label: 'Recon'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book_outlined), label: 'Account'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined), label: 'Purchases'),
          BottomNavigationBarItem(icon: Icon(Icons.bolt_outlined), label: 'Electricity'),
        ],
      ),
    );
  }
}
