import 'dart:convert';

import 'package:pullcrane/data/local/local_database.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/repositories/exercise_repository.dart';
import 'package:sqflite_common/sqlite_api.dart';

class LocalExerciseRepository implements ExerciseRepository {
  static const String _defaultRestExerciseId = 'default_rest';

  @override
  Future<void> init() async {
    final Database db = await LocalDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      LocalDatabase.exercisesTable,
      columns: <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[_defaultRestExerciseId],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      return;
    }

    final Exercise defaultRestExercise = Exercise(
      id: _defaultRestExerciseId,
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
    );
    await saveExercise(defaultRestExercise);
  }

  @override
  Future<List<Exercise>> listExercises() async {
    final Database db = await LocalDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      LocalDatabase.exercisesTable,
      columns: <String>['payload_json'],
      orderBy: 'LOWER(name) ASC',
    );

    return rows
        .map((Map<String, Object?> row) => Exercise.fromJson(
              jsonDecode(row['payload_json']! as String) as Map<String, dynamic>,
            ))
        .toList();
  }

  @override
  Future<void> saveExercise(Exercise exercise) async {
    final Database db = await LocalDatabase.instance.database;
    await db.insert(
      LocalDatabase.exercisesTable,
      <String, Object?>{
        'id': exercise.id,
        'name': exercise.name,
        'payload_json': jsonEncode(exercise.toJson()),
        'is_default': exercise.isDefault ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteExercise(String id) async {
    final Database db = await LocalDatabase.instance.database;
    await db.delete(
      LocalDatabase.exercisesTable,
      where: 'id = ? AND is_default = 0',
      whereArgs: <Object?>[id],
    );
  }
}
