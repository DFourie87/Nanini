import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import 'game_breeding_models.dart';
import 'game_breeding_repository.dart';

class GameBloodlineScreen extends StatefulWidget {
  const GameBloodlineScreen({super.key, required this.repo, required this.species});
  final GameBreedingRepository repo;
  final String species;

  @override
  State<GameBloodlineScreen> createState() => _GameBloodlineScreenState();
}

class _GameBloodlineScreenState extends State<GameBloodlineScreen> {
  String? selectedTag;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GameEvent>>(
      stream: widget.repo.watchEvents(),
      builder: (context, snap) {
        final events = (snap.data ?? []).where((e) => e.species == widget.species).toList();

        // Every tag that's ever appeared, as an animal, a sire or a dam --
        // births carry a known date and parents, the rest are placeholders
        // for animals whose birth was never logged here.
        final births = {for (final e in events) if (e.eventType == GameEventType.birth && (e.tagNumber ?? '').isNotEmpty) e.tagNumber!: e};
        final allTags = <String>{
          ...births.keys,
          for (final e in events) ...[
            if ((e.sireTag ?? '').isNotEmpty) e.sireTag!,
            if ((e.damTag ?? '').isNotEmpty) e.damTag!,
          ],
        }.toList()
          ..sort();

        if (selectedTag != null && !allTags.contains(selectedTag)) selectedTag = null;
        selectedTag ??= allTags.isNotEmpty ? allTags.first : null;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Bloodline', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (allTags.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No tagged animals yet -- log a birth with a tag number to start building a bloodline.'),
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: selectedTag,
                decoration: const InputDecoration(labelText: 'Animal (tag number)'),
                items: allTags.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => selectedTag = v),
              ),
              const SizedBox(height: 20),
              _ancestryTile(context, selectedTag!, births, events, depth: 0, seen: {}),
            ],
          ],
        );
      },
    );
  }

  /// Recurses through sire/dam tags found on each animal's own birth event.
  /// `seen` guards against a bad data loop (e.g. an animal accidentally
  /// listed as its own ancestor) feeding back into itself forever.
  Widget _ancestryTile(BuildContext context, String tag, Map<String, GameEvent> births, List<GameEvent> events, {required int depth, required Set<String> seen}) {
    final birth = births[tag];
    final alreadySeen = seen.contains(tag);
    final nextSeen = {...seen, tag};
    final camp = currentCampFor(tag, events);

    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0, top: depth == 0 ? 0 : 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.pets_outlined, size: 18, color: NaniniColors.rustDark),
                  const SizedBox(width: 6),
                  Expanded(child: Text(tag, style: const TextStyle(fontWeight: FontWeight.w700))),
                  if (birth != null) Text(fmtDateDisplay(birth.eventDate), style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                ],
              ),
              if (camp != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Camp: $camp', style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                ),
              if (birth == null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('No birth record for this tag.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
                )
              else if (alreadySeen)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Already shown above (circular record).', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
                )
              else if ((birth.sireTag ?? '').isEmpty && (birth.damTag ?? '').isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('No parents recorded.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
                )
              else ...[
                if ((birth.sireTag ?? '').isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.only(top: 8, bottom: 2), child: Text('Sire', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  _ancestryTile(context, birth.sireTag!, births, events, depth: depth + 1, seen: nextSeen),
                ],
                if ((birth.damTag ?? '').isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.only(top: 8, bottom: 2), child: Text('Dam', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  _ancestryTile(context, birth.damTag!, births, events, depth: depth + 1, seen: nextSeen),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
