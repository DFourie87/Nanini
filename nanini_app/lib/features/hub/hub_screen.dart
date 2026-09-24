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
import '../game_breeding/game_breeding_home_screen.dart';
import '../hunting/hunting_home_screen.dart';
import 'rifle_icon.dart';

class _ModuleTile {
  const _ModuleTile(this.key, this.emoji, this.name, this.builder, {this.icon});
  final String key;
  final String emoji;
  final String name;
  final WidgetBuilder builder;

  /// Drawn icon shown instead of [emoji], for apps with no fitting emoji.
  final Widget? icon;
}

class HubScreen extends StatelessWidget {
  const HubScreen({super.key});

  static final _tiles = <_ModuleTile>[
    _ModuleTile('diesel', '⛽', 'Diesel', (_) => const DieselHomeScreen()),
    _ModuleTile('tuckshop', '🛒', 'Tuck Shop', (_) => const TuckshopHomeScreen()),
    _ModuleTile('hours', '🕒', 'Employees', (_) => const HoursHomeScreen()),
    _ModuleTile('packaging', '📦', 'Packaging', (_) => const DeliveryHomeScreen()),
    _ModuleTile('sales', '📊', 'Sales', (_) => const SalesHomeScreen()),
    _ModuleTile('employees_list', '🧑‍🌾', 'Employee List', (_) => const EmployeesHomeScreen()),
    _ModuleTile('truck', '🚚', 'Truck', (_) => const TruckHomeScreen()),
    _ModuleTile('buffalo', '🐃', 'Buffalo', (_) => const GameSpeciesHomeScreen(species: 'Buffalo')),
    _ModuleTile('hunting', '', 'Hunting', (_) => const HuntingHomeScreen(), icon: const RifleIcon()),
  ];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.currentUser;
    final tiles = _tiles.where((t) => session.hasModule(t.key)).toList();
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 12, 0),
                child: PopupMenuButton<String>(
                  icon: const CircleAvatar(
                    backgroundColor: NaniniColors.disabledBg,
                    child: Icon(Icons.person, color: NaniniColors.ink),
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: SizedBox(
                height: 140,
                width: 140,
                child: Image.asset('assets/images/hub-logo.jpg', fit: BoxFit.contain),
              ),
            ),
            Expanded(
              child: tiles.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No apps have been enabled for your account yet — ask an admin to give you access.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: NaniniColors.muted),
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        const crossAxisCount = 2;
                        const spacing = 14.0;
                        const gridPadding = 20.0;
                        final rows = (tiles.length / crossAxisCount).ceil();
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
                          children: tiles
                              .map((t) => _Tile(
                                    emoji: t.emoji,
                                    icon: t.icon,
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
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.emoji, this.icon, required this.name, required this.onTap});
  final String emoji;
  final Widget? icon;
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
                icon ?? Text(emoji, style: const TextStyle(fontSize: 42)),
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
