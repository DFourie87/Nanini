import 'package:intl/intl.dart';

final _rFormat = NumberFormat('#,##0', 'en_US');
final _rCentsFormat = NumberFormat('#,##0.00', 'en_US');
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

/// South African Rand formatting with cents, unrounded -- for small
/// per-litre amounts (e.g. the diesel price forecast) where whole-rand
/// fmtR() would round a real change like R0.45 down to "R 0".
String fmtRCents(num? n) {
  final v = n ?? 0;
  final sign = v < 0 ? '-' : '';
  final formatted = _rCentsFormat.format(v.abs()).replaceAll(',', ' ');
  return 'R $sign$formatted'.replaceFirst('R -', '-R ');
}

/// Rands with the R right against the number (Employees app): "R2 000",
/// "-R150". Whole rands.
String fmtRand(num? n) {
  final v = n ?? 0;
  final formatted = _rFormat.format(v.abs()).replaceAll(',', ' ');
  return '${v < 0 ? '-' : ''}R$formatted';
}

/// [fmtRand] with cents: "R30.00".
String fmtRandCents(num? n) {
  final v = n ?? 0;
  final formatted = _rCentsFormat.format(v.abs()).replaceAll(',', ' ');
  return '${v < 0 ? '-' : ''}R$formatted';
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

/// Parses a typed number. Accepts a decimal comma ("12,5" -- many phones set
/// to South African English type that), spaces and a leading "R".
double? parseNum(String? s) {
  if (s == null) return null;
  var t = s.trim().replaceAll(RegExp(r'[\sR]'), '');
  // "1,250.50": the comma is a thousands separator; otherwise it's the decimal.
  t = t.contains('.') ? t.replaceAll(',', '') : t.replaceAll(',', '.');
  return double.tryParse(t);
}

/// Whole-number percentages of [values] that always add up to exactly 100.
/// Rounding each share on its own can total 99% or 101% (three equal parts
/// show 33 + 33 + 33); here the leftover points go to the shares that were
/// rounded down the most.
List<int> wholePercents(List<double> values) {
  final total = values.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return List.filled(values.length, 0);
  final raw = [for (final v in values) v / total * 100];
  final out = [for (final r in raw) r.floor()];
  var left = 100 - out.fold<int>(0, (a, b) => a + b);
  final order = List.generate(values.length, (i) => i)..sort((a, b) => (raw[b] - out[b]).compareTo(raw[a] - out[a]));
  for (var k = 0; left > 0 && order.isNotEmpty; k = (k + 1) % order.length, left--) {
    out[order[k]]++;
  }
  return out;
}
