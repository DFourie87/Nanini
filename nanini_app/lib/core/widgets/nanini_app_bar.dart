import 'package:flutter/material.dart';

/// Standard module header: back button, title, optional actions. Since
/// login is now app-wide (see core/auth/), there's no per-module "Manager"
/// toggle anymore — `showManagerButton` is kept as a no-op parameter so
/// existing call sites don't all need editing, but has no effect.
class NaniniAppBar extends StatelessWidget implements PreferredSizeWidget {
  const NaniniAppBar({super.key, required this.title, this.showManagerButton = true, this.actions});

  final String title;
  final bool showManagerButton;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          'Nanini Boerdery - $title',
          maxLines: 1,
          style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(fontSize: 26, color: Colors.black, fontWeight: FontWeight.w700),
        ),
      ),
      actions: [
        ...?actions,
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
