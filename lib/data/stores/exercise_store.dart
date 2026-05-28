import 'package:pullcrane/data/app_database.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:sqflite_common/sqlite_api.dart';

class ExerciseStore {
  Future<void> init() async {
    final Database db = await AppDatabase.instance.database;

    // Clean up the old default rest exercise if it still exists
    await db.delete(
      AppDatabase.exercisesTable,
      where: 'id = ?',
      whereArgs: <Object?>['default_rest'],
    );
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
      );
    }).toList();
  }

  Future<void> saveExercise(Exercise exercise) async {
    final Database db = await AppDatabase.instance.database;
    await db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> existing = await txn.query(
        AppDatabase.exercisesTable,
        where: 'id = ?',
        whereArgs: <Object?>[exercise.id],
      );

      final Map<String, Object?> row = <String, Object?>{
        'id': exercise.id,
        'name': exercise.name,
        'description': exercise.description,
        'is_side_switching': exercise.isSideSwitching ? 1 : 0,
        'max_lift_left_kg': exercise.maxLiftLeftKg,
        'max_lift_right_kg': exercise.maxLiftRightKg,
      };

      if (existing.isNotEmpty) {
        await txn.update(
          AppDatabase.exercisesTable,
          row,
          where: 'id = ?',
          whereArgs: <Object?>[exercise.id],
        );
      } else {
        await txn.insert(AppDatabase.exercisesTable, row);
      }

      await txn.delete(
        AppDatabase.exerciseHistoryTable,
        where: 'exercise_id = ?',
        whereArgs: <Object?>[exercise.id],
      );

      for (final MaxLiftRecord record in exercise.maxLiftHistory) {
        await txn.insert(AppDatabase.exerciseHistoryTable, <String, Object?>{
          'exercise_id': exercise.id,
          'date': record.date.toIso8601String(),
          'left_kg': record.leftKg,
          'right_kg': record.rightKg,
        });
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
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }
}
