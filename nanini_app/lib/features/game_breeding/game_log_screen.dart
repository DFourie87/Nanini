import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'game_breeding_models.dart';
import 'game_breeding_repository.dart';
import '../../core/run_once.dart';

class GameLogScreen extends StatefulWidget {
  const GameLogScreen({super.key, required this.repo, required this.species});
  final GameBreedingRepository repo;
  final String species;

  @override
  State<GameLogScreen> createState() => _GameLogScreenState();
}

class _GameLogScreenState extends State<GameLogScreen> {
  final tagCtrl = TextEditingController();
  final weightCtrl = TextEditingController();
  final sireCtrl = TextEditingController();
  final damCtrl = TextEditingController();
  final campCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  GameEventType eventType = GameEventType.birth;
  DateTime eventDate = DateTime.now();

  /// A calf born: bull calf ('M'), heifer ('F'), or not known yet ('') --
  /// often not seen at first; set later on its card in the herd.
  String calfSex = '';

  /// The calf's tag as suggested (sire's initial + dam's tag) -- replaced
  /// when the sire or dam changes, unless typed over.
  String _suggested = '';

  /// The herd register, for the drop-downs.
  late final Stream<List<GameAnimal>> _animals = widget.repo.watchAnimals(widget.species);

  bool get _isWeighing => eventType == GameEventType.weighing;
  bool get _isBirth => eventType == GameEventType.birth;
  bool get _hasCamp => gameEventCarriesCamp(eventType);

  /// A new animal (birth, purchase): its tag is typed or assigned, not picked.
  bool get _newAnimal => eventType == GameEventType.birth || eventType == GameEventType.purchase;

  @override
  void dispose() {
    for (final c in [tagCtrl, weightCtrl, sireCtrl, damCtrl, campCtrl, notesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  /// A drop-down of [options] (value, label) that also takes typed text --
  /// e.g. an outside bull not in the herd.
  Widget _pick(String label, TextEditingController ctrl, List<(String, String)> options, {ValueChanged<String>? onChanged}) => DropdownMenu<String>(
        controller: ctrl,
        label: Text(label),
        expandedInsets: EdgeInsets.zero,
        enableFilter: true,
        requestFocusOnTap: true,
        menuHeight: 320,
        dropdownMenuEntries: [for (final (v, l) in options) DropdownMenuEntry(value: v, label: l)],
        onSelected: (v) {
          if (v != null) {
            ctrl.text = v;
            onChanged?.call(v);
          }
        },
      );

  static String _animalLabel(GameAnimal a) => [
        a.tag,
        if ((a.name ?? '').trim().isNotEmpty) a.name!.trim(),
        if (a.sex == 'M') 'bull' else if (a.sex == 'F') 'cow',
        if (!a.isAlive) a.status == 'dead' ? 'died' : 'sold',
      ].join(' · ');

  /// The calf's tag from the sire and dam picked (unless typed over).
  void _suggestTag(List<GameAnimal> herd) {
    if (!_isBirth) return;
    final next = suggestCalfTag(sire: sireCtrl.text, dam: damCtrl.text, taken: herd.map((a) => a.tag));
    if (tagCtrl.text.trim().isEmpty || tagCtrl.text.trim() == _suggested) tagCtrl.text = next;
    _suggested = next;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GameAnimal>>(
      stream: _animals,
      builder: (context, herdSnap) => StreamBuilder<List<GameEvent>>(
      stream: widget.repo.watchEvents(),
      builder: (context, snap) {
        final events = (snap.data ?? []).where((e) => e.species == widget.species).toList()
          ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
        final herd = herdSnap.data ?? const <GameAnimal>[];
        // The living ones first, then the rest (dead, sold, outside sires).
        List<(String, String)> options(bool Function(GameAnimal) keep) => [
              for (final alive in [true, false])
                for (final a in herd)
                  if (a.isAlive == alive && keep(a)) (a.tag, _animalLabel(a)),
            ];
        final camps = {for (final a in herd) if ((a.camp ?? '').trim().isNotEmpty) a.camp!.trim()}.toList()..sort();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('New event', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<GameEventType>(
              initialValue: eventType,
              decoration: const InputDecoration(labelText: 'Event type'),
              items: GameEventType.values.map((t) => DropdownMenuItem(value: t, child: Text(gameEventTypeLabel(t)))).toList(),
              onChanged: (v) => setState(() {
                eventType = v!;
                tagCtrl.clear();
                _suggested = '';
                _suggestTag(herd);
              }),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => runOnce('game_log_screen.1', () async {
                final picked = await showDatePicker(context: context, initialDate: eventDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (picked != null) setState(() => eventDate = picked);
              }),
              child: InputDecorator(decoration: const InputDecoration(labelText: 'Date'), child: Text(fmtDateDisplay(toDateStr(eventDate)))),
            ),
            const SizedBox(height: 12),
            if (_isBirth) ...[
              _pick('Dam (mother)', damCtrl, options((a) => a.sex != 'M'), onChanged: (v) => setState(() {
                final dam = herd.where((a) => a.tag == v).firstOrNull;
                // The calf starts in its mother's camp.
                if (campCtrl.text.trim().isEmpty && (dam?.camp ?? '').isNotEmpty) campCtrl.text = dam!.camp!;
                _suggestTag(herd);
              })),
              const SizedBox(height: 12),
              _pick('Sire (father)', sireCtrl, options((a) => a.sex != 'F'), onChanged: (_) => setState(() => _suggestTag(herd))),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '', label: Text('Unknown')),
                  ButtonSegment(value: 'F', label: Text('Heifer')),
                  ButtonSegment(value: 'M', label: Text('Bull calf')),
                ],
                selected: {calfSex},
                onSelectionChanged: (v) => setState(() => calfSex = v.first),
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
              ),
              const SizedBox(height: 12),
            ],
            if (_newAnimal)
              TextField(
                controller: tagCtrl,
                decoration: InputDecoration(
                  labelText: _isBirth ? "Calf's tag number" : 'Tag number',
                  helperText: _isBirth ? "Assigned: the sire's initial and the dam's tag (without her birth year) -- change it if needed" : null,
                ),
              )
            else
              _pick('Animal', tagCtrl, options((a) => true)),
            if (_isWeighing) ...[
              const SizedBox(height: 12),
              TextField(controller: weightCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (kg)')),
            ],
            if (_hasCamp) ...[
              const SizedBox(height: 12),
              _pick('Camp', campCtrl, [for (final c in camps) (c, c)]),
            ],
            const SizedBox(height: 12),
            TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => runOnce('game_log_screen.2', () => _save(herd)), child: const Text('Log event')),
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 12),
            Text('Events', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (events.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No events logged yet.'))
            else
              for (final e in events) _eventCard(context, e),
          ],
        );
      },
      ),
    );
  }

  Widget _eventCard(BuildContext context, GameEvent e) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_iconFor(e.eventType), color: NaniniColors.rustDark),
        title: Text('${gameEventTypeLabel(e.eventType)}${(e.tagNumber ?? '').isNotEmpty ? ' · ${e.tagNumber}' : ''}'),
        subtitle: Text([
          fmtDateDisplay(e.eventDate),
          if (e.weightKg != null) '${e.weightKg} kg',
          if ((e.sireTag ?? '').isNotEmpty) 'Sire: ${e.sireTag}',
          if ((e.damTag ?? '').isNotEmpty) 'Dam: ${e.damTag}',
          if ((e.camp ?? '').isNotEmpty) 'Camp: ${e.camp}',
          if ((e.notes ?? '').isNotEmpty) e.notes!,
        ].join(' · ')),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => runOnce('game_log_screen.3', () async {
            final ok = await confirmDialog(context, message: 'Delete this event?', danger: true);
            if (ok) {
              await widget.repo.deleteEvent(e.id!);
              if (context.mounted) showToast(context, 'Event deleted');
            }
          }),
        ),
      ),
    );
  }

  IconData _iconFor(GameEventType t) => switch (t) {
        GameEventType.birth => Icons.child_care,
        GameEventType.death => Icons.heart_broken_outlined,
        GameEventType.sale => Icons.sell_outlined,
        GameEventType.purchase => Icons.add_shopping_cart_outlined,
        GameEventType.weighing => Icons.monitor_weight_outlined,
        GameEventType.health => Icons.medical_services_outlined,
        GameEventType.campMove => Icons.map_outlined,
      };

  /// Logs the event, and keeps the herd up to date: a birth adds the calf
  /// (its tag, sex, birth date, sire, dam, camp); a death or sale marks the
  /// animal; a camp move puts it in the new camp.
  Future<void> _save(List<GameAnimal> herd) async {
    final tag = tagCtrl.text.trim();
    final animal = herd.where((a) => a.tag.toLowerCase() == tag.toLowerCase()).firstOrNull;
    if (_isBirth) {
      if (damCtrl.text.trim().isEmpty) return showToast(context, 'Pick the dam (mother)', isError: true);
      if (tag.isEmpty) return showToast(context, "Give the calf's tag number", isError: true);
      if (animal != null) return showToast(context, 'Tag $tag is already in the herd -- give the calf another tag', isError: true);
    } else if (eventType != GameEventType.purchase && tag.isEmpty) {
      return showToast(context, 'Pick the animal', isError: true);
    }
    final weight = _isWeighing ? parseNum(weightCtrl.text) : null;
    final camp = _hasCamp && campCtrl.text.trim().isNotEmpty ? campCtrl.text.trim() : null;
    await widget.repo.addEvent(GameEvent(
      species: widget.species,
      tagNumber: tag.isEmpty ? null : tag,
      eventType: eventType,
      eventDate: toDateStr(eventDate),
      weightKg: weight,
      sireTag: _isBirth && sireCtrl.text.trim().isNotEmpty ? sireCtrl.text.trim() : null,
      damTag: _isBirth && damCtrl.text.trim().isNotEmpty ? damCtrl.text.trim() : null,
      camp: camp,
      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
    ));
    if (_isBirth) {
      final dam = herd.where((a) => a.tag == damCtrl.text.trim()).firstOrNull;
      await widget.repo.saveAnimal(GameAnimal(
        species: widget.species,
        tag: tag,
        sex: calfSex.isEmpty ? null : calfSex,
        born: toDateStr(eventDate),
        owner: dam?.owner,
        sire: sireCtrl.text.trim().isEmpty ? null : sireCtrl.text.trim(),
        dam: damCtrl.text.trim(),
        camp: camp,
        subspecies: dam?.subspecies,
        source: 'Bred on farm',
      ));
    } else if (animal?.id != null) {
      final changes = switch (eventType) {
        GameEventType.death => {'status': 'dead'},
        GameEventType.sale => {'status': 'sold'},
        GameEventType.campMove when camp != null => {'camp': camp},
        _ => <String, dynamic>{},
      };
      if (changes.isNotEmpty) await widget.repo.updateAnimal(animal!.id!, changes);
    }
    if (!mounted) return;
    showToast(context, _isBirth ? 'Birth logged -- $tag added to the herd' : 'Event logged');
    setState(() {
      tagCtrl.clear();
      weightCtrl.clear();
      sireCtrl.clear();
      damCtrl.clear();
      campCtrl.clear();
      notesCtrl.clear();
      _suggested = '';
      calfSex = '';
      eventType = GameEventType.birth;
      eventDate = DateTime.now();
    });
  }
}
