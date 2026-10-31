import 'package:flutter/material.dart';
import '../capture/capture_models.dart';
import '../capture/captured_review_screen.dart';
import '../../core/widgets/nanini_app_bar.dart';
import 'delivery_repository.dart';
import 'delivery_bags_screen.dart';
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
    // Trucks come from the phones (Packaging), approved in the inbox above:
    // no Log tab for typing them in here.
    final pages = [
      DeliveryRecordsScreen(repo: repo),
      DeliveryBagsScreen(repo: repo),
      DeliveryPalletsScreen(repo: repo),
    ];
    return Scaffold(
      appBar: NaniniAppBar(
        title: 'Packaging',
        actions: const [CapturedInboxButton(title: 'Packaging', modules: CaptureModule.deliveryModules)],
      ),
      body: pages[index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'Delivery Notes'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: 'Bags/Boxes'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_outlined), label: 'Pallets'),
        ],
      ),
    );
  }
}
