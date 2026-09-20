import 'package:flutter/material.dart';
import '../../core/widgets/nanini_app_bar.dart';
import 'game_bloodline_screen.dart';
import 'game_breeding_repository.dart';
import 'game_log_screen.dart';
import 'game_overview_screen.dart';

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

/// One subcategory app per species (Buffalo, Sable), each with its own
/// Overview, Log, and Bloodline tabs against the shared game_events table
/// filtered by species.
class GameSpeciesHomeScreen extends StatefulWidget {
  const GameSpeciesHomeScreen({super.key, required this.species});
  final String species;

  @override
  State<GameSpeciesHomeScreen> createState() => _GameSpeciesHomeScreenState();
}

class _GameSpeciesHomeScreenState extends State<GameSpeciesHomeScreen> {
  final repo = GameBreedingRepository();
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      GameOverviewScreen(repo: repo, species: widget.species),
      GameLogScreen(repo: repo, species: widget.species),
      GameBloodlineScreen(repo: repo, species: widget.species),
    ];
    return Scaffold(
      appBar: NaniniAppBar(title: widget.species),
      body: pages[index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart_outline), label: 'Overview'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box_outlined), label: 'Log'),
          BottomNavigationBarItem(icon: Icon(Icons.account_tree_outlined), label: 'Bloodline'),
        ],
      ),
    );
  }
}
