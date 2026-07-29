import 'package:pullcrane/data/app_database.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/models/set_log.dart';
import 'package:pullcrane/domain/models/workout_session.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Persists workout sessions and their set logs (schema v4).
class SessionStore {
  Future<int> saveSession({
    required String workoutId,
    required String workoutName,
    required DateTime startedAt,
    required DateTime finishedAt,
    required bool completed,
    required List<SetLog> logs,
  }) async {
    final Database db = await AppDatabase.instance.database;
    return db.transaction((Transaction txn) async {
      final int sessionId = await txn.insert(AppDatabase.workoutSessionsTable, {
        'workout_id': workoutId,
        'workout_name': workoutName,
        'started_at': startedAt.toIso8601String(),
        'finished_at': finishedAt.toIso8601String(),
        'completed': completed ? 1 : 0,
      });

      for (final SetLog log in logs) {
        await txn.insert(AppDatabase.setLogsTable, {
          'session_id': sessionId,
          'entry_index': log.entryIndex,
          'set_number': log.setNumber,
          'exercise_id': log.exerciseId,
          'exercise_name': log.exerciseName,
          'hand': log.hand?.name,
          'target_force_kg': log.targetForceKg,
          'planned_duration_seconds': log.plannedDurationSeconds,
          'planned_reps': log.plannedReps,
          'actual_duration_seconds': log.actualDurationSeconds,
          'peak_force_kg': log.peakForceKg,
        });
      }

      return sessionId;
    });
  }

  /// All sessions, newest first, without their set logs.
  Future<List<WorkoutSession>> listSessions() async {
    final Database db = await AppDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT s.*,
        (SELECT COUNT(*) FROM ${AppDatabase.setLogsTable} l
         WHERE l.session_id = s.id) AS set_count
      FROM ${AppDatabase.workoutSessionsTable} s
      ORDER BY s.started_at DESC
      ''');
    return rows.map(_sessionFromRow).toList();
  }

  /// A single session including its set logs, or null when missing.
  Future<WorkoutSession?> getSession(int id) async {
    final Database db = await AppDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.workoutSessionsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (rows.isEmpty) {
      return null;
    }

    final List<Map<String, Object?>> logRows = await db.query(
      AppDatabase.setLogsTable,
      where: 'session_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'id ASC',
    );

    final WorkoutSession session = _sessionFromRow(rows.first);
    return WorkoutSession(
      id: session.id,
      workoutId: session.workoutId,
      workoutName: session.workoutName,
      startedAt: session.startedAt,
      finishedAt: session.finishedAt,
      completed: session.completed,
      setLogs: logRows.map(_logFromRow).toList(),
    );
  }

  /// Set logs for one exercise across all sessions, newest first.
  /// Used by the per-exercise analytics view.
  Future<List<SetLog>> listLogsForExercise(
    String exerciseId, {
    int limit = 100,
  }) async {
    final Database db = await AppDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT l.*, s.started_at AS session_started_at
      FROM ${AppDatabase.setLogsTable} l
      INNER JOIN ${AppDatabase.workoutSessionsTable} s ON s.id = l.session_id
      WHERE l.exercise_id = ?
      ORDER BY s.started_at DESC, l.id DESC
      LIMIT ?
      ''',
      <Object?>[exerciseId, limit],
    );
    return rows.map(_logFromRow).toList();
  }

  Future<void> deleteSession(int id) async {
    final Database db = await AppDatabase.instance.database;
    await db.transaction((Transaction txn) async {
      await txn.delete(
        AppDatabase.setLogsTable,
        where: 'session_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        AppDatabase.workoutSessionsTable,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }

  WorkoutSession _sessionFromRow(Map<String, Object?> row) {
    return WorkoutSession(
      id: row['id'] as int,
      workoutId: row['workout_id'] as String,
      workoutName: row['workout_name'] as String,
      startedAt: DateTime.parse(row['started_at'] as String),
      finishedAt: DateTime.parse(row['finished_at'] as String),
      completed: (row['completed'] as int) == 1,
      setCount: (row['set_count'] as int?) ?? 0,
    );
  }

  SetLog _logFromRow(Map<String, Object?> row) {
    final String? handName = row['hand'] as String?;
    final String? sessionStartedAt = row['session_started_at'] as String?;
    return SetLog(
      entryIndex: row['entry_index'] as int,
      setNumber: row['set_number'] as int,
      exerciseId: row['exercise_id'] as String,
      exerciseName: row['exercise_name'] as String,
      hand: handName == null ? null : ExerciseHand.values.byName(handName),
      targetForceKg: row['target_force_kg'] as int,
      plannedDurationSeconds: row['planned_duration_seconds'] as int,
      plannedReps: row['planned_reps'] as int,
      actualDurationSeconds: row['actual_duration_seconds'] as int,
      peakForceKg: row['peak_force_kg'] as int,
      sessionStartedAt:
          sessionStartedAt == null ? null : DateTime.parse(sessionStartedAt),
    );
  }
}
