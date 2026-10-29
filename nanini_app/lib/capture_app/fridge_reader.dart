import 'dart:math' as math;

import '../features/capture/fridge_sheet_capture.dart' show fridgeCountUnclear;
import 'ref_data.dart';
import 'timesheet_reader.dart';

/// Reading a photo of a filled-in fridge sheet (wors, chicken pieces) on the
/// phone, like a timesheet: the page's QR code says which sheet it is, the
/// printed row numbers, headings and names say where the boxes are, and the
/// marks in each item's box are counted -- with the number written in its
/// Total box. Someone checks it all in the hub.

/// A fridge sheet page's QR code (fridge_sheet_pdf.dart's fridgeSheetCode):
/// NFS2|month|first day|last day|farm|items|page/pages|ids (ids shortened).
class FridgeCode {
  FridgeCode({
    required this.month,
    required this.first,
    required this.last,
    required this.farm,
    required this.items,
    required this.page,
    required this.pages,
    required this.ids,
  });
  final String month, first, last, farm;
  final List<String> items;
  final int page, pages;
  final List<String> ids;

  static FridgeCode parse(String? text) {
    final p = (text ?? '').trim().split('|');
    if (p.length != 8 || p[0] != 'NFS2') throw SheetReadProblem("This isn't a Nanini fridge sheet's QR code -- print the sheet from the hub");
    final pg = p[6].split('/');
    final page = int.tryParse(pg.first), pages = int.tryParse(pg.last);
    final items = p[5].split(',').where((s) => s.isNotEmpty).toList();
    if (page == null || pages == null || items.isEmpty || DateTime.tryParse(p[2]) == null || DateTime.tryParse(p[3]) == null) {
      throw SheetReadProblem("The QR code couldn't be understood -- take the photo again");
    }
    return FridgeCode(
      month: p[1],
      first: p[2],
      last: p[3],
      farm: p[4],
      items: items,
      page: page,
      pages: pages,
      ids: p[7].split(',').where((s) => s.isNotEmpty).toList(),
    );
  }

  /// The number in the # column of the page's first line (numbered across pages).
  int get firstRow => (page - 1) * kFridgeSheetRows + 1;
}

/// Lines per printed page (kFridgeRows in fridge_sheet_pdf.dart).
const kFridgeSheetRows = 20;

/// Where the printed table's columns are, in points from its left edge
/// (fridge_sheet_pdf.dart: landscape A4, the table 782 pt wide: # 18 pt,
/// then flex widths Surname 3.4, Name 3.2, and per item its box -- 8.5, or
/// 18 for one item -- and Total 1.4). Measured on the printed sheet.
class FridgeLayout {
  FridgeLayout(this.itemCount)
      : box = itemCount == 1 ? 18 : 8.5,
        unit = 764 / (3.4 + 3.2 + itemCount * ((itemCount == 1 ? 18 : 8.5) + 1.4));
  final int itemCount;
  final double box, unit;

  static const hashCentre = 9.0, surnameLeft = 18.0;
  double get nameLeft => surnameLeft + 3.4 * unit;
  double get firstItemLeft => nameLeft + 3.2 * unit;
  double itemLeft(int i) => firstItemLeft + i * (box + 1.4) * unit;
  double totalLeft(int i) => itemLeft(i) + box * unit;
  double totalCentre(int i) => totalLeft(i) + 0.7 * unit;
  double get right => itemLeft(itemCount);

  /// Left-aligned text starts this far into its box.
  static const textInset = 3.0;

  /// The headings' line, in lines (22 pt) above the first line's centre.
  static const headerRow = -0.905;
}

/// The marks in an item's box, counted from what the text recognition made
/// of them: a mark ( | ) reads as | I l 1 / ...; two or three strokes run
/// together as one letter (H, N, M ...). A number written instead of marks
/// counts as that number. Dots, dashes and commas (a stroke through a group
/// of five, specks) don't count.
int fridgeMarks(String raw) {
  final t = raw.replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return 0;
  if (RegExp(r'^[0-9]{1,2}$').hasMatch(t) && !RegExp(r'^1+$').hasMatch(t)) return int.parse(t);
  var n = 0;
  for (final c in t.split('')) {
    if ('.,-_~=—–:;\'"`°'.contains(c)) continue;
    if ('HNUnuVvhK'.contains(c)) {
      n += 2;
    } else if ('MWmw'.contains(c)) {
      n += 3;
    } else {
      n += 1;
    }
  }
  return n;
}

/// The count written in a Total box: '' empty, '7', or '?' when it isn't a
/// count. Common misreadings of handwritten digits are fixed.
String fridgeTotalText(String raw) {
  var t = raw.replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return '';
  if (RegExp(r'^[-–_xX/\\]+$').hasMatch(t)) return '';
  const fix = {'O': '0', 'o': '0', 'D': '0', 'Q': '0', 'l': '1', 'I': '1', '|': '1', 'i': '1', '!': '1', 'Z': '2', 'z': '2', 'S': '5', 's': '5', 'B': '8', 'g': '9', 'q': '9'};
  t = t.split('').map((c) => fix[c] ?? c).join();
  final v = int.tryParse(t);
  if (v == null || v < 0 || v > 300) return '?';
  return '$v';
}

/// The page as read: the same shape the hub checks (FridgeRead): the sheet,
/// its items, and per line the worker (printed) or the name written in, with
/// per item the marks counted and the total written. [symbols] are single
/// characters (Android), else [words] are used for the handwriting.
Map<String, dynamic> readFridgeSheet({required FridgeCode code, required List<OcrBox> words, List<OcrBox> symbols = const [], required RefData ref}) {
  final farm = ref.farms.where((f) => f.id.startsWith(code.farm)).toList();
  if (farm.length != 1) throw SheetReadProblem("The sheet's farm isn't on this phone -- open the app on Wi-Fi to update it, then try again");
  final layout = FridgeLayout(code.items.length);
  final printed = [for (final id in code.ids) ref.people.where((p) => p.id.startsWith(id)).firstOrNull];
  final items = [
    for (final prefix in code.items)
      if (ref.shopItems.where((i) => i.id.startsWith(prefix)).firstOrNull case final item?)
        {'id': item.id, 'prefix': prefix, 'name': item.name}
      else
        {'id': null, 'prefix': prefix, 'name': '(not on this phone)'},
  ];

  double left(OcrBox w) => w.cx - w.w / 2;
  String low(String s) => s.trim().toLowerCase();
  final heights = [for (final w in words) w.h]..sort();
  final lineH = math.max(heights.isEmpty ? 10.0 : heights[heights.length ~/ 2], 4.0);

  // Landmarks: the row numbers down the # column, the headings, the printed names.
  final rowCands = [
    for (final w in words)
      if (int.tryParse(w.text.trim()) case final n? when n >= code.firstRow && n < code.firstRow + kFridgeSheetRows) (n - code.firstRow, w),
  ];
  final rowNos = <(int, OcrBox)>[];
  for (final c in rowCands) {
    // The column (across the photo) holding most of them: the # column.
    final col = [for (final o in rowCands) if ((o.$2.cx - c.$2.cx).abs() <= lineH * 2) o];
    if (col.length > rowNos.length) {
      rowNos
        ..clear()
        ..addAll(col);
    }
  }
  final heads = <(double, OcrBox, bool)>[]; // (u, word, left-aligned?)
  final surnameHead = words.where((w) => low(w.text) == 'surname').toList();
  final nameHead = words.where((w) => low(w.text) == 'name').toList();
  final totals = words.where((w) => low(w.text) == 'total').toList()..sort((a, b) => a.cx.compareTo(b.cx));
  if (surnameHead.length == 1) heads.add((FridgeLayout.surnameLeft + FridgeLayout.textInset, surnameHead.single, true));
  if (nameHead.length == 1) heads.add((layout.nameLeft + FridgeLayout.textInset, nameHead.single, true));
  if (totals.length == code.items.length) {
    for (final (i, w) in totals.indexed) {
      heads.add((layout.totalCentre(i), w, false));
    }
  }
  final names = <(int, OcrBox, double)>[]; // (row, word, u of its left edge)
  for (final (i, p) in printed.indexed) {
    final s = low(p?.surname ?? ''), n = low(p?.knownName ?? '');
    for (final w in words) {
      if (s.length >= 3 && low(w.text) == s) names.add((i, w, FridgeLayout.surnameLeft + FridgeLayout.textInset));
      if (n.length >= 3 && low(w.text) == n) names.add((i, w, layout.nameLeft + FridgeLayout.textInset));
    }
  }
  if (rowNos.length + names.length < 2 || heads.length + names.length < 1) {
    throw SheetReadProblem("The sheet's lines couldn't be found -- take the photo again: straight above it, the whole page, in good light");
  }
  final u = SheetPlane.robust([
    for (final (_, w) in rowNos) (w.cx, w.cy, FridgeLayout.hashCentre),
    for (final (x, w, isLeft) in heads) (isLeft ? left(w) : w.cx, w.cy, x),
    for (final (_, w, x) in names) (left(w), w.cy, x),
  ], tolerance: 14);
  final v = SheetPlane.robust([
    for (final (r, w) in rowNos) (w.cx, w.cy, r.toDouble()),
    for (final (_, w, _) in heads) (w.cx, w.cy, FridgeLayout.headerRow),
    for (final (r, w, _) in names) (w.cx, w.cy, r.toDouble()),
  ]);
  if (u == null || v == null) throw SheetReadProblem("The sheet's lines couldn't be found -- take the photo again, straight above it");

  // Each piece of handwriting into its box.
  final ink = symbols.isNotEmpty ? symbols : words;
  final boxes = <(int, String), List<OcrBox>>{};
  for (final s in ink) {
    final cu = u.at(s.cx, s.cy), cv = v.at(s.cx, s.cy);
    final row = cv.round();
    if (row < 0 || row >= kFridgeSheetRows || (cv - row).abs() > 0.45) continue;
    String? col;
    if (cu >= FridgeLayout.surnameLeft && cu < layout.nameLeft) {
      col = 'surname';
    } else if (cu >= layout.nameLeft && cu < layout.firstItemLeft) {
      col = 'name';
    } else {
      for (var i = 0; i < code.items.length; i++) {
        if (cu >= layout.itemLeft(i) && cu < layout.totalLeft(i)) col = 'm$i';
        if (cu >= layout.totalLeft(i) && cu < layout.itemLeft(i + 1)) col = 't$i';
      }
    }
    if (col != null) boxes.putIfAbsent((row, col), () => []).add(s);
  }
  String text(int row, String col, {bool spaced = false}) {
    final list = [...?boxes[(row, col)]]..sort((a, b) => a.cx.compareTo(b.cx));
    return list.map((s) => s.text).join(spaced && symbols.isEmpty ? ' ' : '').trim();
  }

  var unclear = 0;
  final rows = <Map<String, dynamic>>[];
  for (var r = 0; r < kFridgeSheetRows; r++) {
    final counts = <Map<String, dynamic>>[];
    for (var i = 0; i < code.items.length; i++) {
      final marks = fridgeMarks(text(r, 'm$i')), total = fridgeTotalText(text(r, 't$i'));
      if (fridgeCountUnclear(marks, total)) unclear++;
      counts.add({'marks': marks, 'total': total});
    }
    final taken = counts.any((c) => c['marks'] != 0 || '${c['total']}'.isNotEmpty);
    if (r < printed.length) {
      final p = printed[r];
      rows.add({
        'row': code.firstRow + r,
        'employee_id': p?.id,
        if (p == null) 'id_prefix': code.ids[r],
        'name': p?.name ?? '(not on this phone)',
        'counts': counts,
      });
    } else {
      final written = '${text(r, 'surname', spaced: true)} ${text(r, 'name', spaced: true)}'.trim();
      if (written.isEmpty && !taken) continue;
      // A worker written in by hand: by their name and surname, when only one fits.
      final said = written.toLowerCase().split(RegExp(r'[^a-z]+')).where((s) => s.isNotEmpty).toSet();
      final match = ref.people
          .where((p) => said.contains(low(p.knownName)) && (p.surname ?? '').trim().isNotEmpty && said.contains(low(p.surname!)))
          .toList();
      rows.add({
        'row': code.firstRow + r,
        'employee_id': match.length == 1 ? match.single.id : null,
        if (match.length == 1) 'name': match.single.name,
        'written_name': written,
        'counts': counts,
      });
    }
  }
  return {
    'farm_id': farm.single.id,
    'farm_name': farm.single.name,
    'month': code.month,
    'first': code.first,
    'last': code.last,
    'page': '${code.page}/${code.pages}',
    'items': items,
    'rows': rows,
    'notes': unclear == 0 ? '' : '$unclear box${unclear == 1 ? '' : 'es'} where the marks and the total differ or the total is not clear',
    'read_on': 'phone',
  };
}
