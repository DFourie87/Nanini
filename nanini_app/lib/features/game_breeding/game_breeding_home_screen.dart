import 'package:flutter/material.dart';
import '../../core/widgets/nanini_app_bar.dart';
import 'game_bloodline_screen.dart';
import 'game_breeding_repository.dart';
import 'game_log_screen.dart';
import 'game_overview_screen.dart';

/// The Buffalo app: Overview, Log, and Bloodline tabs against the
/// game_events table (filtered to species 'Buffalo').
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
