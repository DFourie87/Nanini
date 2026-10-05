import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import '../sales/sales_data.dart';
import '../sales/sales_repository.dart';
import 'customers_screen.dart';

/// Hub > Financials > Customers: the market agents and buyers -- their
/// account sales, payments and what they owe. The produce itself (per crop,
/// class and size) stays in the Sales app; both read the same account sales.
class CustomersHomeScreen extends StatefulWidget {
  const CustomersHomeScreen({super.key, this.data});

  /// For tests: fixed data instead of the database.
  final SalesData? data;

  @override
  State<CustomersHomeScreen> createState() => _CustomersHomeScreenState();
}

class _CustomersHomeScreenState extends State<CustomersHomeScreen> {
  /// Loaded once when Customers opens; the refresh button reloads.
  late final SalesData data = widget.data ?? SalesData(SalesRepository());

  @override
  void dispose() {
    if (widget.data == null) data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NaniniAppBar(
        title: 'Customers',
        actions: [
          ListenableBuilder(
            listenable: data,
            builder: (context, _) => data.loading
                ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(
                    tooltip: data.loadedAt == null ? 'Refresh' : 'Refresh (loaded ${fmtDateTimeDisplay(data.loadedAt!.toIso8601String())})',
                    icon: const Icon(Icons.refresh),
                    onPressed: data.refresh,
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: data,
            builder: (context, _) => data.error == null
                ? const SizedBox.shrink()
                : Container(
                    width: double.infinity,
                    color: NaniniColors.disabledBg,
                    padding: const EdgeInsets.all(10),
                    child: const Text('Could not load everything -- check the signal and tap refresh.',
                        style: TextStyle(color: NaniniColors.red, fontWeight: FontWeight.w600)),
                  ),
          ),
          Expanded(child: CustomersScreen(data: data)),
        ],
      ),
    );
  }
}
