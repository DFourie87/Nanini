import 'package:flutter/material.dart';
import '../../core/widgets/nanini_app_bar.dart';
import 'hunting_invoices_screen.dart';
import 'hunting_price_lists_screen.dart';
import 'hunting_repository.dart';

class HuntingHomeScreen extends StatefulWidget {
  const HuntingHomeScreen({super.key});
  @override
  State<HuntingHomeScreen> createState() => _HuntingHomeScreenState();
}

class _HuntingHomeScreenState extends State<HuntingHomeScreen> {
  final repo = HuntingRepository();
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HuntingInvoicesScreen(repo: repo),
      HuntingPriceListsScreen(repo: repo),
    ];
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Hunting'),
      body: pages[index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'Invoices'),
          BottomNavigationBarItem(icon: Icon(Icons.price_change_outlined), label: 'Price Lists'),
        ],
      ),
    );
  }
}
