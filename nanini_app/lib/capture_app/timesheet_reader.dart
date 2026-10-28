import 'dart:math' as math;

import '../core/formatters.dart';
import 'ref_data.dart';

/// Reading a photo of a filled-in printed timesheet on the phone (free, no
/// internet): the page's QR code says which sheet it is; Google's on-phone
/// text recognition gives each piece of text with where it is. The printed
/// day numbers along the top and row numbers down the side say where the
/// boxes are (even with the page photographed at an angle); each handwritten
/// number goes in the box it sits in. Someone checks it all in the hub.

/// A piece of text found in the photo, with its centre and size in pixels.
class OcrBox {
  const OcrBox(this.text, this.cx, this.cy, {this.w = 0, this.h = 0});
  final String text;
  final double cx, cy, w, h;
}

/// Why a photo can't be read: shown on the phone, to take it again.
class SheetReadProblem implements Exception {
  SheetReadProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A page's QR code (timesheet_pdf.dart's timesheetCode):
/// NTS2|month|first day|last day|farm|group|page/pages|ids (ids shortened).
class SheetCode {
  SheetCode({
    required this.month,
    required this.first,
    required this.last,
    required this.farm,
    required this.group,
    required this.page,
    required this.pages,
    required this.ids,
  });
  final String month, first, last, farm;
  final String? group;
  final int page, pages;
  final List<String> ids;

  static SheetCode parse(String? text) {
    final p = (text ?? '').trim().split('|');
    if (p.length != 8 || p[0] != 'NTS2') throw SheetReadProblem("This isn't a Nanini timesheet's QR code -- print the sheet from the hub");
    final pg = p[6].split('/');
    final page = int.tryParse(pg.first), pages = int.tryParse(pg.last);
    if (page == null || pages == null || DateTime.tryParse(p[2]) == null || DateTime.tryParse(p[3]) == null) {
      throw SheetReadProblem("The QR code couldn't be understood -- take the photo again");
    }
    return SheetCode(
      month: p[1],
      first: p[2],
      last: p[3],
      farm: p[4],
      group: p[5] == '-' ? null : p[5],
      page: page,
      pages: pages,
      ids: p[7].split(',').where((s) => s.isNotEmpty).toList(),
    );
  }

  List<String> get days {
    final out = <String>[];
    for (var d = DateTime.parse(first); !d.isAfter(DateTime.parse(last)); d = DateTime(d.year, d.month, d.day + 1)) {
      out.add(toDateStr(d));
    }
    return out;
  }

  /// The number in the # column of the page's first line (numbered across pages).
  int get firstRow => (page - 1) * kSheetRows + 1;
}

/// Lines per printed page (kTimesheetRows in timesheet_pdf.dart).
const kSheetRows = 20;

/// Where the printed table's columns are, in day-column widths, with the
/// first day column's centre at 0 (timesheet_pdf.dart: # 16 pt, then flex
/// widths Surname 3.4, Name 3.2, ID 3.6, a day 1, Total 1.7 over 766 pt).
class SheetLayout {
  SheetLayout(this.dayCount) : unit = 766 / (3.4 + 3.2 + 3.6 + dayCount + 1.7);
  final int dayCount;

  /// One day column's width in points.
  final double unit;

  double get hashCentre => -(0.5 + 3.6 + 3.2 + 3.4 + 8 / unit);
  static const surname = (-10.7, -7.3), name = (-7.3, -4.1), idNumber = (-4.1, -0.5);
  (double, double) get total => (dayCount - 0.5, dayCount + 1.2);

  /// The day numbers' line in the header, in lines (21.5 pt) above the
  /// first line's centre -- measured on the printed sheet.
  static const headerRow = -1.25;
}

/// u = a·x + b·y + c: one coordinate of the table from a point in the photo.
class _Plane {
  _Plane(this.a, this.b, this.c);
  final double a, b, c;
  double at(double x, double y) => a * x + b * y + c;

  /// Least squares through (x, y) -> value; null when the points don't fix it.
  static _Plane? fit(List<(double, double, double)> pts) {
    if (pts.length < 3) return null;
    // Normal equations for [a b c].
    var sxx = 0.0, sxy = 0.0, sx = 0.0, syy = 0.0, sy = 0.0, n = 0.0, sxv = 0.0, syv = 0.0, sv = 0.0;
    for (final (x, y, v) in pts) {
      sxx += x * x;
      sxy += x * y;
      sx += x;
      syy += y * y;
      sy += y;
      n += 1;
      sxv += x * v;
      syv += y * v;
      sv += v;
    }
    final m = [
      [sxx, sxy, sx, sxv],
      [sxy, syy, sy, syv],
      [sx, sy, n, sv],
    ];
    for (var col = 0; col < 3; col++) {
      var pivot = col;
      for (var r = col + 1; r < 3; r++) {
        if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
      }
      if (m[pivot][col].abs() < 1e-9) return null;
      final t = m[col];
      m[col] = m[pivot];
      m[pivot] = t;
      for (var r = 0; r < 3; r++) {
        if (r == col) continue;
        final f = m[r][col] / m[col][col];
        for (var k = col; k < 4; k++) {
          m[r][k] -= f * m[col][k];
        }
      }
    }
    return _Plane(m[0][3] / m[0][0], m[1][3] / m[1][1], m[2][3] / m[2][2]);
  }

  /// Fits, then drops the points far off (text mistaken for a landmark) and fits again.
  static _Plane? robust(List<(double, double, double)> pts, {double tolerance = 0.35}) {
    var fit = _Plane.fit(pts);
    for (var i = 0; i < 2 && fit != null; i++) {
      final f = fit;
      final kept = [for (final p in pts) if ((f.at(p.$1, p.$2) - p.$3).abs() <= tolerance) p];
      if (kept.length == pts.length || kept.length < 3) break;
      pts = kept;
      fit = _Plane.fit(pts);
    }
    return fit;
  }
}

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// The day numbers printed along the top: (column, centre) for each found.
List<(int, OcrBox)> _headerAnchors(List<OcrBox> words, List<String> days) {
  final dayNos = [for (final d in days) DateTime.parse(d).day];
  final cands = [for (final w in words) if (w.text.trim() == _digits(w.text) && dayNos.contains(int.tryParse(w.text.trim()))) w];
  if (cands.isEmpty) return [];
  final heights = [for (final w in words) w.h]..sort();
  final tol = math.max(heights.isEmpty ? 10.0 : heights[heights.length ~/ 2], 4.0) * 1.5;
  // The band (by height in the photo) holding most of them: the header row.
  List<OcrBox> best = [];
  for (final c in cands) {
    final band = [for (final o in cands) if ((o.cy - c.cy).abs() <= tol) o];
    if (band.length > best.length) best = band;
  }
  best.sort((a, b) => a.cx.compareTo(b.cx));
  // Left to right, matched in order to the days (the same day number can
  // be at both ends of the sheet).
  final out = <(int, OcrBox)>[];
  var next = 0;
  for (final w in best) {
    final v = int.parse(w.text.trim());
    for (var i = next; i < dayNos.length; i++) {
      if (dayNos[i] == v) {
        out.add((i, w));
        next = i + 1;
        break;
      }
    }
  }
  return out;
}

/// A handwritten box's text as hours: '' empty, '9.5', or '?' when it isn't
/// a number of hours. Common misreadings of handwritten digits are fixed.
String sheetCellText(String raw) {
  var t = raw.replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return '';
  if (RegExp(r'^[-–_xX/\\✓✔Aa]+$').hasMatch(t)) return '';
  const fix = {'O': '0', 'o': '0', 'D': '0', 'Q': '0', 'l': '1', 'I': '1', '|': '1', 'i': '1', '!': '1', 'Z': '2', 'z': '2', 'S': '5', 's': '5', 'B': '8', 'g': '9', 'q': '9', ',': '.', '½': '.5'};
  t = t.split('').map((c) => fix[c] ?? c).join();
  if (t.startsWith('.')) t = '0$t';
  final v = double.tryParse(t);
  if (v == null || v <= 0 || v > 24) return '?';
  return v == v.roundToDouble() ? '${v.toInt()}' : '$v';
}

/// The page as read: the same shape the hub checks (TimesheetRead): the sheet,
/// and per line the worker (printed) or name and ID (written in), the hours
/// per day and the total. [symbols] are single characters (Android), else
/// [words] are used for the handwriting.
Map<String, dynamic> readSheet({required SheetCode code, required List<OcrBox> words, List<OcrBox> symbols = const [], required RefData ref}) {
  final farm = ref.farms.where((f) => f.id.startsWith(code.farm)).toList();
  if (farm.length != 1) throw SheetReadProblem("The sheet's farm isn't on this phone -- open the app on Wi-Fi to update it, then try again");
  final group = code.group == null ? null : ref.groups.where((g) => g.id.startsWith(code.group!)).firstOrNull;
  final days = code.days;
  final layout = SheetLayout(days.length);
  final printed = [for (final id in code.ids) ref.people.where((p) => p.id.startsWith(id)).firstOrNull];

  // Landmarks: the day numbers (top) and row numbers (left), and the printed surnames.
  final header = _headerAnchors(words, days);
  final rowNos = <(int, OcrBox)>[];
  if (header.isNotEmpty) {
    final leftOfDays = header.first.$2.cx;
    final rowCands = [
      for (final w in words)
        if (w.cx < leftOfDays && w.cy > header.first.$2.cy)
          if (int.tryParse(w.text.trim()) case final n? when n >= code.firstRow && n < code.firstRow + kSheetRows) (n - code.firstRow, w),
    ];
    // The column (across the photo) holding most of them: the # column.
    final widths = [for (final w in words) w.h]..sort();
    final tol = math.max(widths.isEmpty ? 10.0 : widths[widths.length ~/ 2], 4.0) * 2;
    for (final c in rowCands) {
      final col = [for (final o in rowCands) if ((o.$2.cx - c.$2.cx).abs() <= tol) o];
      if (col.length > rowNos.length) {
        rowNos
          ..clear()
          ..addAll(col);
      }
    }
  }
  final surnames = <(int, OcrBox)>[];
  for (final (i, p) in printed.indexed) {
    final s = (p?.surname ?? '').trim().toLowerCase();
    if (s.length < 3) continue;
    for (final w in words) {
      if (w.text.trim().toLowerCase() == s) surnames.add((i, w));
    }
  }
  if (header.length < 3 || rowNos.length + surnames.length < 2) {
    throw SheetReadProblem("The sheet's lines couldn't be found -- take the photo again: straight above it, the whole page, in good light");
  }
  final u = _Plane.robust([
    for (final (i, w) in header) (w.cx, w.cy, i.toDouble()),
    for (final (_, w) in rowNos) (w.cx, w.cy, layout.hashCentre),
  ]);
  final v = _Plane.robust([
    for (final (_, w) in header) (w.cx, w.cy, SheetLayout.headerRow),
    for (final (r, w) in rowNos) (w.cx, w.cy, r.toDouble()),
    for (final (r, w) in surnames) (w.cx, w.cy, r.toDouble()),
  ]);
  if (u == null || v == null) throw SheetReadProblem("The sheet's lines couldn't be found -- take the photo again, straight above it");

  // Each piece of handwriting into its box.
  final ink = symbols.isNotEmpty ? symbols : words;
  final boxes = <(int, String), List<OcrBox>>{};
  for (final s in ink) {
    final cu = u.at(s.cx, s.cy), cv = v.at(s.cx, s.cy);
    final row = cv.round();
    if (row < 0 || row >= kSheetRows || (cv - row).abs() > 0.45) continue;
    final String col;
    if (cu >= -0.5 && cu < layout.dayCount - 0.5) {
      col = 'd${cu.round()}';
    } else if (cu >= layout.total.$1 && cu < layout.total.$2) {
      col = 'total';
    } else if (cu >= SheetLayout.idNumber.$1 && cu < SheetLayout.idNumber.$2) {
      col = 'id';
    } else if (cu >= SheetLayout.name.$1 && cu < SheetLayout.name.$2) {
      col = 'name';
    } else if (cu >= SheetLayout.surname.$1 && cu < SheetLayout.surname.$2) {
      col = 'surname';
    } else {
      continue;
    }
    boxes.putIfAbsent((row, col), () => []).add(s);
  }
  String text(int row, String col, {bool spaced = false}) {
    final list = [...?boxes[(row, col)]]..sort((a, b) => a.cx.compareTo(b.cx));
    return list.map((s) => s.text).join(spaced && symbols.isEmpty ? ' ' : '').trim();
  }

  var unclear = 0;
  final rows = <Map<String, dynamic>>[];
  for (var r = 0; r < kSheetRows; r++) {
    final hours = [for (var d = 0; d < days.length; d++) sheetCellText(text(r, 'd$d'))];
    unclear += hours.where((h) => h == '?').length;
    final total = sheetCellText(text(r, 'total'));
    if (r < printed.length) {
      final p = printed[r];
      rows.add({
        'row': code.firstRow + r,
        'employee_id': p?.id,
        if (p == null) 'id_prefix': code.ids[r],
        'name': p?.name ?? '(not on this phone)',
        'hours': hours,
        'total': total,
      });
    } else {
      final written = '${text(r, 'surname', spaced: true)} ${text(r, 'name', spaced: true)}'.trim();
      final idNo = text(r, 'id').replaceAll(RegExp(r'\s'), '');
      if (written.isEmpty && idNo.isEmpty && hours.every((h) => h.isEmpty)) continue;
      final match = idNo.length < 6 ? <RefPerson>[] : ref.people.where((p) => (p.idOrPassport ?? '').replaceAll(' ', '').toUpperCase() == idNo.toUpperCase()).toList();
      rows.add({
        'row': code.firstRow + r,
        'employee_id': match.length == 1 ? match.single.id : null,
        if (match.length == 1) 'name': match.single.name,
        'written_name': written,
        'id_number': idNo,
        'hours': hours,
        'total': total,
      });
    }
  }
  return {
    'farm_id': farm.single.id,
    'farm_name': farm.single.name,
    'group_id': group?.id,
    'group_name': group?.name,
    'month': code.month,
    'page': '${code.page}/${code.pages}',
    'days': days,
    'rows': rows,
    'notes': unclear == 0 ? '' : '$unclear box${unclear == 1 ? '' : 'es'} not clear',
    'read_on': 'phone',
  };
}
