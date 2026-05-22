import 'dart:convert';

import 'package:pullcrane/domain/models/workout.dart';
import 'package:pullcrane/domain/repositories/workout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalWorkoutRepository implements WorkoutRepository {
  static const String _storageKey = 'workouts.v1';

  List<Workout> _cache = <Workout>[];

  @override
  Future<void> init() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_storageKey);

    if (raw == null || raw.isEmpty) {
      _cache = <Workout>[];
      return;
    }

    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    _cache = decoded
        .map((item) => Workout.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Workout>> listWorkouts() async {
    return List<Workout>.from(_cache)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Future<void> saveWorkout(Workout workout) async {
    final int index = _cache.indexWhere((item) => item.id == workout.id);
    if (index >= 0) {
      _cache[index] = workout;
    } else {
      _cache.add(workout);
    }
    await _save();
  }

  @override
  Future<void> deleteWorkout(String id) async {
    _cache.removeWhere((workout) => workout.id == id);
    await _save();
  }

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(_cache.map((item) => item.toJson()).toList());
    await prefs.setString(_storageKey, raw);
  }
}

