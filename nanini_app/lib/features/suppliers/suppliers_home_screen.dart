import 'package:flutter/material.dart';

import '../../core/widgets/nanini_app_bar.dart';
import 'suppliers_data.dart';
import 'suppliers_due_screen.dart';
import 'suppliers_inbox_screen.dart';
import 'suppliers_overview_screen.dart';
import 'suppliers_repository.dart';
import 'suppliers_supplier_screen.dart';

/// Hub > Suppliers: Due (the total, and who to pay when and how much) and
/// Suppliers (each one; tap for its account and details). What was bought,
/// per contra account, is in the Expenses app. Documents
/// photographed on a capture phone or brought in from email wait in the
/// inbox (top right) for an admin to check, allocate and approve.
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
        actions: [SuppliersInboxButton(data: data, captured: widget.data == null)],
      ),
      body: ListenableBuilder(
        listenable: data,
        builder: (context, _) => switch (tab) {
          0 => SuppliersDueScreen(data: data, onOpen: _open),
          _ => SuppliersOverviewScreen(data: data, onOpen: _open),
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tab,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.event_note_outlined), label: 'Due'),
          BottomNavigationBarItem(icon: Icon(Icons.store_mall_directory_outlined), label: 'List'),
        ],
      ),
    );
  }
}
