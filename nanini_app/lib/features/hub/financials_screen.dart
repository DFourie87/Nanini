import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import '../sales/sales_home_screen.dart';
import '../suppliers/suppliers_home_screen.dart';
import 'hub_tile.dart';

/// Hub > Financials: Sales and Suppliers (the ones the user may open).
class FinancialsScreen extends StatelessWidget {
  const FinancialsScreen({super.key});

  static final _apps = <(String, String, String, WidgetBuilder)>[
    ('sales', '📊', 'Sales', (_) => const SalesHomeScreen()),
    ('suppliers', '🧾', 'Suppliers', (_) => const SuppliersHomeScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final apps = _apps.where((a) => session.hasModule(a.$1)).toList();
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
