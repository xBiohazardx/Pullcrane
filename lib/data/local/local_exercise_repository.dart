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
    
    final List<Map<String, Object?>> exerciseRows = await db.query(
      LocalDatabase.exercisesTable,
      orderBy: 'LOWER(name) ASC',
    );

    final List<Map<String, Object?>> historyRows = await db.query(
      LocalDatabase.exerciseHistoryTable,
      orderBy: 'date ASC',
    );

    final Map<String, List<MaxLiftRecord>> historyMap = {};
    for (final row in historyRows) {
      final String exerciseId = row['exercise_id'] as String;
      final MaxLiftRecord record = MaxLiftRecord(
        date: DateTime.parse(row['date'] as String),
        leftKg: row['left_kg'] as int,
        rightKg: row['right_kg'] as int,
      );
      historyMap.putIfAbsent(exerciseId, () => <MaxLiftRecord>[]).add(record);
    }

    return exerciseRows.map((Map<String, Object?> row) {
      final String id = row['id'] as String;
      return Exercise(
        id: id,
        name: row['name'] as String,
        description: row['description'] as String,
        mode: ExerciseMode.values.byName(row['mode'] as String),
        reps: row['reps'] as int?,
        durationSeconds: row['duration_seconds'] as int?,
        defaultRestSeconds: row['default_rest_seconds'] as int,
        targetForceMode: TargetForceMode.values.byName(row['target_force_mode'] as String),
        targetForceValue: (row['target_force_value'] as num).toDouble(),
        isSideSwitching: (row['is_side_switching'] as int) == 1,
        startingHand: ExerciseHand.values.byName(row['starting_hand'] as String),
        maxLiftLeftKg: row['max_lift_left_kg'] as int,
        maxLiftRightKg: row['max_lift_right_kg'] as int,
        maxLiftHistory: historyMap[id] ?? <MaxLiftRecord>[],
        isDefault: (row['is_default'] as int) == 1,
      );
    }).toList();
  }

  @override
  Future<void> saveExercise(Exercise exercise) async {
    final Database db = await LocalDatabase.instance.database;
    await db.transaction((Transaction txn) async {
      await txn.insert(
        LocalDatabase.exercisesTable,
        <String, Object?>{
          'id': exercise.id,
          'name': exercise.name,
          'description': exercise.description,
          'mode': exercise.mode.name,
          'reps': exercise.reps,
          'duration_seconds': exercise.durationSeconds,
          'default_rest_seconds': exercise.defaultRestSeconds,
          'target_force_mode': exercise.targetForceMode.name,
          'target_force_value': exercise.targetForceValue,
          'is_side_switching': exercise.isSideSwitching ? 1 : 0,
          'starting_hand': exercise.startingHand.name,
          'max_lift_left_kg': exercise.maxLiftLeftKg,
          'max_lift_right_kg': exercise.maxLiftRightKg,
          'is_default': exercise.isDefault ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        LocalDatabase.exerciseHistoryTable,
        where: 'exercise_id = ?',
        whereArgs: <Object?>[exercise.id],
      );

      for (final MaxLiftRecord record in exercise.maxLiftHistory) {
        await txn.insert(
          LocalDatabase.exerciseHistoryTable,
          <String, Object?>{
            'exercise_id': exercise.id,
            'date': record.date.toIso8601String(),
            'left_kg': record.leftKg,
            'right_kg': record.rightKg,
          },
        );
      }
    });
  }

  @override
  Future<void> deleteExercise(String id) async {
    final Database db = await LocalDatabase.instance.database;
    await db.transaction((Transaction txn) async {
      // Manual cascade delete just in case PRAGMAs aren't respected
      await txn.delete(
        LocalDatabase.exerciseHistoryTable,
        where: 'exercise_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        LocalDatabase.exercisesTable,
        where: 'id = ? AND is_default = 0',
        whereArgs: <Object?>[id],
      );
    });
  }
}
