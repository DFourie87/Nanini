import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';

/// "Farm Haaskraal - Swartwater" -> "Haaskraal".
String farmShort(Farm? f) {
  if (f == null) return 'No farm';
  var n = f.name.replaceFirst(RegExp(r'^Farm\s+'), '');
  final dash = n.indexOf(' - ');
  if (dash > 0) n = n.substring(0, dash);
  return n.trim().isEmpty ? f.name : n.trim();
}

/// Top of the Work and Summary tabs: which farm, and pay up to which day.
class PayScopeBar extends StatelessWidget {
  const PayScopeBar({
    super.key,
    required this.farms,
    required this.farmId,
    required this.payUpTo,
    required this.onFarm,
    required this.onPayUpTo,
  });
  final List<Farm> farms;
  final String? farmId;
  final DateTime payUpTo;
  final ValueChanged<String?> onFarm;
  final ValueChanged<DateTime> onPayUpTo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (farms.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: [
                  const ButtonSegment(value: '', label: Text('All farms')),
                  for (final f in farms) ButtonSegment(value: f.id, label: Text(farmShort(f))),
                ],
                selected: {farmId ?? ''},
                onSelectionChanged: (s) => onFarm(s.first.isEmpty ? null : s.first),
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: NaniniColors.rust,
                  selectedForegroundColor: Colors.white,
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(context: context, initialDate: payUpTo, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (picked != null) onPayUpTo(picked);
            },
            icon: const Icon(Icons.event),
            label: Text('Since last pay, up to ${fmtDateDisplay(toDateStr(payUpTo))}'),
          ),
        ],
      ),
    );
  }
}

/// A farm's block: name and totals on top, one row per worker below.
class FarmSection extends StatelessWidget {
  const FarmSection({super.key, required this.title, required this.totals, required this.children});
  final String title;
  final String totals;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: NaniniColors.disabledBg,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                Text(totals, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class EmptyPayNote extends StatelessWidget {
  const EmptyPayNote({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(32),
        child: Text('No hours, picking or tuck shop debt since the last pay.', textAlign: TextAlign.center, style: TextStyle(color: NaniniColors.muted)),
      );
}

/// A label/amount line (e.g. "Tuck shop  -R 230").
class AmountRow extends StatelessWidget {
  const AmountRow(this.label, this.value, {super.key, this.bold = false, this.color});
  final String label;
  final double value;
  final bool bold;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [Expanded(child: Text(label, style: style)), Text(fmtR(value), style: style)],
      ),
    );
  }
}
