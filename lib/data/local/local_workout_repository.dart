import 'dart:convert';

import 'package:pullcrane/data/local/local_database.dart';
import 'package:pullcrane/domain/models/workout.dart';
import 'package:pullcrane/domain/repositories/workout_repository.dart';
import 'package:sqflite_common/sqlite_api.dart';

class LocalWorkoutRepository implements WorkoutRepository {
  @override
  Future<void> init() async {
    await LocalDatabase.instance.database;
  }

  @override
  Future<List<Workout>> listWorkouts() async {
    final Database db = await LocalDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      LocalDatabase.workoutsTable,
      columns: <String>['payload_json'],
      orderBy: 'LOWER(name) ASC',
    );

    return rows
        .map((Map<String, Object?> row) => Workout.fromJson(
              jsonDecode(row['payload_json']! as String) as Map<String, dynamic>,
            ))
        .toList();
  }

  @override
  Future<void> saveWorkout(Workout workout) async {
    final Database db = await LocalDatabase.instance.database;
    await db.insert(
      LocalDatabase.workoutsTable,
      <String, Object?>{
        'id': workout.id,
        'name': workout.name,
        'payload_json': jsonEncode(workout.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteWorkout(String id) async {
    final Database db = await LocalDatabase.instance.database;
    await db.delete(
      LocalDatabase.workoutsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
