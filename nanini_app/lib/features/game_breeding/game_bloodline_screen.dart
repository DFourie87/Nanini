import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'game_breeding_models.dart';
import 'game_breeding_repository.dart';

enum _View { herd, mating, tree }

/// Bloodline: the herd register (every animal with its parents, born,
/// horns, microchip and owner), the mating guide (each cow × bull: the
/// calf's inbreeding and best / acceptable / avoid) and an animal's family
/// tree -- from the register and the births logged here.
class GameBloodlineScreen extends StatefulWidget {
  const GameBloodlineScreen({super.key, required this.repo, required this.species});
  final GameBreedingRepository repo;
  final String species;

  @override
  State<GameBloodlineScreen> createState() => _GameBloodlineScreenState();
}

class _GameBloodlineScreenState extends State<GameBloodlineScreen> {
  _View view = _View.herd;
  String? selectedTag;

  /// Herd: all, or one owner's animals.
  String? owner;
  late final Stream<List<GameAnimal>> _animals = widget.repo.watchAnimals(widget.species);
  late final Stream<List<GameEvent>> _events = widget.repo.watchEvents();
  late Future<List<GameMating>> _matings = widget.repo.fetchMatings(widget.species);

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
          final events = (eventSnap.data ?? const <GameEvent>[]).where((e) => e.species == widget.species).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<_View>(
                segments: const [
                  ButtonSegment(value: _View.herd, label: Text('Herd')),
                  ButtonSegment(value: _View.mating, label: Text('Mating guide')),
                  ButtonSegment(value: _View.tree, label: Text('Family tree')),
                ],
                selected: {view},
                onSelectionChanged: (s) => setState(() => view = s.first),
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
              ),
              const SizedBox(height: 16),
              if (missing && view != _View.tree)
                const Text('Run game_animals.sql in Supabase first.', style: TextStyle(color: NaniniColors.red))
              else
                ...switch (view) {
                  _View.herd => _herd(context, animals, events),
                  _View.mating => [_mating(context, animals)],
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
    final owners = {for (final a in animals) if (a.onFarm && (a.owner ?? '').isNotEmpty) a.owner!}.toList()..sort();
    final onFarm = animals.where((a) => a.onFarm && (owner == null || a.owner == owner)).toList();
    final alive = onFarm.where((a) => a.isAlive).toList();
    final groups = [
      ('Cows', alive.where((a) => a.sex == 'F').toList()),
      ('Bulls', alive.where((a) => a.sex == 'M').toList()),
      ('Calves (sex not known yet)', alive.where((a) => a.sex == null).toList()),
      ('Died or sold', onFarm.where((a) => !a.isAlive).toList()),
    ];
    final ancestors = animals.where((a) => !a.onFarm).toList();
    return [
      Row(children: [
        Expanded(
          child: Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('All'), selected: owner == null, onSelected: (_) => setState(() => owner = null)),
            for (final o in owners) ChoiceChip(label: Text(o), selected: owner == o, onSelected: (_) => setState(() => owner = o)),
          ]),
        ),
        IconButton(
          tooltip: 'Add an animal',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => runOnce('bloodline.add', () => _edit(context, null)),
        ),
      ]),
      const SizedBox(height: 4),
      Text('${alive.length} on the farm', style: const TextStyle(color: NaniniColors.muted)),
      if (animals.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No animals in the register yet.')),
      for (final (title, list) in groups)
        if (list.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('$title (${list.length})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final a in list) _animalTile(context, a, animals, events),
        ],
      if (ancestors.isNotEmpty && owner == null) ...[
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
      switch (a.sex) { 'F' => '♀', 'M' => '♂', _ => '?' },
      if ((a.born ?? '').isNotEmpty) 'born ${a.born!.length == 4 ? a.born : fmtDateDisplay(a.born!)}',
      if ((a.horns ?? '').isNotEmpty) a.horns!,
      ?a.parents,
      if ((a.camp ?? '').isNotEmpty) 'camp ${a.camp}',
    ].join(' · ');
    final tile = ListTile(
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
            Row(children: [
              Expanded(child: Text(a.label, style: Theme.of(ctx).textTheme.titleLarge)),
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
        final cows = {for (final m in matings) m.cowTag}.toList()
          ..sort((a, b) {
            final oa = byTag[a]?.owner ?? '', ob = byTag[b]?.owner ?? '';
            // Our cows first, then those kept for others.
            if (oa != ob) return oa == 'Nanini' ? -1 : (ob == 'Nanini' ? 1 : oa.compareTo(ob));
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
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
    // Every tag that's ever appeared: in the register, born here, or as a parent.
    final allTags = <String>{
      for (final a in animals) a.tag,
      ...parents.keys,
      for (final (s, d) in parents.values) ...[if ((s ?? '').isNotEmpty) s!, if ((d ?? '').isNotEmpty) d!],
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
                  const Icon(Icons.pets_outlined, size: 18, color: NaniniColors.rustDark),
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
