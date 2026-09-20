import 'package:flutter/material.dart';
import '../../core/widgets/nanini_app_bar.dart';
import 'delivery_repository.dart';
import 'delivery_log_screen.dart';
import 'delivery_records_screen.dart';
import 'delivery_pallets_screen.dart';

class DeliveryHomeScreen extends StatefulWidget {
  const DeliveryHomeScreen({super.key});
  @override
  State<DeliveryHomeScreen> createState() => _DeliveryHomeScreenState();
}

class _DeliveryHomeScreenState extends State<DeliveryHomeScreen> {
  final repo = DeliveryRepository();
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DeliveryLogScreen(repo: repo),
      DeliveryRecordsScreen(repo: repo),
      DeliveryPalletsScreen(repo: repo),
    ];
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Packaging'),
      body: pages[index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.local_shipping_outlined), label: 'Log'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'Records'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_outlined), label: 'Pallets'),
        ],
      ),
    );
  }
}
