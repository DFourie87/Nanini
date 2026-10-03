import 'package:flutter/material.dart';

import '../../theme/nanini_theme.dart';

/// An app tile on the hub (and on a group of apps, like Financials).
class HubTile extends StatelessWidget {
  const HubTile({super.key, required this.emoji, this.icon, required this.name, required this.onTap});
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
