import 'package:intl/intl.dart';

final _rFormat = NumberFormat('#,##0', 'en_US');
final _lFormat = NumberFormat('#,##0.0', 'en_US');
final _lWholeFormat = NumberFormat('#,##0', 'en_US');
final _dateFormat = DateFormat('yyyy-MM-dd');
final _dateDisplayFormat = DateFormat('d MMM yyyy');
final _dateTimeDisplayFormat = DateFormat('d MMM yyyy, HH:mm');

/// South African Rand formatting -- whole rands only, space-grouped
/// thousands (e.g. "R 12 345"), no cents and no comma separator.
String fmtR(num? n) {
  final v = n ?? 0;
  final sign = v < 0 ? '-' : '';
  final formatted = _rFormat.format(v.abs()).replaceAll(',', ' ');
  return 'R $sign$formatted'.replaceFirst('R -', '-R ');
}

/// Litres formatting, matching the web app's `fmtL()`.
String fmtL(num? n) => '${_lFormat.format(n ?? 0)} L';

/// Litres formatting with no decimal place, for tank level readouts.
String fmtLWhole(num? n) => '${_lWholeFormat.format(n ?? 0)} L';

String fmtHours(num? h) {
  final v = h ?? 0;
  if (v == v.roundToDouble()) return '${v.round()}h';
  return '${v}h';
}

/// Groups a hour-meter/odometer reading with spaces every 3 digits, e.g.
/// "215624" -> "215 624", "1410.5" -> "1 410.5". Falls back to the raw
/// string unchanged if it isn't a parseable number.
String fmtReading(String? raw) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return s;
  final n = double.tryParse(s);
  if (n == null) return s;
  final numStr = n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  final parts = numStr.split('.');
  final intPart = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(intPart[i]);
  }
  return parts.length > 1 ? '${buffer.toString()}.${parts[1]}' : buffer.toString();
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
