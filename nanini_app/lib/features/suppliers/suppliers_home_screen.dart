import 'package:flutter/material.dart';

import '../../core/widgets/nanini_app_bar.dart';
import 'suppliers_data.dart';
import 'suppliers_overview_screen.dart';
import 'suppliers_recon_screen.dart';
import 'suppliers_repository.dart';

/// Hub > Suppliers: Overview (who we owe what) and Recon (the work page --
/// invoices, credit notes and statements as PDFs, payments typed in, and
/// each statement checked against our account).
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
        builder: (context, _) => tab == 0
            ? SuppliersOverviewScreen(
                data: data,
                onOpen: (id) => setState(() {
                  supplierId = id;
                  tab = 1;
                }),
              )
            : SuppliersReconScreen(data: data, supplierId: supplierId, onSupplier: (id) => setState(() => supplierId = id)),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tab,
        onTap: (i) => setState(() => tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Overview'),
          BottomNavigationBarItem(icon: Icon(Icons.fact_check_outlined), label: 'Recon'),
        ],
      ),
    );
  }
}
