import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import 'sales_data.dart';
import 'sales_repository.dart';
import 'sales_summary_screen.dart';
import 'sales_reports_screen.dart';

class SalesHomeScreen extends StatefulWidget {
  const SalesHomeScreen({super.key});
  @override
  State<SalesHomeScreen> createState() => _SalesHomeScreenState();
}

class _SalesHomeScreenState extends State<SalesHomeScreen> {
  /// Loaded once when Sales opens and kept across both tabs; the refresh
  /// button reloads (new market reports arrive once a day).
  late final data = SalesData(SalesRepository());
  int index = 0;

  @override
  void dispose() {
    data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      SalesSummaryScreen(data: data),
      SalesReportsScreen(data: data),
    ];
    return Scaffold(
      appBar: NaniniAppBar(
        title: 'Sales',
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
      // Both tabs stay alive, so switching keeps their filters and data.
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
          Expanded(child: IndexedStack(index: index, children: pages)),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart_outline), label: 'Summary'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt_outlined), label: 'Reports'),
        ],
      ),
    );
  }
}
