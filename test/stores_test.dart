import 'package:flutter_test/flutter_test.dart';
import 'package:pullcrane/data/app_database.dart';
import 'package:pullcrane/data/stores/exercise_store.dart';
import 'package:pullcrane/data/stores/session_store.dart';
import 'package:pullcrane/data/stores/settings_store.dart';
import 'package:pullcrane/data/stores/workout_store.dart';
import 'package:pullcrane/domain/models/app_settings.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/models/set_log.dart';
import 'package:pullcrane/domain/models/workout.dart';
import 'package:pullcrane/domain/models/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ExerciseStore exercises = ExerciseStore();
  final WorkoutStore workouts = WorkoutStore();
  final SettingsStore settings = SettingsStore();
  final SessionStore sessions = SessionStore();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Reopen the in-memory test database so every test starts empty.
    await AppDatabase.instance.reloadDatabase();
  });

  group('SettingsStore', () {
    test('returns defaults when nothing is stored', () async {
      final AppSettings loaded = await settings.load();
      expect(loaded.forceThresholdKg, AppSettings.defaults.forceThresholdKg);
      expect(loaded.maxForceKg, AppSettings.defaults.maxForceKg);
    });

    test('round-trips all fields including maxForceKg', () async {
      const AppSettings saved = AppSettings(
        forceThresholdKg: 15,
        targetHysteresisKg: 3,
        enableTargetHaptics: false,
        requireZeroBeforeSetStart: false,
        maxForceKg: 250,
      );
      await settings.save(saved);
      final AppSettings loaded = await settings.load();

      expect(loaded.forceThresholdKg, 15);
      expect(loaded.targetHysteresisKg, 3);
      expect(loaded.enableTargetHaptics, isFalse);
      expect(loaded.requireZeroBeforeSetStart, isFalse);
      expect(loaded.maxForceKg, 250);
    });
  });

  group('ExerciseStore', () {
    test('saves and lists exercises with history', () async {
      final Exercise exercise = Exercise(
        id: 'ex1',
        name: 'Hang',
        description: 'Two-arm hang',
        isSideSwitching: true,
        maxLiftLeftKg: 50,
        maxLiftRightKg: 55,
        maxLiftHistory: [
          MaxLiftRecord(date: DateTime(2026, 7, 1), leftKg: 48, rightKg: 53),
          MaxLiftRecord(date: DateTime(2026, 7, 15), leftKg: 50, rightKg: 55),
        ],
      );
      await exercises.saveExercise(exercise);

      final List<Exercise> loaded = await exercises.listExercises();
      expect(loaded, hasLength(1));
      expect(loaded.single.name, 'Hang');
      expect(loaded.single.isSideSwitching, isTrue);
      expect(loaded.single.maxLiftHistory, hasLength(2));
      expect(loaded.single.maxLiftHistory.first.rightKg, 53);
    });

    test('deleteExercise cascades into workout entries', () async {
      await exercises.saveExercise(Exercise(id: 'ex1', name: 'A', description: ''));
      await workouts.saveWorkout(
        Workout(
          id: 'w1',
          name: 'Strength',
          entries: [
            WorkoutExerciseEntry(
              exerciseId: 'ex1',
              sets: 3,
              mode: ExerciseMode.duration,
              durationSeconds: 7,
              restSeconds: 180,
            ),
          ],
        ),
      );

      expect(await workouts.listWorkoutNamesUsingExercise('ex1'), ['Strength']);

      await exercises.deleteExercise('ex1');

      expect(await exercises.listExercises(), isEmpty);
      expect(await workouts.listWorkoutNamesUsingExercise('ex1'), isEmpty);
      final List<Workout> loadedWorkouts = await workouts.listWorkouts();
      expect(loadedWorkouts, hasLength(1));
      expect(loadedWorkouts.single.entries, isEmpty);
    });
  });

  group('WorkoutStore', () {
    test('round-trips entries in order with all fields', () async {
      await exercises.saveExercise(Exercise(id: 'ex1', name: 'A', description: ''));
      await exercises.saveExercise(Exercise(id: 'ex2', name: 'B', description: ''));
      await workouts.saveWorkout(
        Workout(
          id: 'w1',
          name: 'Mixed',
          entries: [
            WorkoutExerciseEntry(
              exerciseId: 'ex1',
              sets: 3,
              mode: ExerciseMode.duration,
              durationSeconds: 7,
              restSeconds: 180,
              targetForceMode: TargetForceMode.relativePercent,
              targetForceValue: 85.5,
              startingHand: ExerciseHand.right,
            ),
            WorkoutExerciseEntry(
              exerciseId: 'ex2',
              sets: 1,
              mode: ExerciseMode.reps,
              reps: 5,
              restSeconds: 60,
              targetForceMode: TargetForceMode.absoluteKg,
              targetForceValue: 40,
            ),
          ],
        ),
      );

      final List<Workout> loaded = await workouts.listWorkouts();
      expect(loaded, hasLength(1));
      final Workout workout = loaded.single;
      expect(workout.name, 'Mixed');
      expect(workout.entries, hasLength(2));

      final WorkoutExerciseEntry first = workout.entries[0];
      expect(first.exerciseId, 'ex1');
      expect(first.sets, 3);
      expect(first.mode, ExerciseMode.duration);
      expect(first.durationSeconds, 7);
      expect(first.restSeconds, 180);
      expect(first.targetForceMode, TargetForceMode.relativePercent);
      expect(first.targetForceValue, 85.5);
      expect(first.startingHand, ExerciseHand.right);

      final WorkoutExerciseEntry second = workout.entries[1];
      expect(second.exerciseId, 'ex2');
      expect(second.mode, ExerciseMode.reps);
      expect(second.reps, 5);
    });

    test('deleteWorkout removes entries but not exercises', () async {
      await exercises.saveExercise(Exercise(id: 'ex1', name: 'A', description: ''));
      await workouts.saveWorkout(
        Workout(
          id: 'w1',
          name: 'Gone',
          entries: [
            WorkoutExerciseEntry(
              exerciseId: 'ex1',
              sets: 1,
              mode: ExerciseMode.reps,
              reps: 3,
              restSeconds: 30,
            ),
          ],
        ),
      );

      await workouts.deleteWorkout('w1');

      expect(await workouts.listWorkouts(), isEmpty);
      expect(await exercises.listExercises(), hasLength(1));
    });
  });

  group('SessionStore', () {
    final SetLog log1 = SetLog(
      entryIndex: 0,
      setNumber: 1,
      exerciseId: 'ex1',
      exerciseName: 'Hang',
      hand: ExerciseHand.left,
      targetForceKg: 80,
      plannedDurationSeconds: 7,
      plannedReps: 0,
      actualDurationSeconds: 7,
      peakForceKg: 95,
    );
    final SetLog log2 = SetLog(
      entryIndex: 0,
      setNumber: 1,
      exerciseId: 'ex1',
      exerciseName: 'Hang',
      hand: ExerciseHand.right,
      targetForceKg: 88,
      plannedDurationSeconds: 7,
      plannedReps: 0,
      actualDurationSeconds: 5,
      peakForceKg: 101,
    );

    test('saves and loads sessions with set logs', () async {
      final int id = await sessions.saveSession(
        workoutId: 'w1',
        workoutName: 'Strength',
        startedAt: DateTime(2026, 7, 29, 10),
        finishedAt: DateTime(2026, 7, 29, 10, 30),
        completed: true,
        logs: [log1, log2],
      );

      final List<WorkoutSession> list = await sessions.listSessions();
      expect(list, hasLength(1));
      expect(list.single.workoutName, 'Strength');
      expect(list.single.completed, isTrue);
      expect(list.single.setCount, 2);

      final WorkoutSession? detail = await sessions.getSession(id);
      expect(detail, isNotNull);
      expect(detail!.setLogs, hasLength(2));
      expect(detail.setLogs[0].hand, ExerciseHand.left);
      expect(detail.setLogs[0].peakForceKg, 95);
      expect(detail.setLogs[1].targetForceKg, 88);
    });

    test('listLogsForExercise returns logs newest first with session date', () async {
      await sessions.saveSession(
        workoutId: 'w1',
        workoutName: 'Old',
        startedAt: DateTime(2026, 7, 1, 10),
        finishedAt: DateTime(2026, 7, 1, 10, 30),
        completed: true,
        logs: [log1],
      );
      await sessions.saveSession(
        workoutId: 'w1',
        workoutName: 'New',
        startedAt: DateTime(2026, 7, 29, 10),
        finishedAt: DateTime(2026, 7, 29, 10, 30),
        completed: false,
        logs: [log2],
      );

      final List<SetLog> logs = await sessions.listLogsForExercise('ex1');
      expect(logs, hasLength(2));
      expect(logs.first.sessionStartedAt, DateTime(2026, 7, 29, 10));
      expect(logs.last.sessionStartedAt, DateTime(2026, 7, 1, 10));
    });

    test('history survives workout deletion (no FK to workouts)', () async {
      await exercises.saveExercise(Exercise(id: 'ex1', name: 'A', description: ''));
      await workouts.saveWorkout(
        Workout(
          id: 'w1',
          name: 'Strength',
          entries: [
            WorkoutExerciseEntry(
              exerciseId: 'ex1',
              sets: 1,
              mode: ExerciseMode.duration,
              durationSeconds: 7,
              restSeconds: 60,
            ),
          ],
        ),
      );
      await sessions.saveSession(
        workoutId: 'w1',
        workoutName: 'Strength',
        startedAt: DateTime(2026, 7, 29, 10),
        finishedAt: DateTime(2026, 7, 29, 10, 30),
        completed: true,
        logs: [log1],
      );

      await workouts.deleteWorkout('w1');

      final List<WorkoutSession> list = await sessions.listSessions();
      expect(list, hasLength(1));
      expect(list.single.workoutName, 'Strength');
    });

    test('deleteSession removes the session and its logs', () async {
      final int id = await sessions.saveSession(
        workoutId: 'w1',
        workoutName: 'Strength',
        startedAt: DateTime(2026, 7, 29, 10),
        finishedAt: DateTime(2026, 7, 29, 10, 30),
        completed: true,
        logs: [log1, log2],
      );

      await sessions.deleteSession(id);

      expect(await sessions.listSessions(), isEmpty);
      expect(await sessions.getSession(id), isNull);
      expect(await sessions.listLogsForExercise('ex1'), isEmpty);
    });
  });
}
