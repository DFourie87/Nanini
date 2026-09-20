import 'package:flutter/material.dart';
import '../../core/widgets/nanini_app_bar.dart';

class GameBreedingHomeScreen extends StatelessWidget {
  const GameBreedingHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Game Breeding'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SpeciesButton(species: 'Buffalo', icon: Icons.pets_outlined),
            const SizedBox(height: 20),
            _SpeciesButton(species: 'Sable', icon: Icons.pets_outlined),
          ],
        ),
      ),
    );
  }
}

class _SpeciesButton extends StatelessWidget {
  const _SpeciesButton({required this.species, required this.icon});
  final String species;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: FilledButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GameSpeciesHomeScreen(species: species)),
        ),
        icon: Icon(icon),
        label: Text(species, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}

/// One subcategory app per species (Buffalo, Sable). Breeding-record
/// features are still to be defined -- this is the landing screen each
/// species button opens into.
class GameSpeciesHomeScreen extends StatelessWidget {
  const GameSpeciesHomeScreen({super.key, required this.species});
  final String species;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NaniniAppBar(title: species),
      body: Center(
        child: Text('$species breeding records coming soon.', style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
