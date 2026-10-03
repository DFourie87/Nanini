import 'package:flutter/material.dart';

import '../../core/widgets/nanini_app_bar.dart';
import '../capture/capture_models.dart';
import '../capture/captured_review_screen.dart';
import 'suppliers_data.dart';
import 'suppliers_due_screen.dart';
import 'suppliers_electricity_screen.dart';
import 'suppliers_overview_screen.dart';
import 'suppliers_period.dart';
import 'suppliers_purchases_screen.dart';
import 'suppliers_repository.dart';
import 'suppliers_supplier_screen.dart';

/// Hub > Suppliers: Due (the total, and who to pay when and how much),
/// Suppliers (each one; tap for its account and details), Purchases (per
/// contra account, for a period) and Electricity (Eskom). Documents
/// photographed on a capture phone wait in the inbox for an admin to check
/// and allocate.
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
  SupplierPeriod period = SupplierPeriod.taxYearToDate(DateTime.now());

  @override
  void dispose() {
    if (widget.data == null) data.dispose();
    super.dispose();
  }

  void _open(String id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierScreen(data: data, supplierId: id)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NaniniAppBar(
        title: 'Suppliers',
        actions: [if (widget.data == null) const CapturedInboxButton(title: 'Suppliers', modules: CaptureModule.supplierModules)],
      ),
      body: ListenableBuilder(
        listenable: data,
        builder: (context, _) => switch (tab) {
          0 => SuppliersDueScreen(data: data, onOpen: _open),
          1 => SuppliersOverviewScreen(data: data, onOpen: _open),
          2 => SuppliersPurchasesScreen(data: data, period: period, onPeriod: (p) => setState(() => period = p)),
          _ => SuppliersElectricityScreen(data: data, period: period, onPeriod: (p) => setState(() => period = p)),
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tab,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.event_note_outlined), label: 'Due'),
          BottomNavigationBarItem(icon: Icon(Icons.store_mall_directory_outlined), label: 'Suppliers'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined), label: 'Purchases'),
          BottomNavigationBarItem(icon: Icon(Icons.bolt_outlined), label: 'Electricity'),
        ],
      ),
    );
  }
}
