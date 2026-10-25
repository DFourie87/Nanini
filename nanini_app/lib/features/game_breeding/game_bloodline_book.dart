import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/formatters.dart';
import 'game_breeding_models.dart';

/// Each herd's book in its owner's own look: logo, accent (footer, titles),
/// muted text, rules and empty photo boxes. Another owner: Nanini's colours,
/// no logo (its animals aren't Nanini's).
typedef _Look = ({String? logo, PdfColor accent, PdfColor? title, PdfColor muted, PdfColor line, PdfColor empty});
final _looks = <String, _Look>{
  'Nanini': (
    logo: 'assets/images/hub-logo-print.png',
    accent: PdfColor.fromInt(0xFFEC1F24),
    title: null,
    muted: PdfColor.fromInt(0xFF4A4A4A),
    line: PdfColor.fromInt(0xFFE4D6C3),
    empty: PdfColor.fromInt(0xFFF0E7D8),
  ),
  // Eljuro Beleggings' logo: sage green and charcoal.
  'Eljuro': (
    logo: 'assets/images/eljuro-logo-print.png',
    accent: PdfColor.fromInt(0xFF688662),
    title: PdfColor.fromInt(0xFF688662),
    muted: PdfColor.fromInt(0xFF545454),
    line: PdfColor.fromInt(0xFFD8E1DA),
    empty: PdfColor.fromInt(0xFFEAF0EA),
  ),
};

/// The PDF's built-in font has Latin-1 only: dashes, curly quotes and the
/// like as their plain kind (else they print as boxes).
String _latin(String s) => s
    .replaceAll(RegExp('[\u2013\u2014\u2212]'), '-')
    .replaceAll(RegExp('[\u2018\u2019]'), "'")
    .replaceAll(RegExp('[\u201C\u201D]'), '"')
    .replaceAll('\u2026', '...')
    .replaceAll(RegExp('[^\u0000-\u00FF]'), '?');

pw.Widget _text(String s, {pw.TextStyle? style, pw.TextAlign? textAlign, int? maxLines}) =>
    pw.Text(_latin(s), style: style, textAlign: textAlign, maxLines: maxLines);

/// The herds' names on the books: an owner as kept in the register -> its name.
const kBookNames = {'Nanini': 'Nanini Boerdery', 'Eljuro': 'Eljuro Beleggings'};
String bookName(String owner) => kBookNames[owner] ?? owner;

/// A herd's animals on the farm (alive), as the book lists them: cows,
/// bulls, then calves whose sex isn't known yet.
List<GameAnimal> bookAnimals(Iterable<GameAnimal> animals, String owner) {
  final mine = animals.where((a) => a.onFarm && a.isAlive && a.owner == owner).toList();
  int group(GameAnimal a) => switch (a.sex) { 'F' => 0, 'M' => 1, _ => 2 };
  return mine..sort((a, b) => group(a) != group(b) ? group(a).compareTo(group(b)) : a.tag.toLowerCase().compareTo(b.tag.toLowerCase()));
}

/// The ancestors behind [animals] (by tag, through the register's parents),
/// [generations] deep.
Set<String> ancestorTags(Iterable<GameAnimal> animals, Map<String, GameAnimal> byTag, {int generations = 6}) {
  final out = <String>{};
  var level = {for (final a in animals) a.tag};
  for (var g = 0; g < generations && level.isNotEmpty; g++) {
    final next = <String>{};
    for (final t in level) {
      for (final p in [byTag[t]?.sire, byTag[t]?.dam]) {
        if ((p ?? '').isNotEmpty && out.add(p!)) next.add(p);
      }
    }
    level = next;
  }
  return out;
}

/// "11y 8m on 24/10/2026" for a full date of birth; null otherwise.
String? ageOn(String? born, DateTime today) {
  final d = born == null || born.length != 10 ? null : DateTime.tryParse(born);
  if (d == null) return null;
  var months = (today.year - d.year) * 12 + today.month - d.month - (today.day < d.day ? 1 : 0);
  if (months < 0) months = 0;
  return '${months ~/ 12}y ${months % 12}m on ${fmtDateDisplay(toDateStr(today))}';
}

/// The bloodline book of one herd ([owner]): a cover with its contents, then
/// a page per animal -- its photo and details, its parents, grandparents and
/// great-grandparents with their photos, its offspring on the farm and the
/// notes. Built from the register, so it always has the latest data and each
/// animal's own photo. [photo] fetches a photo's bytes (null: not available).
/// [only]: just that animal's page (no cover).
Future<pw.Document> buildBloodlineBook({
  required String owner,
  required List<GameAnimal> animals,
  required Future<Uint8List?> Function(String path) photo,
  GameAnimal? only,
  DateTime? today,
}) async {
  final now = today ?? DateTime.now();
  final byTag = {for (final a in animals) a.tag: a};
  final members = only != null ? [only] : bookAnimals(animals, owner);
  final name = bookName(owner);
  const months = ['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'];
  final edition = '${months[now.month - 1]} ${now.year}';

  // Every photo the book shows: the animals' and their three generations'.
  List<String?> line(String tag, int depth) {
    // Breadth first: parents, grandparents, great-grandparents (null: unknown).
    final out = <String?>[];
    var level = <String?>[tag];
    for (var g = 0; g < depth; g++) {
      level = [for (final t in level) ...[t == null ? null : byTag[t]?.sire, t == null ? null : byTag[t]?.dam]]
          .map((t) => (t ?? '').isEmpty ? null : t)
          .toList();
      out.addAll(level);
    }
    return out;
  }

  final paths = <String>{
    for (final a in members) ...[
      ?a.photo,
      for (final t in line(a.tag, 3)) ?byTag[t]?.photo,
    ],
  };
  final images = <String, pw.MemoryImage>{};
  final list = paths.toList();
  for (var i = 0; i < list.length; i += 6) {
    await Future.wait([
      for (final p in list.skip(i).take(6))
        photo(p).then((b) {
          if (b != null) images[p] = pw.MemoryImage(b);
        }, onError: (_) {}),
    ]);
  }
  final n = _looks['Nanini']!;
  final look = _looks[owner] ?? (logo: null, accent: n.accent, title: n.title, muted: n.muted, line: n.line, empty: n.empty);
  Future<pw.MemoryImage> load(String asset) async => pw.MemoryImage((await rootBundle.load(asset)).buffer.asUint8List());
  final logo = look.logo == null ? null : await load(look.logo!);
  // Another herd's animal by one of Nanini's own bulls (e.g. Eben), now and
  // later: Nanini's logo next to its owner's on that page.
  bool byNaniniBull(GameAnimal a) {
    final sire = byTag[a.sire];
    return owner != 'Nanini' && sire != null && sire.onFarm && sire.owner == 'Nanini';
  }
  final naniniLogo = members.any(byNaniniBull) ? await load(n.logo!) : null;

  pw.Widget pic(String? tag, double w, double h, {double radius = 6}) {
    final animal = tag == null ? null : byTag[tag];
    final img = images[animal?.photo];
    // Cropped around the head (the PDF's y runs up, the app's down).
    final (fx, fy) = animal?.focus ?? (0.0, -0.25);
    return pw.ClipRRect(
      horizontalRadius: radius,
      verticalRadius: radius,
      child: img == null
          ? pw.Container(width: w, height: h, color: look.empty)
          : pw.Image(img, width: w, height: h, fit: pw.BoxFit.cover, alignment: pw.Alignment(fx, -fy)),
    );
  }

  String caption(String tag) {
    final a = byTag[tag];
    final horns = a?.horns;
    return [a?.label ?? tag, if ((horns ?? '').isNotEmpty && !horns!.contains('SCI')) horns].join(' ');
  }

  final doc = pw.Document(title: '$name – Buffalo Bloodlines');
  final pageFormat = PdfPageFormat.a4.landscape;

  // --- Cover (the whole book only) ---
  final groups = [
    ('Cows', members.where((a) => a.sex == 'F').toList()),
    ('Bulls', members.where((a) => a.sex == 'M').toList()),
    ('Calves', members.where((a) => a.sex == null).toList()),
  ];
  if (only == null) {
    doc.addPage(pw.Page(
    pageFormat: pageFormat,
    margin: const pw.EdgeInsets.all(40),
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        // The page's full width, so everything centres on the page.
        pw.SizedBox(width: double.infinity, height: 30),
        if (logo != null) pw.Image(logo, height: 150) else pw.SizedBox(height: 120),
        pw.SizedBox(height: 16),
        _text('Buffalo Bloodlines', style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold, color: look.title)),
        pw.SizedBox(height: 6),
        _text(name.toUpperCase(), style: pw.TextStyle(fontSize: 11, color: look.muted, letterSpacing: 2)),
        pw.SizedBox(height: 26),
        for (final (title, list) in groups)
          if (list.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: _text('$title:  ${list.map((a) => '${a.label}  p${members.indexOf(a) + 2}').join('  ·  ')}',
                  textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
            ),
        pw.Spacer(),
        _text(edition.toUpperCase(), style: pw.TextStyle(fontSize: 10, color: look.muted, letterSpacing: 2)),
      ],
    ),
    ));
  }

  // --- A page per animal ---
  pw.Widget label(String t) => _text(t.toUpperCase(), style: pw.TextStyle(fontSize: 7, color: look.muted, letterSpacing: 1.5));
  for (final a in members) {
    final gens = line(a.tag, 3);
    final offspring = animals.where((x) => x.onFarm && (x.sire == a.tag || x.dam == a.tag)).map((x) => x.label).toList()..sort();
    final details = <(String, String?)>[
      ('Microchip', a.microchip),
      ('Born', a.born == null ? null : [a.born!.length == 10 ? fmtDateDisplay(a.born!) : a.born!, if (ageOn(a.born, now) != null) '(${ageOn(a.born, now)})'].join(' ')),
      ('Sex', switch (a.sex) { 'F' => 'Female', 'M' => 'Male', _ => 'Not known yet' }),
      ('Camp', a.camp),
      ('Spread (RW)', a.horns),
      ('SCI', a.sci),
      ('Last measured', a.measured == null ? null : (a.measured!.length == 10 ? fmtDateDisplay(a.measured!) : a.measured)),
      ('In calf to', a.inCalfTo),
      ('Source', a.source),
      ('DNA', a.dna),
    ].where((d) => (d.$2 ?? '').isNotEmpty).toList();
    final sub = [
      if ((a.subspecies ?? '').isNotEmpty) a.subspecies!.toUpperCase(),
      if ((a.horns ?? '').isNotEmpty) 'RW ${a.horns}',
      if ((a.sci ?? '').isNotEmpty) 'SCI ${a.sci!.split(' ').first}',
    ].join('   |   ');

    // A generation: [tags] spread evenly down the column, each a photo and its caption.
    pw.Widget column(String title, List<String?> tags, double w, double h, double font) => pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            label(title),
            pw.SizedBox(height: 4),
            for (final t in tags)
              pw.Expanded(
                child: pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: t == null
                      ? pw.SizedBox()
                      : pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                          pic(t, w, h, radius: 4),
                          pw.SizedBox(height: 1.5),
                          pw.SizedBox(
                            width: w + 20,
                            child: _text(caption(t), textAlign: pw.TextAlign.center, maxLines: 1, style: pw.TextStyle(fontSize: font)),
                          ),
                        ]),
                ),
              ),
          ]),
        );

    doc.addPage(pw.Page(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 20),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                _text(a.label, style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: look.title)),
                if (sub.isNotEmpty) _text(sub, style: pw.TextStyle(fontSize: 9, letterSpacing: 1.2)),
              ]),
            ),
            if (naniniLogo != null && byNaniniBull(a)) ...[pw.Image(naniniLogo, height: 44), pw.SizedBox(width: 14)],
            if (logo != null) pw.Image(logo, height: 44),
          ]),
          pw.Divider(color: look.line, thickness: 0.8),
          pw.Expanded(
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(
                width: 250,
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  a.photo != null && images[a.photo] != null
                      ? pic(a.tag, 250, 167, radius: 12)
                      : pw.Container(
                          width: 250,
                          height: 167,
                          decoration: pw.BoxDecoration(color: look.empty, borderRadius: pw.BorderRadius.circular(12)),
                          alignment: pw.Alignment.center,
                          child: _text('PHOTO NEEDED', style: pw.TextStyle(fontSize: 10, color: look.muted, letterSpacing: 2)),
                        ),
                  pw.SizedBox(height: 10),
                  label('Details'),
                  pw.SizedBox(height: 3),
                  for (final (k, v) in details)
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2.2),
                      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: look.line, width: 0.5))),
                      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.SizedBox(width: 72, child: _text(k, style: pw.TextStyle(fontSize: 7.5, color: look.muted))),
                        pw.Expanded(child: _text(v!, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
                      ]),
                    ),
                ]),
              ),
              pw.SizedBox(width: 22),
              pw.Expanded(
                child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
                  column('Parents', gens.sublist(0, 2), 120, 80, 8),
                  column('Grandparents', gens.sublist(2, 6), 96, 64, 7.5),
                  column('3rd generation', gens.sublist(6, 14), 60, 40, 6.5),
                ]),
              ),
            ]),
          ),
          pw.SizedBox(height: 6),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 110, child: label('Offspring on farm')),
            pw.Expanded(child: _text(offspring.isEmpty ? '—' : offspring.join(', '), style: const pw.TextStyle(fontSize: 8))),
          ]),
          if ((a.notes ?? '').isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(width: 110, child: label('Notes')),
              pw.Expanded(child: _text(a.notes!, maxLines: 4, style: const pw.TextStyle(fontSize: 8))),
            ]),
          ],
          pw.Divider(color: look.line, thickness: 0.8),
          _text('${name.toUpperCase()} – BUFFALO BLOODLINES   |   ${a.tag}   |   $edition', style: pw.TextStyle(fontSize: 7, color: look.accent, letterSpacing: 1.5)),
        ],
      ),
    ));
  }
  return doc;
}
