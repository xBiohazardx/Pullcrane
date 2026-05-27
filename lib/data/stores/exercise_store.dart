import 'package:pullcrane/data/app_database.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:sqflite_common/sqlite_api.dart';

class ExerciseStore {
  static const String _defaultRestExerciseId = 'default_rest';

  Future<void> init() async {
    final Database db = await AppDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.exercisesTable,
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
      isSideSwitching: false,
      isDefault: true,
    );
    await saveExercise(defaultRestExercise);
  }

  Future<List<Exercise>> listExercises() async {
    final Database db = await AppDatabase.instance.database;
    
    final List<Map<String, Object?>> exerciseRows = await db.query(
      AppDatabase.exercisesTable,
      orderBy: 'LOWER(name) ASC',
    );

    final List<Map<String, Object?>> historyRows = await db.query(
      AppDatabase.exerciseHistoryTable,
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
        isSideSwitching: (row['is_side_switching'] as int) == 1,
        maxLiftLeftKg: row['max_lift_left_kg'] as int,
        maxLiftRightKg: row['max_lift_right_kg'] as int,
        maxLiftHistory: historyMap[id] ?? <MaxLiftRecord>[],
        isDefault: (row['is_default'] as int) == 1,
      );
    }).toList();
  }

  Future<void> saveExercise(Exercise exercise) async {
    final Database db = await AppDatabase.instance.database;
    await db.transaction((Transaction txn) async {
      await txn.insert(
        AppDatabase.exercisesTable,
        <String, Object?>{
          'id': exercise.id,
          'name': exercise.name,
          'description': exercise.description,
          'is_side_switching': exercise.isSideSwitching ? 1 : 0,
          'max_lift_left_kg': exercise.maxLiftLeftKg,
          'max_lift_right_kg': exercise.maxLiftRightKg,
          'is_default': exercise.isDefault ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        AppDatabase.exerciseHistoryTable,
        where: 'exercise_id = ?',
        whereArgs: <Object?>[exercise.id],
      );

      for (final MaxLiftRecord record in exercise.maxLiftHistory) {
        await txn.insert(
          AppDatabase.exerciseHistoryTable,
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

  Future<void> deleteExercise(String id) async {
    final Database db = await AppDatabase.instance.database;
    await db.transaction((Transaction txn) async {
      // Manual cascade delete just in case PRAGMAs aren't respected
      await txn.delete(
        AppDatabase.exerciseHistoryTable,
        where: 'exercise_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        AppDatabase.exercisesTable,
        where: 'id = ? AND is_default = 0',
        whereArgs: <Object?>[id],
      );
    });
  }
}
