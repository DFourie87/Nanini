import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import '../customers/customers_home_screen.dart';
import '../expenses/expenses_home_screen.dart';
import '../sales/sales_home_screen.dart';
import '../suppliers/suppliers_home_screen.dart';
import '../xero/xero_export_screen.dart';
import 'hub_tile.dart';

/// Hub > Financials: Sales, Customers, Suppliers and Expenses (the ones the
/// user may open; Customers reads the account sales, so it goes with Sales,
/// and Expenses the suppliers' documents, so it goes with Suppliers), and the
/// Xero export (with Sales or Suppliers).
class FinancialsScreen extends StatelessWidget {
  const FinancialsScreen({super.key});

  // Two columns, filled row by row: Sales and Customers on the left,
  // Expenses and Suppliers on the right.
  static final _apps = <(String, String, String, WidgetBuilder)>[
    ('sales', '📊', 'Sales', (_) => const SalesHomeScreen()),
    ('suppliers', '💸', 'Expenses', (_) => const ExpensesHomeScreen()),
    ('sales', '🏪', 'Customers', (_) => const CustomersHomeScreen()),
    ('suppliers', '🧾', 'Suppliers', (_) => const SuppliersHomeScreen()),
    ('sales|suppliers', '📤', 'Xero export', (_) => const XeroExportScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final apps = _apps.where((a) => a.$1.split('|').any(session.hasModule)).toList();
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      appBar: const NaniniAppBar(title: 'Financials'),
      body: apps.isEmpty
          ? const Center(child: Text('No financial apps enabled for your account.', style: TextStyle(color: NaniniColors.muted)))
          : GridView.count(
              padding: const EdgeInsets.all(20),
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              children: [
                for (final (_, emoji, name, builder) in apps)
                  HubTile(emoji: emoji, name: name, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: builder))),
              ],
            ),
    );
  }
}
