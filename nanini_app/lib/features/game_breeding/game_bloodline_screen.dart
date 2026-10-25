import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../hours/hours_payslip_preview.dart' show showPdfPreview;
import 'game_bloodline_book.dart';
import 'game_breeding_models.dart';
import 'game_breeding_repository.dart';
import 'game_mating_check.dart';

enum _View { herd, mating, tree }

/// Bloodline, per herd's book (Nanini Boerdery, Eljuro Beleggings): the herd
/// register (every animal with its parents, born, horns, microchip, photo),
/// the mating guide (each cow × bull: the calf's inbreeding and best /
/// acceptable / avoid), an animal's family tree -- from the register and the
/// births logged here -- and the bloodline book as a PDF (whole, or one
/// animal's page) to print or send. [herd]: the Herd tab (the register
/// only); else the Bloodline tab (mating guide and family tree).
class GameBloodlineScreen extends StatefulWidget {
  const GameBloodlineScreen({super.key, required this.repo, required this.species, this.herd = false});
  final GameBreedingRepository repo;
  final String species;
  final bool herd;

  @override
  State<GameBloodlineScreen> createState() => _GameBloodlineScreenState();
}

class _GameBloodlineScreenState extends State<GameBloodlineScreen> {
  late final _views = widget.herd ? const [_View.herd] : const [_View.tree, _View.mating];
  late _View view = _views.first;
  String? selectedTag;

  /// The herd whose book is shown (its animals' owner).
  String book = 'Nanini';
  late final Stream<List<GameAnimal>> _animals = widget.repo.watchAnimals(widget.species);
  late final Stream<List<GameEvent>> _events = widget.repo.watchEvents();
  late Future<List<GameMating>> _matings = widget.repo.fetchMatings(widget.species);

  /// Links to the photos, by storage path (fetched as photos appear).
  final _urls = <String, String>{};
  final _asked = <String>{};

  /// Add photos: how far along ("12 of 69"), while uploading.
  String? _adding;

  void _loadUrls(List<GameAnimal> animals) {
    final missing = [for (final a in animals) if (a.photo != null && !_asked.contains(a.photo)) a.photo!];
    if (missing.isEmpty) return;
    _asked.addAll(missing);
    widget.repo.photoUrls(missing).then((m) {
      if (mounted) setState(() => _urls.addAll(m));
    }, onError: (Object e) => debugPrint('game photos: $e'));
  }

  /// [path]'s photo, cropped to [w] × [h] around [focus] (the head); a
  /// placeholder without one.
  Widget _photo(String? path, double w, double h, {double radius = 8, (double, double) focus = (0, -0.25)}) {
    final url = path == null ? null : _urls[path];
    final empty = Container(
      width: w,
      height: h,
      color: NaniniColors.disabledBg,
      child: Icon(Icons.pets_outlined, size: h * 0.45, color: NaniniColors.muted),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null
          ? empty
          : Image.network(url, width: w, height: h, fit: BoxFit.cover, alignment: Alignment(focus.$1, focus.$2), errorBuilder: (_, _, _) => empty),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GameAnimal>>(
      stream: _animals,
      builder: (context, animalSnap) => StreamBuilder<List<GameEvent>>(
        stream: _events,
        builder: (context, eventSnap) {
          // Before game_animals.sql: no register, the tree from births only.
          final missing = animalSnap.hasError;
          final animals = animalSnap.data ?? const <GameAnimal>[];
          _loadUrls(animals);
          final events = (eventSnap.data ?? const <GameEvent>[]).where((e) => e.species == widget.species).toList();
          final books = {'Nanini', for (final a in animals) if (a.onFarm && (a.owner ?? '').isNotEmpty) a.owner!}.toList()
            ..sort((a, b) => a == 'Nanini' ? -1 : (b == 'Nanini' ? 1 : a.compareTo(b)));
          if (!books.contains(book)) book = books.first;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (books.length > 1) ...[
                SegmentedButton<String>(
                  segments: [for (final b in books) ButtonSegment(value: b, label: Text(bookName(b), overflow: TextOverflow.ellipsis))],
                  selected: {book},
                  onSelectionChanged: (s) => setState(() => book = s.first),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rustDark, selectedForegroundColor: Colors.white),
                ),
                const SizedBox(height: 8),
              ],
              if (_views.length > 1) ...[
                SegmentedButton<_View>(
                  segments: [
                    for (final v in _views)
                      ButtonSegment(value: v, label: Text(switch (v) { _View.herd => 'Herd', _View.mating => 'Mating guide', _View.tree => 'Family tree' })),
                  ],
                  selected: {view},
                  onSelectionChanged: (s) => setState(() => view = s.first),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
                ),
                const SizedBox(height: 16),
              ] else
                const SizedBox(height: 8),
              if (missing && view != _View.tree)
                const Text('Run game_animals.sql in Supabase first.', style: TextStyle(color: NaniniColors.red))
              else
                ...switch (view) {
                  _View.herd => _herd(context, animals, events),
                  _View.mating => [
                      // An outside or new animal against this book's: worked out only, nothing stored.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.manage_search),
                          label: const Text('Check an animal (to buy or new)'),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => GameMatingCheckScreen(animals: animals, parents: parentsByTag(animals, events), book: book))),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _mating(context, animals),
                    ],
                  _View.tree => _tree(context, animals, events),
                },
            ],
          );
        },
      ),
    );
  }

  // --- Herd ---

  List<Widget> _herd(BuildContext context, List<GameAnimal> animals, List<GameEvent> events) {
    final onFarm = animals.where((a) => a.onFarm && a.owner == book).toList();
    final alive = onFarm.where((a) => a.isAlive).toList();
    final groups = [
      ('Cows', alive.where((a) => a.sex == 'F').toList()),
      ('Bulls', alive.where((a) => a.sex == 'M').toList()),
      ('Calves (sex not known yet)', alive.where((a) => a.sex == null).toList()),
      ('Died or sold', onFarm.where((a) => !a.isAlive).toList()),
    ];
    // This book's ancestors: behind its animals, through their parents.
    final byTag = {for (final a in animals) a.tag: a};
    final behind = ancestorTags(onFarm, byTag);
    final ancestors = animals.where((a) => !a.onFarm && behind.contains(a.tag)).toList();
    return [
      Row(children: [
        Expanded(child: Text(bookName(book), style: Theme.of(context).textTheme.titleMedium)),
        IconButton(
          tooltip: 'Bloodline book (PDF to print or send)',
          icon: const Icon(Icons.menu_book_outlined),
          onPressed: () => runOnce('bloodline.book', () => _showBook(context, animals)),
        ),
        IconButton(
          tooltip: 'Add photos (files named by tag)',
          icon: const Icon(Icons.add_photo_alternate_outlined),
          onPressed: _adding != null ? null : () => runOnce('bloodline.photos', () => _addPhotos(context, animals)),
        ),
        IconButton(
          tooltip: 'Add an animal',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => runOnce('bloodline.add', () => _edit(context, null)),
        ),
      ]),
      const SizedBox(height: 4),
      Text('${alive.length} on the farm', style: const TextStyle(color: NaniniColors.muted)),
      if (_adding != null) Text('Adding photos: $_adding', style: const TextStyle(color: NaniniColors.rustDark)),
      if (animals.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No animals in the register yet.')),
      for (final (title, list) in groups)
        if (list.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('$title (${list.length})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final a in list) _animalTile(context, a, animals, events),
        ],
      if (ancestors.isNotEmpty) ...[
        const SizedBox(height: 16),
        Card(
          child: ExpansionTile(
            title: Text('Ancestors in the pedigrees (${ancestors.length})'),
            children: [for (final a in ancestors) _animalTile(context, a, animals, events, flat: true)],
          ),
        ),
      ],
    ];
  }

  Widget _animalTile(BuildContext context, GameAnimal a, List<GameAnimal> animals, List<GameEvent> events, {bool flat = false}) {
    final line = [
      if ((a.born ?? '').isNotEmpty) 'born ${a.born!.length == 4 ? a.born : fmtDateDisplay(a.born!)}',
      if ((a.horns ?? '').isNotEmpty) a.horns!,
      ?a.parents,
      if ((a.camp ?? '').isNotEmpty) 'camp ${a.camp}',
    ].join(' · ');
    final tile = ListTile(
      leading: _photo(a.photo, 52, 52, focus: a.focus),
      title: Row(children: [
        Flexible(child: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w700))),
        if (a.onFarm && (a.owner ?? '').isNotEmpty && a.owner != 'Nanini') ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(border: Border.all(color: NaniniColors.amber), borderRadius: BorderRadius.circular(4)),
            child: Text(a.owner!, style: const TextStyle(fontSize: 11, color: NaniniColors.amber)),
          ),
        ],
        // East African or a cross: outside the African breeding plan.
        if (a.notAfrican) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(border: Border.all(color: NaniniColors.muted), borderRadius: BorderRadius.circular(4)),
            child: Text(a.subspecies!.startsWith('Cross') ? 'Cross' : a.subspecies!, style: const TextStyle(fontSize: 11, color: NaniniColors.muted)),
          ),
        ],
      ]),
      subtitle: Text(line),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => runOnce('bloodline.animal', () => _details(context, a, animals, events)),
    );
    return flat ? tile : Card(child: tile);
  }

  Future<void> _details(BuildContext context, GameAnimal a, List<GameAnimal> animals, List<GameEvent> events) {
    final parents = parentsByTag(animals, events);
    final byTag = {for (final x in animals) x.tag: x};
    final camp = currentCampFor(a.tag, events) ?? a.camp;
    final calves = a.sex == 'F' ? calvesOf(a, animals, events) : const <GameAnimal>[];
    String? day(String? d) => d == null || d.length != 10 ? d : fmtDateDisplay(d);
    Widget row(String label, String? v) => (v ?? '').isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 92, child: Text(label, style: const TextStyle(color: NaniniColors.muted))),
              Expanded(child: Text(v!)),
            ]),
          );
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            if (a.photo != null && _urls[a.photo] != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 3 / 2,
                  child: Image.network(_urls[a.photo]!, fit: BoxFit.cover, alignment: Alignment(a.focus.$1, a.focus.$2)),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Expanded(child: Text(a.label, style: Theme.of(ctx).textTheme.titleLarge)),
              if (a.onFarm)
                IconButton(
                  tooltip: 'Bloodline page (PDF to print or send)',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () {
                    Navigator.pop(ctx);
                    runOnce('bloodline.page', () => _showBook(context, animals, only: a));
                  },
                ),
              if (a.id != null && a.photo != null && _urls[a.photo] != null)
                IconButton(
                  tooltip: 'Where is the head? (the photo is cropped around it)',
                  icon: const Icon(Icons.center_focus_strong_outlined),
                  onPressed: () {
                    Navigator.pop(ctx);
                    runOnce('bloodline.focus', () => _setFocus(context, a, Image.network(_urls[a.photo]!).image));
                  },
                ),
              if (a.id != null)
                IconButton(
                  tooltip: a.photo == null ? 'Add a photo' : 'Change the photo',
                  icon: const Icon(Icons.add_a_photo_outlined),
                  onPressed: () {
                    Navigator.pop(ctx);
                    runOnce('bloodline.photo', () => _changePhoto(context, a));
                  },
                ),
              IconButton(
                tooltip: 'Change',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {
                  Navigator.pop(ctx);
                  runOnce('bloodline.edit', () => _edit(context, a));
                },
              ),
            ]),
            row('Sex', switch (a.sex) { 'F' => 'Female', 'M' => 'Male', _ => 'Not known yet' }),
            row('Born', day(a.born)),
            row('Subspecies', a.subspecies),
            row('Bloodline', a.bloodline),
            row('Owner', a.onFarm ? a.owner : 'Not on the farm (ancestor)'),
            row('Status', a.isAlive ? null : (a.status == 'dead' ? 'Died' : 'Sold')),
            row('Sire', a.sire),
            row('Dam', a.dam),
            row('Spread', a.horns),
            row('SCI', a.sci),
            row('Measured', day(a.measured)),
            row('In calf to', a.inCalfTo),
            row('Camp', camp),
            row('Microchip', a.microchip),
            row('DNA', a.dna),
            row('Source', a.source),
            row('Notes', a.notes),
            if (calves.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Calves (${calves.length})', style: Theme.of(ctx).textTheme.titleMedium),
              for (final c in calves)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _photo(c.photo, 44, 44, radius: 6, focus: c.focus),
                  title: Text(c.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    if ((c.born ?? '').isNotEmpty) 'born ${c.born!.length == 4 ? c.born : fmtDateDisplay(c.born!)}',
                    if ((c.sire ?? '').isNotEmpty) 'by ${c.sire}',
                    switch (c.sex) { 'F' => 'heifer', 'M' => 'bull', _ => null },
                    if (!c.isAlive) c.status == 'dead' ? 'died' : 'sold',
                    if (c.isAlive && !c.onFarm) 'not on the farm',
                  ].nonNulls.join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Straight on (this page's own runOnce is still open).
                    Navigator.pop(ctx);
                    _details(context, c, animals, events);
                  },
                ),
            ],
            const SizedBox(height: 12),
            Text('Family tree', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ancestryTile(ctx, a.tag, parents, byTag, events, depth: 0, seen: {}),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, GameAnimal? a) async {
    final tag = TextEditingController(text: a?.tag);
    final name = TextEditingController(text: a?.name);
    final born = TextEditingController(text: a?.born);
    final ownerCtl = TextEditingController(text: a?.owner ?? (a == null ? 'Nanini' : null));
    final sire = TextEditingController(text: a?.sire);
    final dam = TextEditingController(text: a?.dam);
    final horns = TextEditingController(text: a?.horns);
    final chip = TextEditingController(text: a?.microchip);
    final notes = TextEditingController(text: a?.notes);
    final campCtl = TextEditingController(text: a?.camp);
    final subspecies = TextEditingController(text: a?.subspecies ?? (a == null ? 'African' : null));
    final bloodline = TextEditingController(text: a?.bloodline);
    final sci = TextEditingController(text: a?.sci);
    final measured = TextEditingController(text: a?.measured);
    final inCalf = TextEditingController(text: a?.inCalfTo);
    final source = TextEditingController(text: a?.source);
    final dna = TextEditingController(text: a?.dna);
    var sex = a?.sex;
    var status = a?.status ?? 'alive';
    var onFarm = a?.onFarm ?? true;
    String? error;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(a == null ? 'Add an animal' : 'Change ${a.label}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(controller: tag, decoration: const InputDecoration(labelText: 'Tag')),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name (optional)')),
                DropdownButtonFormField<String?>(
                  initialValue: sex,
                  decoration: const InputDecoration(labelText: 'Sex'),
                  items: const [
                    DropdownMenuItem(value: 'F', child: Text('Female')),
                    DropdownMenuItem(value: 'M', child: Text('Male')),
                    DropdownMenuItem(value: null, child: Text('Not known yet')),
                  ],
                  onChanged: (v) => setLocal(() => sex = v),
                ),
                TextField(controller: born, decoration: const InputDecoration(labelText: 'Born', hintText: 'A year (2019) or a date (2026-12-14)')),
                TextField(controller: sire, decoration: const InputDecoration(labelText: 'Sire (tag)')),
                TextField(controller: dam, decoration: const InputDecoration(labelText: 'Dam (tag)')),
                TextField(controller: subspecies, decoration: const InputDecoration(labelText: 'Subspecies', hintText: 'African, East African, or a cross')),
                TextField(controller: bloodline, decoration: const InputDecoration(labelText: 'Bloodline')),
                TextField(controller: horns, decoration: const InputDecoration(labelText: 'Spread (RW)', hintText: 'e.g. 30 4/8"')),
                TextField(controller: sci, decoration: const InputDecoration(labelText: 'SCI', hintText: 'e.g. 75.75 (61.75 + 7 + 7)')),
                TextField(controller: measured, decoration: const InputDecoration(labelText: 'Last measured', hintText: 'yyyy-mm-dd')),
                TextField(controller: inCalf, decoration: const InputDecoration(labelText: 'In calf to')),
                TextField(controller: campCtl, decoration: const InputDecoration(labelText: 'Camp')),
                TextField(controller: chip, decoration: const InputDecoration(labelText: 'Microchip')),
                TextField(controller: dna, decoration: const InputDecoration(labelText: 'DNA lab no')),
                TextField(controller: source, decoration: const InputDecoration(labelText: 'Source', hintText: 'Auction and lot, or Bred on farm')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('On the farm'),
                  subtitle: const Text('Off: an ancestor known from the pedigrees'),
                  value: onFarm,
                  onChanged: (v) => setLocal(() => onFarm = v),
                ),
                if (onFarm) TextField(controller: ownerCtl, decoration: const InputDecoration(labelText: 'Owner', hintText: 'Nanini, or who owns it')),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'alive', child: Text('Alive')),
                    DropdownMenuItem(value: 'dead', child: Text('Died')),
                    DropdownMenuItem(value: 'sold', child: Text('Sold')),
                  ],
                  onChanged: (v) => setLocal(() => status = v ?? status),
                ),
                TextField(controller: notes, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Notes')),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: NaniniColors.red))),
              ]),
            ),
          ),
          actions: [
            if (a?.id != null) TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Delete', style: TextStyle(color: NaniniColors.red))),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (tag.text.trim().isEmpty) {
                  setLocal(() => error = 'Enter the tag.');
                  return;
                }
                Navigator.pop(ctx, 'save');
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      if (action == 'delete') {
        if (!await confirmDialog(context, message: 'Delete ${a!.label} from the register?', danger: true)) return;
        await widget.repo.deleteAnimal(a.id!);
        if (context.mounted) showToast(context, 'Deleted');
        return;
      }
      await widget.repo.saveAnimal(GameAnimal(
        id: a?.id,
        species: widget.species,
        tag: tag.text.trim(),
        name: v(name),
        sex: sex,
        born: v(born),
        owner: onFarm ? v(ownerCtl) : null,
        onFarm: onFarm,
        status: status,
        sire: v(sire),
        dam: v(dam),
        horns: v(horns),
        microchip: v(chip),
        camp: v(campCtl),
        subspecies: v(subspecies),
        bloodline: v(bloodline),
        sci: v(sci),
        measured: v(measured),
        inCalfTo: v(inCalf),
        source: v(source),
        dna: v(dna),
        notes: v(notes),
      ));
      if (context.mounted) showToast(context, 'Saved');
    } catch (e) {
      if (context.mounted) showToast(context, 'Could not save: $e', isError: true);
    }
  }

  /// The bloodline book of the herd shown (or one animal's page), to print or send.
  Future<void> _showBook(BuildContext context, List<GameAnimal> animals, {GameAnimal? only}) => showPdfPreview(
        context,
        () => buildBloodlineBook(
          owner: only?.owner ?? book,
          animals: animals,
          only: only,
          photo: (path) => widget.repo.downloadPhoto(path).then<Uint8List?>((b) => b, onError: (_) => null),
        ),
        landscape: true,
        title: only != null ? 'Bloodline ${only.tag}' : '${bookName(book)} buffalo bloodlines',
      );

  /// A photo's width and height (read from its header, not decoded).
  static Future<(int, int)> _size(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final d = await ui.ImageDescriptor.encoded(buffer);
    final size = (d.width, d.height);
    d.dispose();
    buffer.dispose();
    return size;
  }

  /// One photo: on a phone taken or chosen there (shrunk to 1800 px), on a
  /// PC picked from a file. (bytes, extension), or null.
  Future<(Uint8List, String)?> _pickOne(BuildContext context) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (ctx) => SimpleDialog(title: const Text('Photo'), children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ImageSource.camera), child: const Text('Take a photo')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ImageSource.gallery), child: const Text('Choose from the phone')),
        ]),
      );
      if (source == null) return null;
      final shot = await ImagePicker().pickImage(source: source, maxWidth: 1800, maxHeight: 1800, imageQuality: 82);
      return shot == null ? null : (await shot.readAsBytes(), 'jpg');
    }
    final f = (await FilePicker.platform.pickFiles(type: FileType.image, withData: true))?.files.firstOrNull;
    if (f == null) return null;
    final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    if (bytes == null) throw StateError('Could not read that file.');
    return (bytes, f.extension ?? 'jpg');
  }

  /// One animal's photo: a new one (kept with its earlier ones; it becomes
  /// the book's photo when good enough), or take the current one off.
  Future<void> _changePhoto(BuildContext context, GameAnimal a) async {
    var remove = false;
    if (a.photo != null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(title: Text('Photo of ${a.label}'), children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'new'), child: const Text('Add a newer photo')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'remove'), child: const Text('Remove this photo', style: TextStyle(color: NaniniColors.red))),
        ]),
      );
      if (choice == null) return;
      remove = choice == 'remove';
    }
    try {
      if (remove) {
        await widget.repo.removePhoto(a);
        if (context.mounted) showToast(context, 'Photo removed');
        return;
      }
      if (!context.mounted) return;
      final picked = await _pickOne(context);
      if (picked == null) return;
      final (w, h) = await _size(picked.$1);
      final used = await widget.repo.addPhoto(widget.species, a.tag, picked.$1, width: w, height: h, id: a.id, current: a.photo, extension: picked.$2);
      if (!context.mounted) return;
      if (used) {
        showToast(context, 'Photo saved');
        // Head and horns first: where is the head on it?
        if (a.id != null) await _setFocus(context, a, MemoryImage(picked.$1));
      } else if (await confirmDialog(context,
              title: 'Lower quality',
              message: 'This photo ($w × $h) is smaller than the current one, so the book keeps the current one. It is saved with the animal\'s other photos. Use it anyway?',
              confirmLabel: 'Use it')) {
        final latest = await widget.repo.latestPhoto(widget.species, a.tag);
        if (latest != null) await widget.repo.usePhoto(widget.species, a.tag, latest, id: a.id);
        if (context.mounted) showToast(context, 'Photo saved');
      }
    } catch (e) {
      if (context.mounted) showToast(context, 'Could not save the photo: $e', isError: true);
    }
  }

  /// Where the head is on [a]'s photo ([image]): tapped on the photo, it's
  /// the centre every crop of it keeps (head and horns first, then as much
  /// of the body as fits).
  Future<void> _setFocus(BuildContext context, GameAnimal a, ImageProvider image) async {
    // The tap, as a fraction of the photo (0..1 across and down).
    var at = a.focusX == null ? null : Offset((a.focus.$1 + 1) / 2, (a.focus.$2 + 1) / 2);
    final focus = await showDialog<Offset>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Tap the head of ${a.label}'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Photos are cropped around it, so the head and horns always show, and as much of the body as fits.',
                  style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
              const SizedBox(height: 8),
              Flexible(
                child: Builder(
                  builder: (pic) => GestureDetector(
                    onTapDown: (d) {
                      final size = (pic.findRenderObject() as RenderBox).size;
                      setLocal(() => at = Offset((d.localPosition.dx / size.width).clamp(0, 1), (d.localPosition.dy / size.height).clamp(0, 1)));
                    },
                    child: Stack(children: [
                      Image(
                        image: image,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox(height: 120, child: Center(child: Text('The photo could not be loaded'))),
                      ),
                      if (at != null)
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment(at!.dx * 2 - 1, at!.dy * 2 - 1),
                            child: const Icon(Icons.add_circle_outline, size: 36, color: NaniniColors.rust),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Skip')),
            FilledButton(onPressed: at == null ? null : () => Navigator.pop(ctx, at), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (focus == null || a.id == null) return;
    try {
      await widget.repo.setFocus(a.id!, focus.dx * 2 - 1, focus.dy * 2 - 1);
      if (context.mounted) showToast(context, 'Head marked: photos are cropped around it');
    } catch (e) {
      if (context.mounted) showToast(context, 'Could not save it: $e', isError: true);
    }
  }

  /// Many photos at once: each file named by the animal's tag ("PO20.jpg",
  /// "Tag 65.jpg"). A tag not in the register yet is added as an ancestor;
  /// an animal with a photo gets the new one only when it's good enough.
  Future<void> _addPhotos(BuildContext context, List<GameAnimal> animals) async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    final files = picked?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    final byTag = {for (final a in animals) a.tag.toLowerCase(): a};
    var done = 0, added = 0, kept = 0;
    final failed = <String>[];
    setState(() => _adding = '0 of ${files.length}');
    for (final f in files) {
      final tag = f.name.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
      final a = byTag[tag.toLowerCase()];
      try {
        final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
        if (bytes == null) throw StateError('could not read it');
        final (w, h) = await _size(bytes);
        final used = await widget.repo.addPhoto(widget.species, a?.tag ?? tag, bytes,
            width: w, height: h, id: a?.id, current: a?.photo, extension: f.extension ?? 'jpg');
        if (a == null) added++;
        if (!used) kept++;
      } catch (e) {
        failed.add(f.name);
        debugPrint('photo ${f.name}: $e');
      }
      done++;
      if (mounted) setState(() => _adding = '$done of ${files.length}');
    }
    if (mounted) setState(() => _adding = null);
    if (!context.mounted) return;
    showToast(
      context,
      [
        '${files.length - failed.length} photos saved',
        if (added > 0) '$added new ancestors added',
        if (kept > 0) '$kept kept their better current photo',
        if (failed.isNotEmpty) 'not saved: ${failed.join(', ')}',
      ].join(' · '),
      isError: failed.isNotEmpty,
    );
  }

  // --- Mating guide ---

  Widget _mating(BuildContext context, List<GameAnimal> animals) {
    return FutureBuilder<List<GameMating>>(
      future: _matings,
      builder: (context, snap) {
        if (snap.hasError) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Could not load the mating guide: ${snap.error}', style: const TextStyle(color: NaniniColors.red)),
            TextButton(onPressed: () => setState(() => _matings = widget.repo.fetchMatings(widget.species)), child: const Text('Try again')),
          ]);
        }
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        final matings = snap.data!;
        if (matings.isEmpty) return const Text('No matings worked out yet.');
        final byTag = {for (final a in animals) a.tag: a};
        final bulls = {for (final m in matings) m.bullTag}.toList();
        // This book's cows (all of them before the register has owners).
        final cows = {for (final m in matings) if (animals.isEmpty || byTag[m.cowTag]?.owner == book) m.cowTag}.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        if (cows.isEmpty) return Text('No matings worked out for ${bookName(book)}\'s cows yet.');
        Color tone(String advice) => switch (advice) { 'best' => NaniniColors.green, 'avoid' => NaniniColors.red, _ => NaniniColors.amber };
        String word(String advice) => switch (advice) { 'best' => 'Best', 'avoid' => 'Avoid', _ => 'Acceptable' };
        String pct(double v) => v == 0 ? '0%' : '${v.toStringAsFixed(1)}%';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("The calf's inbreeding (Wright's F) for each cow × bull: how much of the calf's genetics is doubled up from shared ancestors.",
              style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final (c, t) in [
                  (NaniniColors.green, '0%: outcross. Below 6.25%: mild line-breeding, acceptable.'),
                  (NaniniColors.amber, '6.25–12.5%: close line-breeding; use deliberately, not as a routine.'),
                  (NaniniColors.red, 'Above 12.5%: inbreeding, avoid (12.5% = half-brother × half-sister; 25% = father × daughter).'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(padding: const EdgeInsets.only(top: 4), child: Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle))),
                      const SizedBox(width: 8),
                      Expanded(child: Text(t, style: const TextStyle(fontSize: 12))),
                    ]),
                  ),
              ]),
            ),
          ),
          for (final cow in cows) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(byTag[cow]?.label ?? cow, style: const TextStyle(fontWeight: FontWeight.w700))),
                    if ((byTag[cow]?.owner ?? '').isNotEmpty) Text(byTag[cow]!.owner!, style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                  ]),
                  if (byTag[cow]?.parents != null) Text(byTag[cow]!.parents!, style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  for (final bull in bulls)
                    if (matings.where((m) => m.cowTag == cow && m.bullTag == bull).firstOrNull case final m?)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Expanded(flex: 3, child: Text(byTag[bull]?.label ?? bull)),
                          Expanded(flex: 2, child: Text(pct(m.calfInbreeding), textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, color: tone(m.advice)))),
                          const SizedBox(width: 10),
                          SizedBox(width: 84, child: Text(word(m.advice) + ((m.note ?? '').isEmpty ? '' : ' *'), style: TextStyle(color: tone(m.advice)))),
                        ]),
                      ),
                  for (final m in matings.where((m) => m.cowTag == cow && (m.note ?? '').isNotEmpty))
                    Text('* ${byTag[m.bullTag]?.label ?? m.bullTag}: ${m.note}', style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                  if (matings.where((m) => m.cowTag == cow && (m.shared ?? '').isNotEmpty).firstOrNull case final m?)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Shared ancestors: ${m.shared}', style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                    ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
              'Unknown ancestors are taken as unrelated: where a sire or dam is not known the line stops there, so the true figures can only be higher. '
              'Sires worked out from the tag letters are marked in the herd (to confirm).',
              style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
        ]);
      },
    );
  }

  // --- Family tree ---

  List<Widget> _tree(BuildContext context, List<GameAnimal> animals, List<GameEvent> events) {
    final parents = parentsByTag(animals, events);
    final byTag = {for (final a in animals) a.tag: a};
    // This book's animals and everything behind them; births logged here
    // (with their parents) go in our own book. Before the register: every tag.
    final mine = animals.where((a) => a.onFarm && a.owner == book).toList();
    final born = [for (final t in parents.keys) if (!byTag.containsKey(t)) t];
    final allTags = <String>{
      if (animals.isEmpty) ...[
        ...parents.keys,
        for (final (s, d) in parents.values) ...[if ((s ?? '').isNotEmpty) s!, if ((d ?? '').isNotEmpty) d!],
      ] else ...[
        for (final a in mine) a.tag,
        ...ancestorTags(mine, byTag),
        if (book == 'Nanini')
          for (final t in born) ...[t, if ((parents[t]!.$1 ?? '').isNotEmpty) parents[t]!.$1!, if ((parents[t]!.$2 ?? '').isNotEmpty) parents[t]!.$2!],
      ],
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (selectedTag != null && !allTags.contains(selectedTag)) selectedTag = null;
    selectedTag ??= allTags.isNotEmpty ? allTags.first : null;
    if (allTags.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('No tagged animals yet -- add one to the herd, or log a birth with a tag number.'),
        ),
      ];
    }
    return [
      DropdownButtonFormField<String>(
        initialValue: selectedTag,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Animal (tag number)'),
        items: allTags.map((t) => DropdownMenuItem(value: t, child: Text(byTag[t]?.label ?? t))).toList(),
        onChanged: (v) => setState(() => selectedTag = v),
      ),
      const SizedBox(height: 20),
      _ancestryTile(context, selectedTag!, parents, byTag, events, depth: 0, seen: {}),
    ];
  }

  /// Recurses through each animal's sire and dam (the register's, or its
  /// logged birth's). `seen` guards against a bad data loop (e.g. an animal
  /// accidentally listed as its own ancestor) feeding back into itself forever.
  Widget _ancestryTile(BuildContext context, String tag, Map<String, (String?, String?)> parents, Map<String, GameAnimal> byTag, List<GameEvent> events,
      {required int depth, required Set<String> seen}) {
    final birth = events.where((e) => e.eventType == GameEventType.birth && e.tagNumber == tag).firstOrNull;
    final animal = byTag[tag];
    final (sire, dam) = parents[tag] ?? (null, null);
    final alreadySeen = seen.contains(tag);
    final nextSeen = {...seen, tag};
    final camp = currentCampFor(tag, events);
    final born = birth != null ? fmtDateDisplay(birth.eventDate) : animal?.born;
    final details = [if ((animal?.horns ?? '').isNotEmpty) animal!.horns!, if (camp != null) 'Camp: $camp'].join(' · ');

    return Padding(
      padding: EdgeInsets.only(left: depth == 0 ? 0 : 16.0, top: depth == 0 ? 0 : 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _photo(animal?.photo, 48, 34, radius: 6, focus: animal?.focus ?? (0, -0.25)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(animal?.label ?? tag, style: const TextStyle(fontWeight: FontWeight.w700))),
                  if ((born ?? '').isNotEmpty) Text(born!, style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                ],
              ),
              if (details.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(details, style: const TextStyle(color: NaniniColors.muted, fontSize: 12))),
              if (alreadySeen)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Already shown above (circular record).', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
                )
              else if ((sire ?? '').isEmpty && (dam ?? '').isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('No parents recorded.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
                )
              else ...[
                if ((sire ?? '').isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.only(top: 8, bottom: 2), child: Text('Sire', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  _ancestryTile(context, sire!, parents, byTag, events, depth: depth + 1, seen: nextSeen),
                ],
                if ((dam ?? '').isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.only(top: 8, bottom: 2), child: Text('Dam', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  _ancestryTile(context, dam!, parents, byTag, events, depth: depth + 1, seen: nextSeen),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
