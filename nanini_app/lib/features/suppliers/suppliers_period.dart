import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';

/// A period of the supplier reports (yyyy-MM-dd, both days included).
class SupplierPeriod {
  const SupplierPeriod(this.from, this.to);
  final String from;
  final String to;

  /// The tax year (March to February) [today] is in, up to today.
  factory SupplierPeriod.taxYearToDate(DateTime today) {
    final start = DateTime(today.month >= 3 ? today.year : today.year - 1, 3, 1);
    return SupplierPeriod(toDateStr(start), toDateStr(today));
  }

  factory SupplierPeriod.month(DateTime anyDay) =>
      SupplierPeriod(toDateStr(DateTime(anyDay.year, anyDay.month, 1)), toDateStr(DateTime(anyDay.year, anyDay.month + 1, 0)));

  String get label => '${fmtDateDisplay(from)} – ${fmtDateDisplay(to)}';
}

/// The period, with quick choices and any dates.
class PeriodBar extends StatelessWidget {
  const PeriodBar({super.key, required this.period, required this.onChanged});
  final SupplierPeriod period;
  final ValueChanged<SupplierPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final lastTaxYearEnd = DateTime(now.month >= 3 ? now.year : now.year - 1, 3, 0);
    final choices = <String, SupplierPeriod>{
      'This month': SupplierPeriod(SupplierPeriod.month(now).from, toDateStr(now)),
      'Last month': SupplierPeriod.month(DateTime(now.year, now.month - 1, 1)),
      'Tax year': SupplierPeriod.taxYearToDate(now),
      'Last tax year': SupplierPeriod.taxYearToDate(lastTaxYearEnd).let((p) => SupplierPeriod(p.from, toDateStr(lastTaxYearEnd))),
    };
    // Small: compact chips, all in view.
    const small = TextStyle(fontSize: 12);
    const dense = VisualDensity(horizontal: -4, vertical: -4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final e in choices.entries)
              ChoiceChip(
                label: Text(e.key, style: small),
                visualDensity: dense,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                showCheckmark: false,
                padding: EdgeInsets.zero,
                selected: e.value.from == period.from && e.value.to == period.to,
                onSelected: (_) => onChanged(e.value),
              ),
            ActionChip(
              avatar: const Icon(Icons.date_range, size: 14),
              visualDensity: dense,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
              label: const Text('Dates', style: small),
              onPressed: () async {
                final r = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  initialDateRange: DateTimeRange(start: parseDateStr(period.from)!, end: parseDateStr(period.to)!),
                );
                if (r != null) onChanged(SupplierPeriod(toDateStr(r.start), toDateStr(r.end)));
              },
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(period.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: NaniniColors.rustDark)),
      ],
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
