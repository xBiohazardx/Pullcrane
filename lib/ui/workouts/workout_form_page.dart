import 'package:flutter/material.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/models/workout.dart';

class WorkoutFormPage extends StatefulWidget {
  const WorkoutFormPage({
    super.key,
    this.initialWorkout,
    required this.availableExercises,
  });

  final Workout? initialWorkout;
  final List<Exercise> availableExercises;

  @override
  State<WorkoutFormPage> createState() => _WorkoutFormPageState();
}

class _WorkoutFormPageState extends State<WorkoutFormPage> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late List<WorkoutExerciseEntry> entries;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.initialWorkout?.name ?? '');
    entries = List<WorkoutExerciseEntry>.from(widget.initialWorkout?.entries ?? <WorkoutExerciseEntry>[]);
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> _addEntry() async {
    if (widget.availableExercises.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create an exercise first.')),
      );
      return;
    }

    String selectedExerciseId = widget.availableExercises.first.id;
    String setsInput = '3';
    String restOverrideInput = '';
    final GlobalKey<FormState> dialogFormKey = GlobalKey<FormState>();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Exercise Entry'),
              content: Form(
                key: dialogFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedExerciseId,
                      decoration: const InputDecoration(labelText: 'Exercise'),
                      items: widget.availableExercises
                          .map(
                            (exercise) => DropdownMenuItem<String>(
                              value: exercise.id,
                              child: Text(exercise.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          selectedExerciseId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: setsInput,
                      decoration: const InputDecoration(labelText: 'Sets'),
                      keyboardType: TextInputType.number,
                      onChanged: (value) => setsInput = value,
                      validator: (value) {
                        final int? parsed = int.tryParse(value ?? '');
                        if (parsed == null || parsed <= 0) {
                          return 'Sets must be greater than zero.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: restOverrideInput,
                      decoration: const InputDecoration(
                        labelText: 'Rest override (seconds, optional)',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) => restOverrideInput = value,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return null;
                        }
                        final int? parsed = int.tryParse(value);
                        if (parsed == null || parsed < 0) {
                          return 'Enter rest >= 0.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (dialogFormKey.currentState!.validate()) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final int sets = int.parse(setsInput.trim());
    final int? restOverride = restOverrideInput.trim().isEmpty
        ? null
        : int.parse(restOverrideInput.trim());

    setState(() {
      entries = <WorkoutExerciseEntry>[
        ...entries,
        WorkoutExerciseEntry(
          exerciseId: selectedExerciseId,
          sets: sets,
          restOverrideSeconds: restOverride,
        ),
      ];
    });
  }

  void _removeEntry(int index) {
    setState(() {
      entries.removeAt(index);
    });
  }

  void _submit() {
    if (!formKey.currentState!.validate()) {
      return;
    }

    final Workout workout = Workout(
      id: widget.initialWorkout?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: nameController.text.trim(),
      entries: entries,
    );

    Navigator.of(context).pop(workout);
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.initialWorkout != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Workout' : 'Create Workout'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEntry,
        icon: const Icon(Icons.add),
        label: const Text('Add Exercise'),
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Workout name'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Workout name is required.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Text('Exercises', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Text('No exercises added yet.')
            else
              ...entries.asMap().entries.map((entry) {
                final int index = entry.key;
                final WorkoutExerciseEntry item = entry.value;
                final Exercise? exercise = widget.availableExercises
                    .where((candidate) => candidate.id == item.exerciseId)
                    .cast<Exercise?>()
                    .firstWhere((candidate) => candidate != null, orElse: () => null);

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(exercise?.name ?? 'Unknown exercise'),
                  subtitle: Text(
                    'Sets: ${item.sets}${item.restOverrideSeconds != null ? ' • Rest override: ${item.restOverrideSeconds}s' : ''}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeEntry(index),
                  ),
                );
              }),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              child: const Text('Save Workout'),
            ),
          ],
        ),
      ),
    );
  }
}


