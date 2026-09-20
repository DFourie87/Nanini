import 'package:flutter/material.dart';
import '../../core/widgets/nanini_app_bar.dart';
import 'sales_repository.dart';
import 'sales_summary_screen.dart';
import 'sales_reports_screen.dart';

class SalesHomeScreen extends StatefulWidget {
  const SalesHomeScreen({super.key});
  @override
  State<SalesHomeScreen> createState() => _SalesHomeScreenState();
}

class _SalesHomeScreenState extends State<SalesHomeScreen> {
  final repo = SalesRepository();
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      SalesSummaryScreen(repo: repo),
      SalesReportsScreen(repo: repo),
    ];
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Sales'),
      body: pages[index],
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
