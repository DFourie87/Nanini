import 'package:flutter/material.dart';

import '../../core/widgets/nanini_app_bar.dart';
import '../suppliers/suppliers_data.dart';
import '../suppliers/suppliers_period.dart';
import '../suppliers/suppliers_repository.dart';
import 'expenses_accounts_screen.dart';
import 'expenses_electricity_screen.dart';
import 'expenses_purchases_screen.dart';

/// Hub > Financials > Expenses: what the farm spends, per contra account.
/// Expenses (each account's total, tap for its detail), Purchases (every
/// line, against its account) and Electricity (Eskom, bill by bill). The
/// suppliers' own data -- accounts, statements, what's due -- stays in the
/// Suppliers app; both read the same documents.
class ExpensesHomeScreen extends StatefulWidget {
  const ExpensesHomeScreen({super.key, this.data});

  /// For tests: fixed data instead of the database.
  final SuppliersData? data;

  @override
  State<ExpensesHomeScreen> createState() => _ExpensesHomeScreenState();
}

class _ExpensesHomeScreenState extends State<ExpensesHomeScreen> {
  late final SuppliersData data = widget.data ?? SuppliersData(SuppliersRepository());
  int tab = 0;
  SupplierPeriod period = SupplierPeriod.taxYearToDate(DateTime.now());

  @override
  void dispose() {
    if (widget.data == null) data.dispose();
    super.dispose();
  }

  void _setPeriod(SupplierPeriod p) => setState(() => period = p);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Expenses'),
      body: ListenableBuilder(
        listenable: data,
        builder: (context, _) => switch (tab) {
          0 => ExpensesAccountsScreen(data: data, period: period, onPeriod: _setPeriod),
          1 => ExpensesPurchasesScreen(data: data, period: period, onPeriod: _setPeriod),
          _ => ExpensesElectricityScreen(data: data, period: period, onPeriod: _setPeriod),
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tab,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart_outline), label: 'Expenses'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined), label: 'Purchases'),
          BottomNavigationBarItem(icon: Icon(Icons.bolt_outlined), label: 'Electricity'),
        ],
      ),
    );
  }
}
