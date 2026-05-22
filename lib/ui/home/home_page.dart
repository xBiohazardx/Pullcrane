import 'package:flutter/material.dart';
import 'package:pullcrane/data/app_repositories.dart';
import 'package:pullcrane/domain/models/app_settings.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/models/workout.dart';
import 'package:pullcrane/ui/workouts/active_workout_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Workout> workouts = <Workout>[];
  List<Exercise> exercises = <Exercise>[];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<Workout> loadedWorkouts = await AppRepositories.workouts.listWorkouts();
    final List<Exercise> loadedExercises = await AppRepositories.exercises.listExercises();

    if (!mounted) {
      return;
    }

    setState(() {
      workouts = loadedWorkouts;
      exercises = loadedExercises;
      isLoading = false;
    });
  }

  Future<void> _startWorkout(Workout workout) async {
    // Home tab is kept alive in IndexedStack, so refresh before start to avoid stale exercise data.
    final List<Exercise> latestExercises =
        await AppRepositories.exercises.listExercises();
    final List<Workout> latestWorkouts =
        await AppRepositories.workouts.listWorkouts();
    final AppSettings settings = await AppRepositories.settings.load();

    final Workout workoutToStart = latestWorkouts
        .where((item) => item.id == workout.id)
        .cast<Workout?>()
        .firstWhere((item) => item != null, orElse: () => workout)!;

    final Map<String, Exercise> byId = <String, Exercise>{
      for (final Exercise exercise in latestExercises) exercise.id: exercise,
    };

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutPage(
          workout: workoutToStart,
          exercisesById: byId,
          forceThresholdKg: settings.forceThresholdKg,
          targetHysteresisKg: settings.targetHysteresisKg,
          userMaxLiftKg: settings.userMaxLiftKg,
          enableTargetHaptics: settings.enableTargetHaptics,
          requireZeroBeforeSetStart: settings.requireZeroBeforeSetStart,
        ),
      ),
    );

    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : workouts.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 160),
                      Center(child: Text('No workouts found. Create one first.')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: workouts.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final Workout workout = workouts[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                workout.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text('${workout.entries.length} exercise entries'),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.icon(
                                  onPressed: () => _startWorkout(workout),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Start workout'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}


