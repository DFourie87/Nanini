import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import '../../capture_app/farm_icons.dart';
import '../hub/hub_tile.dart';
import 'sales_models.dart';
import 'sales_data.dart';
import 'sales_repository.dart';
import 'sales_summary_screen.dart';
import 'sales_reports_screen.dart';

/// Hub > Financials > Sales: first a tile per produce; tap one for its
/// Summary and its account sales (Reports). The agents' accounts are in
/// Customers.
class SalesHomeScreen extends StatefulWidget {
  const SalesHomeScreen({super.key, this.data});

  /// For tests: fixed data instead of the database.
  final SalesData? data;

  @override
  State<SalesHomeScreen> createState() => _SalesHomeScreenState();
}

/// The produce's tile picture.
const _produceEmoji = {'potatoes': '🥔', 'peppers': '🫑', 'watermelon': '🍉'};

/// Drawn instead of an emoji: the capture app's butternut (🎃 is a pumpkin),
/// a round Peppadew (🌶️ is a long chilli) and a hand of tobacco leaves.
const _produceIcon = <String, Widget>{
  'butternut': ButternutIcon(size: 46),
  'peppadew': PeppadewIcon(size: 46),
  'tobacco': TobaccoIcon(size: 46),
  // White pumpkins (🎃 is an orange jack-o'-lantern).
  'pumpkin': PumpkinIcon(size: 46),
};

class _SalesHomeScreenState extends State<SalesHomeScreen> {
  /// Loaded once when Sales opens and kept for every produce; the refresh
  /// button reloads (new market reports arrive once a day).
  late final SalesData data = widget.data ?? SalesData(SalesRepository());

  @override
  void dispose() {
    if (widget.data == null) data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      appBar: NaniniAppBar(title: 'Sales', actions: [_RefreshButton(data: data)]),
      body: Column(
        children: [
          _ErrorBanner(data: data),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(20),
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              children: [
                for (final c in kSalesCategories)
                  HubTile(
                    emoji: _produceEmoji[c.key] ?? '🧺',
                    icon: _produceIcon[c.key],
                    name: c.label,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SalesProduceScreen(data: data, category: c))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One produce: its Summary and its account sales (Reports).
class SalesProduceScreen extends StatefulWidget {
  const SalesProduceScreen({super.key, required this.data, required this.category});
  final SalesData data;
  final SalesCategory category;

  @override
  State<SalesProduceScreen> createState() => _SalesProduceScreenState();
}

class _SalesProduceScreenState extends State<SalesProduceScreen> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return Scaffold(
      appBar: NaniniAppBar(title: widget.category.label, actions: [_RefreshButton(data: data)]),
      // The tabs stay alive, so switching keeps their filters.
      body: Column(
        children: [
          _ErrorBanner(data: data),
          Expanded(
            child: IndexedStack(index: index, children: [
              SalesSummaryScreen(data: data, category: widget.category),
              SalesReportsScreen(data: data, category: widget.category.key),
            ]),
          ),
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

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.data});
  final SalesData data;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: data,
        builder: (context, _) => data.loading
            ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(
                tooltip: data.loadedAt == null ? 'Refresh' : 'Refresh (loaded ${fmtDateTimeDisplay(data.loadedAt!.toIso8601String())})',
                icon: const Icon(Icons.refresh),
                onPressed: data.refresh,
              ),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.data});
  final SalesData data;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
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
      );
}
