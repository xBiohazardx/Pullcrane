import 'package:flutter/material.dart';
import 'package:pullcrane/domain/models/exercise.dart';

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
  late final TextEditingController repsController;
  late final TextEditingController durationController;
  late final TextEditingController restController;
  late final TextEditingController targetForceController;

  late ExerciseMode mode;
  late TargetForceMode targetForceMode;
  late bool isSideSwitching;
  late ExerciseHand startingHand;

  @override
  void initState() {
    super.initState();
    final Exercise? initial = widget.initialExercise;
    mode = initial?.mode ?? ExerciseMode.reps;
    targetForceMode = initial?.targetForceMode ?? TargetForceMode.absoluteKg;
    isSideSwitching = initial?.isSideSwitching ?? false;
    startingHand = initial?.startingHand ?? ExerciseHand.left;
    nameController = TextEditingController(text: initial?.name ?? '');
    descriptionController = TextEditingController(text: initial?.description ?? '');
    repsController = TextEditingController(
      text: initial?.reps != null ? initial!.reps.toString() : '8',
    );
    durationController = TextEditingController(
      text: initial?.durationSeconds != null ? initial!.durationSeconds.toString() : '30',
    );
    restController = TextEditingController(
      text: (initial?.defaultRestSeconds ?? 60).toString(),
    );
    targetForceController = TextEditingController(
      text: (initial?.targetForceValue ?? 10).toStringAsFixed(
        (initial?.targetForceValue ?? 10) % 1 == 0 ? 0 : 1,
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    repsController.dispose();
    durationController.dispose();
    restController.dispose();
    targetForceController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!formKey.currentState!.validate()) {
      return;
    }

    final String id = widget.initialExercise?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final int defaultRest = int.parse(restController.text.trim());
    final double targetForce = double.parse(targetForceController.text.trim());
    final int? reps = mode == ExerciseMode.reps ? int.parse(repsController.text.trim()) : null;
    final int? duration = mode == ExerciseMode.duration
        ? int.parse(durationController.text.trim())
        : null;

    final Exercise exercise = Exercise(
      id: id,
      name: nameController.text.trim(),
      description: descriptionController.text.trim(),
      mode: mode,
      reps: reps,
      durationSeconds: duration,
      defaultRestSeconds: defaultRest,
      targetForceMode: targetForceMode,
      targetForceValue: targetForce,
      isSideSwitching: isSideSwitching,
      startingHand: startingHand,
      isDefault: widget.initialExercise?.isDefault ?? false,
    );

    Navigator.of(context).pop(exercise);
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.initialExercise != null;

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
                setState(() {
                  mode = value;
                });
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
                setState(() {
                  targetForceMode = value;
                });
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: targetForceController,
              decoration: InputDecoration(
                labelText: targetForceMode == TargetForceMode.absoluteKg
                    ? 'Target force (kg)'
                    : 'Target force (% of max lift)',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            if (isSideSwitching)
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
                  setState(() {
                    startingHand = value;
                  });
                },
              ),
            const SizedBox(height: 12),
            if (mode == ExerciseMode.reps)
              TextFormField(
                controller: repsController,
                decoration: const InputDecoration(labelText: 'Reps'),
                keyboardType: TextInputType.number,
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
                controller: durationController,
                decoration: const InputDecoration(labelText: 'Duration (seconds)'),
                keyboardType: TextInputType.number,
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
              controller: restController,
              decoration: const InputDecoration(labelText: 'Default rest (seconds)'),
              keyboardType: TextInputType.number,
              validator: (value) {
                final int? parsed = int.tryParse(value ?? '');
                if (parsed == null || parsed < 0) {
                  return 'Enter rest >= 0.';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}


