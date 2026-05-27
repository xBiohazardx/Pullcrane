import 'package:pullcrane/data/app_database.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/models/workout.dart';
import 'package:sqflite_common/sqlite_api.dart';

class WorkoutStore {
  Future<void> init() async {
    await AppDatabase.instance.database;
  }

  Future<List<Workout>> listWorkouts() async {
    final Database db = await AppDatabase.instance.database;
    
    final List<Map<String, Object?>> workoutRows = await db.query(
      AppDatabase.workoutsTable,
      orderBy: 'LOWER(name) ASC',
    );

    final List<Map<String, Object?>> entryRows = await db.query(
      AppDatabase.workoutEntriesTable,
      orderBy: 'order_index ASC',
    );

    final Map<String, List<WorkoutExerciseEntry>> entriesMap = {};
    for (final Map<String, Object?> row in entryRows) {
      final String workoutId = row['workout_id'] as String;
      final WorkoutExerciseEntry entry = WorkoutExerciseEntry(
        exerciseId: row['exercise_id'] as String,
        sets: row['sets'] as int,
        mode: ExerciseMode.values.byName(row['mode'] as String),
        reps: row['reps'] as int?,
        durationSeconds: row['duration_seconds'] as int?,
        restSeconds: row['rest_seconds'] as int,
        targetForceMode: TargetForceMode.values.byName(row['target_force_mode'] as String),
        targetForceValue: (row['target_force_value'] as num).toDouble(),
        startingHand: ExerciseHand.values.byName(row['starting_hand'] as String),
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

  Future<void> saveWorkout(Workout workout) async {
    final Database db = await AppDatabase.instance.database;
    
    await db.transaction((Transaction txn) async {
      await txn.insert(
        AppDatabase.workoutsTable,
        <String, Object?>{
          'id': workout.id,
          'name': workout.name,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        AppDatabase.workoutEntriesTable,
        where: 'workout_id = ?',
        whereArgs: <Object?>[workout.id],
      );

      for (var i = 0; i < workout.entries.length; i++) {
        final WorkoutExerciseEntry entry = workout.entries[i];
        await txn.insert(
          AppDatabase.workoutEntriesTable,
          <String, Object?>{
            'workout_id': workout.id,
            'exercise_id': entry.exerciseId,
            'sets': entry.sets,
            'mode': entry.mode.name,
            'reps': entry.reps,
            'duration_seconds': entry.durationSeconds,
            'rest_seconds': entry.restSeconds,
            'target_force_mode': entry.targetForceMode.name,
            'target_force_value': entry.targetForceValue,
            'starting_hand': entry.startingHand.name,
            'order_index': i,
          },
        );
      }
    });
  }

  Future<void> deleteWorkout(String id) async {
    final Database db = await AppDatabase.instance.database;
    await db.transaction((Transaction txn) async {
      // Manual cascade delete
      await txn.delete(
        AppDatabase.workoutEntriesTable,
        where: 'workout_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        AppDatabase.workoutsTable,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }
}
