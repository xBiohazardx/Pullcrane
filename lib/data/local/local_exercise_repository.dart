import 'dart:convert';

import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/repositories/exercise_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalExerciseRepository implements ExerciseRepository {
  static const String _storageKey = 'exercises.v1';

  List<Exercise> _cache = <Exercise>[];

  @override
  Future<void> init() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_storageKey);

    if (raw == null || raw.isEmpty) {
      _cache = <Exercise>[];
    } else {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      _cache = decoded
          .map((item) => Exercise.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    // Seed the default rest exercise once for every local profile.
    if (!_cache.any((exercise) => exercise.id == 'default_rest')) {
      _cache.add(
        Exercise(
          id: 'default_rest',
          name: 'Rest',
          description: 'Passive rest between active sets.',
          mode: ExerciseMode.duration,
          durationSeconds: 60,
          defaultRestSeconds: 0,
          targetForceMode: TargetForceMode.absoluteKg,
          targetForceValue: 0,
          isSideSwitching: false,
          startingHand: ExerciseHand.left,
          isDefault: true,
        ),
      );
      await _save();
    }
  }

  @override
  Future<List<Exercise>> listExercises() async {
    return List<Exercise>.from(_cache)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Future<void> saveExercise(Exercise exercise) async {
    final int index = _cache.indexWhere((item) => item.id == exercise.id);
    if (index >= 0) {
      _cache[index] = exercise;
    } else {
      _cache.add(exercise);
    }
    await _save();
  }

  @override
  Future<void> deleteExercise(String id) async {
    _cache.removeWhere((exercise) => exercise.id == id && !exercise.isDefault);
    await _save();
  }

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(_cache.map((item) => item.toJson()).toList());
    await prefs.setString(_storageKey, raw);
  }
}

