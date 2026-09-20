import 'package:flutter/material.dart';
import '../../theme/nanini_theme.dart';
import 'game_breeding_models.dart';
import 'game_breeding_repository.dart';

class GameOverviewScreen extends StatelessWidget {
  const GameOverviewScreen({super.key, required this.repo, required this.species});
  final GameBreedingRepository repo;
  final String species;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GameEvent>>(
      stream: repo.watchEvents(),
      builder: (context, snap) {
        final events = (snap.data ?? []).where((e) => e.species == species).toList();

        final counts = {for (final t in GameEventType.values) t: events.where((e) => e.eventType == t).length};
        final headcount =
            (counts[GameEventType.birth] ?? 0) + (counts[GameEventType.purchase] ?? 0) - (counts[GameEventType.death] ?? 0) - (counts[GameEventType.sale] ?? 0);

        final weighings = events.where((e) => e.eventType == GameEventType.weighing && e.weightKg != null).toList();
        final avgWeight = weighings.isEmpty ? null : weighings.fold<double>(0, (s, e) => s + e.weightKg!) / weighings.length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text('Current headcount', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: NaniniColors.muted)),
                    const SizedBox(height: 6),
                    Text('$headcount', style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: NaniniColors.rustDark)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('By event type', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final t in GameEventType.values) _row(gameEventTypeLabel(t), '${counts[t] ?? 0}'),
                    if (avgWeight != null) ...[
                      const Divider(),
                      _row('Avg. weight (weighings)', '${avgWeight.toStringAsFixed(1)} kg'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Total events: ${events.length}', style: const TextStyle(color: NaniniColors.muted)),
          ],
        );
      },
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}
