import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import '../../core/run_once.dart';

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

/// The period: one small button showing its dates (the tax year to date
/// by default); tapping it picks any dates from -- to.
class PeriodBar extends StatelessWidget {
  const PeriodBar({super.key, required this.period, required this.onChanged});
  final SupplierPeriod period;
  final ValueChanged<SupplierPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        icon: const Icon(Icons.date_range, size: 18),
        label: Text(period.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: NaniniColors.rustDark)),
        onPressed: () => runOnce('suppliers_period.1', () async {
          final r = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            initialDateRange: DateTimeRange(start: parseDateStr(period.from)!, end: parseDateStr(period.to)!),
          );
          if (r != null) onChanged(SupplierPeriod(toDateStr(r.start), toDateStr(r.end)));
        }),
      ),
    );
  }
}
