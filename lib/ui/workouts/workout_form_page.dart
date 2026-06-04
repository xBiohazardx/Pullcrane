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
    nameController = TextEditingController(
      text: widget.initialWorkout?.name ?? '',
    );
    entries = List<WorkoutExerciseEntry>.from(
      widget.initialWorkout?.entries ?? <WorkoutExerciseEntry>[],
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> _showEntryDialog({
    WorkoutExerciseEntry? existingEntry,
    int? index,
  }) async {
    if (widget.availableExercises.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create an exercise first.')),
      );
      return;
    }

    String selectedExerciseId =
        existingEntry?.exerciseId ?? widget.availableExercises.first.id;
    // ensure selectedExerciseId is still valid
    if (!widget.availableExercises.any((e) => e.id == selectedExerciseId)) {
      selectedExerciseId = widget.availableExercises.first.id;
    }

    String setsInput = existingEntry?.sets.toString() ?? '3';
    ExerciseMode mode = existingEntry?.mode ?? ExerciseMode.reps;
    String repsInput = existingEntry?.reps?.toString() ?? '8';
    String durationInput = existingEntry?.durationSeconds?.toString() ?? '30';
    String restInput = existingEntry?.restSeconds.toString() ?? '60';
    TargetForceMode targetForceMode = existingEntry?.targetForceMode ?? TargetForceMode.absoluteKg;
    String targetForceInput = (existingEntry?.targetForceValue ?? 10).toStringAsFixed(
        (existingEntry?.targetForceValue ?? 10) % 1 == 0 ? 0 : 1,
    );
    ExerciseHand startingHand = existingEntry?.startingHand ?? ExerciseHand.left;

    final GlobalKey<FormState> dialogFormKey = GlobalKey<FormState>();

    final bool isEditing = existingEntry != null;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final Exercise? selectedExercise = widget.availableExercises
                .where((e) => e.id == selectedExerciseId)
                .firstOrNull;
            final bool isSideSwitching = selectedExercise?.isSideSwitching ?? false;

            return AlertDialog(
              title: Text(
                isEditing ? 'Edit Exercise Entry' : 'Add Exercise Entry',
              ),
              content: Form(
                key: dialogFormKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedExerciseId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Exercise'),
                        items: widget.availableExercises
                            .map(
                              (exercise) => DropdownMenuItem<String>(
                                value: exercise.id,
                                child: Text(
                                  exercise.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
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
                      DropdownButtonFormField<ExerciseMode>(
                        initialValue: mode,
                        decoration: const InputDecoration(labelText: 'Mode'),
                        items: const [
                          DropdownMenuItem(
                            value: ExerciseMode.reps,
                            child: Text('Reps based'),
                          ),
                          DropdownMenuItem(
                            value: ExerciseMode.duration,
                            child: Text('Duration based'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            mode = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (mode == ExerciseMode.reps)
                        TextFormField(
                          initialValue: repsInput,
                          decoration: const InputDecoration(labelText: 'Reps'),
                          keyboardType: TextInputType.number,
                          onChanged: (value) => repsInput = value,
                          validator: (value) {
                            final int? parsed = int.tryParse(value ?? '');
                            if (parsed == null || parsed <= 0) {
                              return 'Enter reps > 0.';
                            }
                            return null;
                          },
                        )
                      else
                        TextFormField(
                          initialValue: durationInput,
                          decoration: const InputDecoration(labelText: 'Duration (seconds)'),
                          keyboardType: TextInputType.number,
                          onChanged: (value) => durationInput = value,
                          validator: (value) {
                            final int? parsed = int.tryParse(value ?? '');
                            if (parsed == null || parsed <= 0) {
                              return 'Enter duration > 0.';
                            }
                            return null;
                          },
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: restInput,
                        decoration: const InputDecoration(
                          labelText: 'Rest (seconds)',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) => restInput = value,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Rest time is required.';
                          }
                          final int? parsed = int.tryParse(value);
                          if (parsed == null || parsed < 0) {
                            return 'Enter rest >= 0.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<TargetForceMode>(
                        initialValue: targetForceMode,
                        decoration: const InputDecoration(labelText: 'Target force mode'),
                        items: const [
                          DropdownMenuItem(
                            value: TargetForceMode.absoluteKg,
                            child: Text('Absolute (kg)'),
                          ),
                          DropdownMenuItem(
                            value: TargetForceMode.relativePercent,
                            child: Text('Relative (% of max lift)'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            targetForceMode = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: targetForceInput,
                        decoration: InputDecoration(
                          labelText: targetForceMode == TargetForceMode.absoluteKg
                              ? 'Target force (kg)'
                              : 'Target force (% of max lift)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (value) => targetForceInput = value,
                        validator: (value) {
                          final double? parsed = double.tryParse(value ?? '');
                          if (parsed == null) {
                            return 'Enter a valid number.';
                          }
                          if (targetForceMode == TargetForceMode.absoluteKg) {
                            if (parsed < 0 || parsed > 300) {
                              return 'Enter target between 0 and 300kg.';
                            }
                          } else {
                            if (parsed <= 0 || parsed > 100) {
                              return 'Enter target between 0 and 100%.';
                            }
                          }
                          return null;
                        },
                      ),
                      if (isSideSwitching) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<ExerciseHand>(
                          initialValue: startingHand,
                          decoration: const InputDecoration(labelText: 'Starting hand'),
                          items: const [
                            DropdownMenuItem(
                              value: ExerciseHand.left,
                              child: Text('Left'),
                            ),
                            DropdownMenuItem(
                              value: ExerciseHand.right,
                              child: Text('Right'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() {
                              startingHand = value;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
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
                  child: Text(isEditing ? 'Save' : 'Add'),
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
    final int rest = int.parse(restInput.trim());
    final double targetForce = double.parse(targetForceInput.trim());
    final int? reps = mode == ExerciseMode.reps ? int.parse(repsInput.trim()) : null;
    final int? duration = mode == ExerciseMode.duration
        ? int.parse(durationInput.trim())
        : null;

    setState(() {
      final newEntry = WorkoutExerciseEntry(
        exerciseId: selectedExerciseId,
        sets: sets,
        mode: mode,
        reps: reps,
        durationSeconds: duration,
        restSeconds: rest,
        targetForceMode: targetForceMode,
        targetForceValue: targetForce,
        startingHand: startingHand,
      );

      if (index != null) {
        entries[index] = newEntry;
      } else {
        entries = <WorkoutExerciseEntry>[...entries, newEntry];
      }
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
      id:
          widget.initialWorkout?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: nameController.text.trim(),
      entries: entries,
    );

    Navigator.of(context).pop(workout);
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.initialWorkout != null;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
          const Padding(
            padding: EdgeInsets.only(bottom: 16.0),
            child: Text('No exercises added yet.'),
          ),
      ],
    );

    final footer = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        FilledButton(onPressed: _submit, child: const Text('Save Workout')),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Workout' : 'Create Workout'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showEntryDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Exercise'),
      ),
      body: Form(
        key: formKey,
        child: ReorderableListView(
          padding: const EdgeInsets.all(16),
          buildDefaultDragHandles: false,
          header: header,
          footer: footer,
          proxyDecorator:
              (Widget child, int index, Animation<double> animation) {
                return Material(
                  elevation: 6,
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  shadowColor: Theme.of(
                    context,
                  ).colorScheme.shadow.withValues(alpha: 0.2),
                  child: child,
                );
              },
          onReorder: (int oldIndex, int newIndex) {
            setState(() {
              if (oldIndex < newIndex) {
                newIndex -= 1;
              }
              final item = entries.removeAt(oldIndex);
              entries.insert(newIndex, item);
            });
          },
          children: entries.asMap().entries.map((entry) {
            final int index = entry.key;
            final WorkoutExerciseEntry item = entry.value;
            final Exercise? exercise = widget.availableExercises
                .where((candidate) => candidate.id == item.exerciseId)
                .cast<Exercise?>()
                .firstWhere(
                  (candidate) => candidate != null,
                  orElse: () => null,
                );

            return ReorderableDelayedDragStartListener(
              key: ObjectKey(item),
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                  title: Text(
                    exercise?.name ?? 'Unknown exercise',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Sets: ${item.sets} • Rest: ${item.restSeconds}s\n'
                    '${item.mode == ExerciseMode.reps ? '${item.reps} reps' : '${item.durationSeconds}s'} • '
                    '${item.targetForceMode == TargetForceMode.absoluteKg ? '${item.targetForceValue}kg' : '${item.targetForceValue}%'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () =>
                            _showEntryDialog(existingEntry: item, index: index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeEntry(index),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
