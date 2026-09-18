import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/session.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../theme/nanini_theme.dart';
import '../auth/change_pin_screen.dart';
import '../auth/manage_users_screen.dart';
import '../diesel/diesel_home_screen.dart';
import '../tuckshop/tuckshop_home_screen.dart';
import '../hours/hours_home_screen.dart';
import '../employees/employees_home_screen.dart';
import '../delivery/delivery_home_screen.dart';
import '../sales/sales_home_screen.dart';
import '../truck/truck_home_screen.dart';

class _ModuleTile {
  const _ModuleTile(this.emoji, this.name, this.builder);
  final String emoji;
  final String name;
  final WidgetBuilder builder;
}

class HubScreen extends StatelessWidget {
  const HubScreen({super.key});

  static final _tiles = <_ModuleTile>[
    _ModuleTile('⛽', 'Diesel', (_) => const DieselHomeScreen()),
    _ModuleTile('🛒', 'Tuck Shop', (_) => const TuckshopHomeScreen()),
    _ModuleTile('🕒', 'Employees', (_) => const HoursHomeScreen()),
    _ModuleTile('📦', 'Packaging', (_) => const DeliveryHomeScreen()),
    _ModuleTile('📊', 'Sales', (_) => const SalesHomeScreen()),
    _ModuleTile('🧑‍🌾', 'Employee List', (_) => const EmployeesHomeScreen()),
    _ModuleTile('🚚', 'Truck', (_) => const TruckHomeScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.currentUser;
    return Scaffold(
      body: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
            border: Border.fromBorderSide(BorderSide(color: Colors.black, width: 3)),
          ),
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              border: Border.fromBorderSide(BorderSide(color: NaniniColors.rust, width: 2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Row(
                    children: [
                      Container(
                        height: 52,
                        width: 52,
                        decoration: BoxDecoration(
                          border: Border.all(color: NaniniColors.line),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.asset('assets/images/hub-logo.jpg', fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Nanini Boerdery',
                            maxLines: 1,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: NaniniColors.rust),
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const CircleAvatar(
                          backgroundColor: NaniniColors.disabledBg,
                          child: Icon(Icons.person, color: NaniniColors.rustDark),
                        ),
                        onSelected: (v) async {
                          if (v == 'manage_users') {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageUsersScreen()));
                          } else if (v == 'change_pin') {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePinScreen()));
                          } else if (v == 'logout') {
                            final ok = await confirmDialog(context, message: 'Log out of Nanini Boerdery?');
                            if (ok) await session.logout();
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(enabled: false, child: Text(user?.displayName ?? '', style: const TextStyle(fontWeight: FontWeight.w700))),
                          const PopupMenuItem(value: 'change_pin', child: Text('Change PIN')),
                          if (session.isAdmin) const PopupMenuItem(value: 'manage_users', child: Text('Manage users')),
                          const PopupMenuItem(value: 'logout', child: Text('Log out')),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const crossAxisCount = 2;
                      const spacing = 14.0;
                      const gridPadding = 20.0;
                      final rows = (_tiles.length / crossAxisCount).ceil();
                      final availableWidth = constraints.maxWidth - gridPadding * 2;
                      final availableHeight = constraints.maxHeight - gridPadding * 2;
                      final tileWidth = (availableWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
                      final tileHeight = (availableHeight - spacing * (rows - 1)) / rows;

                      return GridView.count(
                        padding: const EdgeInsets.all(gridPadding),
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: spacing,
                        crossAxisSpacing: spacing,
                        childAspectRatio: tileWidth / tileHeight,
                        children: _tiles
                            .map((t) => _Tile(
                                  emoji: t.emoji,
                                  name: t.name,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: t.builder),
                                  ),
                                ))
                            .toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.emoji, required this.name, required this.onTap});
  final String emoji;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NaniniColors.paper,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: NaniniColors.line),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4)),
            ],
          ),
          padding: const EdgeInsets.all(8),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 42)),
                const SizedBox(height: 10),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
