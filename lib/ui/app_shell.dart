import 'package:flutter/material.dart';
import 'benchmark/benchmark_page.dart';
import 'exercises/exercises_page.dart';
import 'home/home_page.dart';
import 'settings/settings_page.dart';
import 'workouts/workouts_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int currentIndex = 0;
  int homeRefreshTick = 0;
  int settingsRefreshTick = 0;

  List<Widget> get pages => <Widget>[
    HomePage(key: ValueKey<int>(homeRefreshTick)),
    const WorkoutsPage(),
    const ExercisesPage(),
    const BenchmarkPage(),
    SettingsPage(key: ValueKey<int>(settingsRefreshTick)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            if (index == 0) {
              homeRefreshTick++;
            }
            if (index == 4) {
              settingsRefreshTick++;
            }
            currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Workouts',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Exercises',
          ),
          NavigationDestination(
            icon: Icon(Icons.speed_outlined),
            selectedIcon: Icon(Icons.speed),
            label: 'Benchmark',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
