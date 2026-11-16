import 'package:flutter/material.dart';

/// Two taps on the same day within this time: that day is chosen at once.
const kDoubleTapDay = Duration(milliseconds: 600);

/// A date picker like [showDatePicker] (a calendar, Cancel and OK), where a
/// double-click (or double-tap) on a day chooses it straight away.
Future<DateTime?> pickDate(BuildContext context, {required DateTime initialDate, required DateTime firstDate, required DateTime lastDate, String? helpText}) {
  var selected = initialDate;
  DateTime? lastDay;
  DateTime? lastTap;
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(helpText ?? 'Select date'),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: SizedBox(
          width: 340,
          height: 360,
          child: CalendarDatePicker(
            initialDate: initialDate,
            firstDate: firstDate,
            lastDate: lastDate,
            onDateChanged: (d) {
              final now = DateTime.now();
              if (lastDay == d && lastTap != null && now.difference(lastTap!) <= kDoubleTapDay) {
                Navigator.pop(ctx, d);
                return;
              }
              lastDay = d;
              lastTap = now;
              setLocal(() => selected = d);
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(key: const Key('pick_date_ok'), onPressed: () => Navigator.pop(ctx, selected), child: const Text('OK')),
        ],
      ),
    ),
  );
}
