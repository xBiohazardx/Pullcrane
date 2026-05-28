import 'package:flutter/material.dart';
import 'package:pullcrane/data/app_stores.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/ui/exercises/exercise_form_page.dart';

class ExercisesPage extends StatefulWidget {
  const ExercisesPage({super.key});

  @override
  State<ExercisesPage> createState() => _ExercisesPageState();
}

class _ExercisesPageState extends State<ExercisesPage> {
  List<Exercise> exercises = <Exercise>[];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<Exercise> loaded = await AppStores.exercises.listExercises();
    if (!mounted) {
      return;
    }
    setState(() {
      exercises = loaded;
      isLoading = false;
    });
  }

  Future<void> _openForm({Exercise? initial}) async {
    final Exercise? result = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(
        builder: (_) => ExerciseFormPage(initialExercise: initial),
      ),
    );

    if (result != null) {
      await AppStores.exercises.saveExercise(result);
    }

    await _reload();
  }

  Future<void> _deleteExercise(Exercise exercise) async {
    await AppStores.exercises.deleteExercise(exercise.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exercises')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : exercises.isEmpty
          ? const Center(child: Text('No exercises yet.'))
          : ListView.builder(
              itemCount: exercises.length,
              itemBuilder: (context, index) {
                final Exercise exercise = exercises[index];
                final String handInfo = exercise.isSideSwitching
                    ? 'Alternating hands'
                    : 'Single configuration';

                return ListTile(
                  title: Text(exercise.name),
                  subtitle: Text('${exercise.description}\n$handInfo'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteExercise(exercise),
                  ),
                  onTap: () => _openForm(initial: exercise),
                );
              },
            ),
    );
  }
}
