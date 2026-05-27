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

  late bool isSideSwitching;

  @override
  void initState() {
    super.initState();
    final Exercise? initial = widget.initialExercise;
    isSideSwitching = initial?.isSideSwitching ?? false;
    nameController = TextEditingController(text: initial?.name ?? '');
    descriptionController = TextEditingController(text: initial?.description ?? '');
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

    final String id = widget.initialExercise?.id ?? DateTime.now().microsecondsSinceEpoch.toString();

    final Exercise exercise = Exercise(
      id: id,
      name: nameController.text.trim(),
      description: descriptionController.text.trim(),
      isSideSwitching: isSideSwitching,
      maxLiftLeftKg: widget.initialExercise?.maxLiftLeftKg ?? 0,
      maxLiftRightKg: widget.initialExercise?.maxLiftRightKg ?? 0,
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}



