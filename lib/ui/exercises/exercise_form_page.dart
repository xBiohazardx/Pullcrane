import 'package:flutter/material.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/ui/benchmark/max_lift_measurement_page.dart';
import 'package:pullcrane/ui/exercises/exercise_progression_page.dart';
import 'package:pullcrane/data/app_stores.dart';

class ExerciseFormPage extends StatefulWidget {
  const ExerciseFormPage({super.key, this.initialExercise});

  final Exercise? initialExercise;

  @override
  State<ExerciseFormPage> createState() => _ExerciseFormPageState();
}

class _ExerciseFormPageState extends State<ExerciseFormPage> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late final TextEditingController descriptionController;

  late bool isSideSwitching;
  Exercise? currentExercise;

  @override
  void initState() {
    super.initState();
    currentExercise = widget.initialExercise;
    isSideSwitching = currentExercise?.isSideSwitching ?? false;
    nameController = TextEditingController(text: currentExercise?.name ?? '');
    descriptionController = TextEditingController(text: currentExercise?.description ?? '');
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!formKey.currentState!.validate()) {
      return;
    }

    final String id = currentExercise?.id ?? DateTime.now().microsecondsSinceEpoch.toString();

    final Exercise exercise = Exercise(
      id: id,
      name: nameController.text.trim(),
      description: descriptionController.text.trim(),
      isSideSwitching: isSideSwitching,
      maxLiftLeftKg: currentExercise?.maxLiftLeftKg ?? 0,
      maxLiftRightKg: currentExercise?.maxLiftRightKg ?? 0,
      maxLiftHistory: currentExercise?.maxLiftHistory ?? [],
      isDefault: currentExercise?.isDefault ?? false,
    );

    Navigator.of(context).pop(exercise);
  }

  String _benchmarkInfo(Exercise exercise) {
    if (!exercise.isSideSwitching) {
      return 'Max lift: ${exercise.maxLiftLeftKg}kg';
    }
    return 'L ${exercise.maxLiftLeftKg}kg  •  R ${exercise.maxLiftRightKg}kg';
  }

  Future<void> _openBenchmark() async {
    if (currentExercise == null) return;
    
    final Exercise? updated = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(
        builder: (_) => MaxLiftMeasurementPage(exercise: currentExercise!),
      ),
    );

    if (updated != null) {
      // Benchmark page already saved to db, just sync state
      // Actually, since we want to be safe, we re-fetch the exercise from the DB 
      // just in case we need fresh data. But `updated` contains the fresh data!
      setState(() {
        currentExercise = updated;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Benchmark saved.')),
        );
      }
    }
  }

  void _openProgression() {
    if (currentExercise == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExerciseProgressionPage(exercise: currentExercise!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = currentExercise != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Exercise' : 'Create Exercise'),
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              value: isSideSwitching,
              contentPadding: EdgeInsets.zero,
              title: const Text('Alternate hands each set'),
              subtitle: const Text('App guides hand switching and rest carryover.'),
              onChanged: (value) {
                setState(() {
                  isSideSwitching = value;
                });
              },
            ),
            
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              child: const Text('Save Exercise Definition'),
            ),

            if (isEditing) ...[
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Benchmark & Progression',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _benchmarkInfo(currentExercise!),
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonal(
                              onPressed: _openBenchmark,
                              child: const Text('Measure Max Lift'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonal(
                              onPressed: _openProgression,
                              child: const Text('Progression'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}



