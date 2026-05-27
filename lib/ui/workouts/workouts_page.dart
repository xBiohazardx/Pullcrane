import 'package:flutter/material.dart';
import 'package:pullcrane/data/app_stores.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/models/workout.dart';
import 'package:pullcrane/ui/workouts/workout_form_page.dart';

class WorkoutsPage extends StatefulWidget {
  const WorkoutsPage({super.key});

  @override
  State<WorkoutsPage> createState() => _WorkoutsPageState();
}

class _WorkoutsPageState extends State<WorkoutsPage> {
  List<Workout> workouts = <Workout>[];
  List<Exercise> exercises = <Exercise>[];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<Workout> loadedWorkouts = await AppStores.workouts.listWorkouts();
    final List<Exercise> loadedExercises = await AppStores.exercises.listExercises();

    if (!mounted) {
      return;
    }

    setState(() {
      workouts = loadedWorkouts;
      exercises = loadedExercises;
      isLoading = false;
    });
  }

  Future<void> _openForm({Workout? initial}) async {
    _reload();
    final Workout? result = await Navigator.of(context).push<Workout>(
      MaterialPageRoute(
        builder: (_) => WorkoutFormPage(
          initialWorkout: initial,
          availableExercises: exercises,
        ),
      ),
    );

    if (result == null) {
      return;
    }

    await AppStores.workouts.saveWorkout(result);
    await _reload();
  }

  Future<void> _deleteWorkout(Workout workout) async {
    await AppStores.workouts.deleteWorkout(workout.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workouts'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await _reload();
          _openForm();
        },
        child: const Icon(Icons.add),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : workouts.isEmpty
              ? const Center(child: Text('No workouts yet.'))
              : ListView.builder(
                  itemCount: workouts.length,
                  itemBuilder: (context, index) {
                    final Workout workout = workouts[index];
                    return ListTile(
                      title: Text(workout.name),
                      subtitle: Text('${workout.entries.length} exercise entr${workout.entries.length == 1 ? 'y' : 'ies'}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteWorkout(workout),
                      ),
                      onTap: () => _openForm(initial: workout),
                    );
                  },
                ),
    );
  }
}
