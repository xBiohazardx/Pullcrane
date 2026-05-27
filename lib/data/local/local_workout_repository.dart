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
    
    final List<Map<String, Object?>> workoutRows = await db.query(
      LocalDatabase.workoutsTable,
      orderBy: 'LOWER(name) ASC',
    );

    final List<Map<String, Object?>> entryRows = await db.query(
      LocalDatabase.workoutEntriesTable,
      orderBy: 'order_index ASC',
    );

    final Map<String, List<WorkoutExerciseEntry>> entriesMap = {};
    for (final Map<String, Object?> row in entryRows) {
      final String workoutId = row['workout_id'] as String;
      final WorkoutExerciseEntry entry = WorkoutExerciseEntry(
        exerciseId: row['exercise_id'] as String,
        sets: row['sets'] as int,
        restOverrideSeconds: row['rest_override_seconds'] as int?,
      );
      entriesMap.putIfAbsent(workoutId, () => <WorkoutExerciseEntry>[]).add(entry);
    }

    return workoutRows.map((Map<String, Object?> row) {
      final String id = row['id'] as String;
      return Workout(
        id: id,
        name: row['name'] as String,
        entries: entriesMap[id] ?? <WorkoutExerciseEntry>[],
      );
    }).toList();
  }

  @override
  Future<void> saveWorkout(Workout workout) async {
    final Database db = await LocalDatabase.instance.database;
    
    await db.transaction((Transaction txn) async {
      await txn.insert(
        LocalDatabase.workoutsTable,
        <String, Object?>{
          'id': workout.id,
          'name': workout.name,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        LocalDatabase.workoutEntriesTable,
        where: 'workout_id = ?',
        whereArgs: <Object?>[workout.id],
      );

      for (var i = 0; i < workout.entries.length; i++) {
        final WorkoutExerciseEntry entry = workout.entries[i];
        await txn.insert(
          LocalDatabase.workoutEntriesTable,
          <String, Object?>{
            'workout_id': workout.id,
            'exercise_id': entry.exerciseId,
            'sets': entry.sets,
            'rest_override_seconds': entry.restOverrideSeconds,
            'order_index': i,
          },
        );
      }
    });
  }

  @override
  Future<void> deleteWorkout(String id) async {
    final Database db = await LocalDatabase.instance.database;
    await db.transaction((Transaction txn) async {
      // Manual cascade delete
      await txn.delete(
        LocalDatabase.workoutEntriesTable,
        where: 'workout_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        LocalDatabase.workoutsTable,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }
}
