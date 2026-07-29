import 'package:flutter_test/flutter_test.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/models/workout.dart';
import 'package:pullcrane/domain/services/workout_session_controller.dart';

final DateTime t0 = DateTime(2026, 7, 29, 12);

DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

Exercise makeExercise({
  String id = 'ex1',
  bool sideSwitching = false,
  int maxLeft = 100,
  int maxRight = 110,
}) {
  return Exercise(
    id: id,
    name: 'Exercise $id',
    description: '',
    isSideSwitching: sideSwitching,
    maxLiftLeftKg: maxLeft,
    maxLiftRightKg: maxRight,
  );
}

WorkoutExerciseEntry makeEntry({
  String exerciseId = 'ex1',
  int sets = 1,
  ExerciseMode mode = ExerciseMode.duration,
  int? reps,
  int? durationSeconds = 7,
  int restSeconds = 180,
  TargetForceMode targetForceMode = TargetForceMode.absoluteKg,
  double targetForceValue = 50,
  ExerciseHand startingHand = ExerciseHand.left,
}) {
  return WorkoutExerciseEntry(
    exerciseId: exerciseId,
    sets: sets,
    mode: mode,
    reps: reps,
    durationSeconds: durationSeconds,
    restSeconds: restSeconds,
    targetForceMode: targetForceMode,
    targetForceValue: targetForceValue,
    startingHand: startingHand,
  );
}

WorkoutSessionController makeController({
  required Workout workout,
  Map<String, Exercise>? exercises,
  WorkoutSessionConfig? config,
  void Function()? onFinished,
}) {
  final controller = WorkoutSessionController(
    workout: workout,
    exercisesById: exercises ?? {'ex1': makeExercise()},
    config: config ??
        const WorkoutSessionConfig(
          forceThresholdKg: 10,
          targetHysteresisKg: 2,
          requireZeroBeforeSetStart: false,
          maxForceKg: 200,
        ),
  );
  controller.onFinished = onFinished;
  return controller;
}

void main() {
  group('session start', () {
    test('empty workout finishes immediately without onFinished', () {
      var finishedFired = false;
      final controller = makeController(
        workout: Workout(id: 'w1', name: 'W', entries: const []),
        onFinished: () => finishedFired = true,
      );
      controller.start(t0);
      expect(controller.phase, SessionPhase.finished);
      expect(finishedFired, isFalse);
    });

    test('starts waiting for force on first entry', () {
      final controller = makeController(
        workout: Workout(id: 'w1', name: 'W', entries: [makeEntry()]),
      );
      controller.start(t0);
      expect(controller.phase, SessionPhase.waitingForForce);
      expect(controller.currentEntryIndex, 0);
      expect(controller.currentSet, 1);
    });
  });

  group('set start trigger', () {
    test('duration set starts at threshold and counts down by wall clock', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [makeEntry(sets: 2, durationSeconds: 7)],
        ),
      );
      controller.start(t0);

      controller.onForceChanged(5, t0);
      expect(controller.phase, SessionPhase.waitingForForce);

      controller.onForceChanged(10, t0);
      expect(controller.phase, SessionPhase.activeSet);
      expect(controller.remainingSetSeconds, 7);

      controller.tick(at(3));
      expect(controller.phase, SessionPhase.activeSet);
      expect(controller.remainingSetSeconds, 4);

      // Rest is 180s, so after the first of two sets the session rests.
      controller.tick(at(7));
      expect(controller.phase, SessionPhase.resting);
      expect(controller.remainingRestSeconds, 180);
    });

    test('requires release to zero before arming when configured', () {
      final controller = makeController(
        workout: Workout(id: 'w1', name: 'W', entries: [makeEntry()]),
        config: const WorkoutSessionConfig(
          forceThresholdKg: 10,
          targetHysteresisKg: 2,
          requireZeroBeforeSetStart: true,
          maxForceKg: 200,
        ),
      );

      // The user is already pulling 50 kg when the set is prepared, so the
      // trigger must not be armed.
      controller.onForceChanged(50, t0);
      controller.start(at(1));
      expect(controller.phase, SessionPhase.waitingForForce);
      expect(controller.setStartArmed, isFalse);

      // Continuing to pull must not start the set.
      controller.onForceChanged(50, at(2));
      expect(controller.phase, SessionPhase.waitingForForce);

      // Release to zero arms the trigger.
      controller.onForceChanged(0, at(3));
      expect(controller.setStartArmed, isTrue);
      expect(controller.phase, SessionPhase.waitingForForce);

      controller.onForceChanged(12, at(4));
      expect(controller.phase, SessionPhase.activeSet);
    });

    test('reps set starts immediately at threshold without a timer', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [
            makeEntry(
              mode: ExerciseMode.reps,
              reps: 5,
              durationSeconds: null,
              restSeconds: 0,
            ),
          ],
        ),
      );
      controller.start(t0);
      controller.onForceChanged(15, t0);
      expect(controller.phase, SessionPhase.activeSet);
      expect(controller.remainingSetSeconds, 0);

      // Time passing does nothing; completion is manual.
      controller.tick(at(60));
      expect(controller.phase, SessionPhase.activeSet);

      controller.completeCurrentSet(at(65));
      expect(controller.phase, SessionPhase.finished);
    });
  });

  group('timed set completion', () {
    test('force drop during timed set does not pause the timer', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [makeEntry(durationSeconds: 7, restSeconds: 0)],
        ),
      );
      controller.start(t0);
      controller.onForceChanged(30, t0);
      expect(controller.phase, SessionPhase.activeSet);

      controller.onForceChanged(0, at(3));
      controller.tick(at(7));
      // restSeconds == 0 and single set -> straight to finished.
      expect(controller.phase, SessionPhase.finished);
    });

    test('finish set early records actual duration and peak force', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [makeEntry(durationSeconds: 7, restSeconds: 0)],
        ),
      );
      controller.start(t0);
      controller.onForceChanged(30, t0);
      controller.onForceChanged(44, at(2));
      controller.completeCurrentSet(at(3));

      expect(controller.phase, SessionPhase.finished);
      expect(controller.setLogs, hasLength(1));
      expect(controller.setLogs.single.actualDurationSeconds, 3);
      expect(controller.setLogs.single.plannedDurationSeconds, 7);
      expect(controller.setLogs.single.peakForceKg, 44);
      expect(controller.setLogs.single.targetForceKg, 50);
    });

    test('double completion is guarded', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [makeEntry(durationSeconds: 7, restSeconds: 0)],
        ),
      );
      controller.start(t0);
      controller.onForceChanged(30, t0);
      controller.completeCurrentSet(at(3));
      controller.completeCurrentSet(at(3));
      expect(controller.setLogs, hasLength(1));
    });
  });

  group('rest and progression', () {
    test('rest counts down and advances to the next set', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [makeEntry(sets: 2, durationSeconds: 7, restSeconds: 60)],
        ),
      );
      controller.start(t0);
      controller.onForceChanged(30, t0);
      controller.tick(at(7));
      expect(controller.phase, SessionPhase.resting);

      controller.tick(at(7 + 59));
      expect(controller.phase, SessionPhase.resting);
      expect(controller.remainingRestSeconds, 1);

      controller.tick(at(7 + 60));
      expect(controller.phase, SessionPhase.waitingForForce);
      expect(controller.currentSet, 2);
      expect(controller.currentEntryIndex, 0);
    });

    test('skip rest advances immediately', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [makeEntry(sets: 2, durationSeconds: 7, restSeconds: 60)],
        ),
      );
      controller.start(t0);
      controller.onForceChanged(30, t0);
      controller.tick(at(7));
      expect(controller.phase, SessionPhase.resting);

      controller.skipRest(at(8));
      expect(controller.phase, SessionPhase.waitingForForce);
      expect(controller.currentSet, 2);
    });

    test('advances across entries and fires onFinished at the end', () {
      var finishedFired = false;
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [
            makeEntry(exerciseId: 'ex1', restSeconds: 0),
            makeEntry(exerciseId: 'ex2', restSeconds: 0),
          ],
        ),
        exercises: {'ex1': makeExercise(id: 'ex1'), 'ex2': makeExercise(id: 'ex2')},
        onFinished: () => finishedFired = true,
      );
      controller.start(t0);

      controller.onForceChanged(30, t0);
      controller.tick(at(7));
      expect(controller.currentEntryIndex, 1);
      expect(controller.currentSet, 1);
      expect(controller.phase, SessionPhase.waitingForForce);

      controller.onForceChanged(30, at(10));
      controller.tick(at(17));
      expect(controller.phase, SessionPhase.finished);
      expect(finishedFired, isTrue);
      expect(controller.setLogs, hasLength(2));
    });
  });

  group('hand switching', () {
    test('switches hands without rest for a fresh hand, then finishes', () {
      var finishedFired = false;
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [
            makeEntry(
              sets: 1,
              durationSeconds: 7,
              restSeconds: 180,
            ),
          ],
        ),
        exercises: {'ex1': makeExercise(sideSwitching: true)},
        onFinished: () => finishedFired = true,
      );
      controller.start(t0);
      expect(controller.activeHand, ExerciseHand.left);

      // Complete left hand. The right hand has no rest debt, so the switch
      // happens immediately.
      controller.onForceChanged(30, t0);
      controller.tick(at(7));
      expect(controller.phase, SessionPhase.waitingForForce);
      expect(controller.activeHand, ExerciseHand.right);

      // Complete right hand. Set count is 1, so the workout is done.
      controller.onForceChanged(0, at(8));
      controller.onForceChanged(30, at(9));
      controller.tick(at(16));
      expect(controller.phase, SessionPhase.finished);
      expect(finishedFired, isTrue);
      expect(controller.setLogs, hasLength(2));
      expect(controller.setLogs[0].hand, ExerciseHand.left);
      expect(controller.setLogs[1].hand, ExerciseHand.right);
    });

    test('rest before returning to the starting hand is the leftover rest', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [
            makeEntry(sets: 2, durationSeconds: 7, restSeconds: 180),
          ],
        ),
        exercises: {'ex1': makeExercise(sideSwitching: true)},
      );
      controller.start(t0);

      // Left hand set: t0 .. t0+7. Left rests until t0+7+180.
      controller.onForceChanged(30, t0);
      controller.tick(at(7));
      expect(controller.activeHand, ExerciseHand.right);

      // Right hand set: t0+8 .. t0+15.
      controller.onForceChanged(30, at(8));
      controller.tick(at(15));

      // Next is left hand again (set 2). Left has already rested 8 of its
      // 180 seconds, so the remaining rest is 172s.
      expect(controller.phase, SessionPhase.resting);
      expect(controller.suggestedSwitchHand, ExerciseHand.left);
      expect(controller.remainingRestSeconds, 172);

      // Auto-switch rests cannot be skipped manually.
      controller.skipRest(at(20));
      expect(controller.phase, SessionPhase.resting);

      controller.tick(at(7 + 180));
      expect(controller.phase, SessionPhase.waitingForForce);
      expect(controller.activeHand, ExerciseHand.left);
      expect(controller.currentSet, 2);
    });
  });

  group('missing exercise', () {
    test('entry with unknown exercise can be skipped entirely', () {
      var finishedFired = false;
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [
            makeEntry(exerciseId: 'ghost', sets: 3),
            makeEntry(exerciseId: 'ex1', restSeconds: 0),
          ],
        ),
        exercises: {'ex1': makeExercise(id: 'ex1')},
        onFinished: () => finishedFired = true,
      );
      controller.start(t0);

      expect(controller.currentExercise, isNull);
      expect(controller.phase, SessionPhase.waitingForForce);

      controller.skipEntry(t0);
      expect(controller.currentEntryIndex, 1);
      expect(controller.currentSet, 1);
      expect(controller.currentExercise, isNotNull);

      controller.onForceChanged(30, at(1));
      controller.tick(at(8));
      expect(controller.phase, SessionPhase.finished);
      expect(finishedFired, isTrue);
      // The skipped entry produced no set logs.
      expect(controller.setLogs, hasLength(1));
    });

    test('skipping the last entry finishes the workout', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [makeEntry(exerciseId: 'ghost')],
        ),
        exercises: const {},
      );
      controller.start(t0);
      controller.skipEntry(t0);
      expect(controller.phase, SessionPhase.finished);
    });
  });

  group('target force resolution', () {
    test('absolute target is clamped to maxForceKg', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [
            makeEntry(
              targetForceMode: TargetForceMode.absoluteKg,
              targetForceValue: 250,
            ),
          ],
        ),
      );
      controller.start(t0);
      expect(controller.targetForceKg, 200);
    });

    test('relative target uses the active hand max lift', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [
            makeEntry(
              targetForceMode: TargetForceMode.relativePercent,
              targetForceValue: 80,
            ),
          ],
        ),
        exercises: {
          'ex1': makeExercise(sideSwitching: true, maxLeft: 100, maxRight: 110),
        },
      );
      controller.start(t0);
      // Starting hand is left (100 kg max).
      expect(controller.targetForceKg, 80);
      expect(controller.isUsingFallbackMaxLift, isFalse);

      // Complete the left-hand set; right hand becomes active (110 kg max).
      controller.onForceChanged(30, t0);
      controller.tick(at(7));
      expect(controller.activeHand, ExerciseHand.right);
      expect(controller.targetForceKg, 88);
    });

    test('relative target without benchmark uses the flagged fallback', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [
            makeEntry(
              targetForceMode: TargetForceMode.relativePercent,
              targetForceValue: 80,
            ),
          ],
        ),
        exercises: {'ex1': makeExercise(maxLeft: 0, maxRight: 0)},
      );
      controller.start(t0);
      expect(controller.targetForceKg, 48); // 80% of 60 kg fallback
      expect(controller.isUsingFallbackMaxLift, isTrue);
    });

    test('target band respects hysteresis around the resolved target', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [makeEntry(targetForceValue: 50)],
        ),
      );
      controller.start(t0);
      expect(controller.targetMinForceKg, 48);
      expect(controller.targetMaxForceKg, 52);

      controller.onForceChanged(49, t0);
      expect(controller.isInTargetZone, isTrue);
      controller.onForceChanged(60, at(1));
      expect(controller.isInTargetZone, isFalse);
    });
  });

  group('wall-clock robustness', () {
    test('a long tick gap (app backgrounded) completes sets on schedule', () {
      final controller = makeController(
        workout: Workout(
          id: 'w1',
          name: 'W',
          entries: [makeEntry(sets: 2, durationSeconds: 7, restSeconds: 60)],
        ),
      );
      controller.start(t0);
      controller.onForceChanged(30, t0);
      expect(controller.phase, SessionPhase.activeSet);

      // Simulate the app being suspended for 30 seconds mid-set. The set
      // ended at t0+7, so the 60s rest is anchored there, not at the tick.
      controller.tick(at(30));
      expect(controller.phase, SessionPhase.resting);
      expect(controller.remainingRestSeconds, 37);

      // Another suspension past the rest: the next set is due immediately.
      controller.tick(at(120));
      expect(controller.phase, SessionPhase.waitingForForce);
      expect(controller.currentSet, 2);
      expect(controller.currentEntryIndex, 0);
    });
  });
}
