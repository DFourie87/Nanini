import 'package:intl/intl.dart';

final _rFormat = NumberFormat('#,##0.00', 'en_US');
final _lFormat = NumberFormat('#,##0.0', 'en_US');
final _dateFormat = DateFormat('yyyy-MM-dd');
final _dateDisplayFormat = DateFormat('d MMM yyyy');
final _dateTimeDisplayFormat = DateFormat('d MMM yyyy, HH:mm');

/// South African Rand formatting, matching the web app's `fmtR()`.
String fmtR(num? n) {
  final v = n ?? 0;
  final sign = v < 0 ? '-' : '';
  return 'R $sign${_rFormat.format(v.abs())}'.replaceFirst('R -', '-R ');
}

/// Litres formatting, matching the web app's `fmtL()`.
String fmtL(num? n) => '${_lFormat.format(n ?? 0)} L';

String fmtHours(num? h) {
  final v = h ?? 0;
  if (v == v.roundToDouble()) return '${v.round()}h';
  return '${v}h';
}

String todayStr() => _dateFormat.format(DateTime.now());

String toDateStr(DateTime d) => _dateFormat.format(d);

DateTime? parseDateStr(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    return DateTime.parse(s);
  } catch (_) {
    return null;
  }
}

String fmtDateDisplay(String? isoDate) {
  final d = parseDateStr(isoDate);
  if (d == null) return '-';
  return _dateDisplayFormat.format(d);
}

String fmtDateTimeDisplay(String? isoDateTime) {
  if (isoDateTime == null || isoDateTime.isEmpty) return '-';
  try {
    final d = DateTime.parse(isoDateTime).toLocal();
    return _dateTimeDisplayFormat.format(d);
  } catch (_) {
    return isoDateTime;
  }
}
