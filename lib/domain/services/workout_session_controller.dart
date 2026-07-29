import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/models/set_log.dart';
import 'package:pullcrane/domain/models/workout.dart';

enum SessionPhase { waitingForForce, activeSet, resting, finished }

/// Immutable knobs for a workout session, usually built from AppSettings.
class WorkoutSessionConfig {
  const WorkoutSessionConfig({
    required this.forceThresholdKg,
    required this.targetHysteresisKg,
    required this.requireZeroBeforeSetStart,
    required this.maxForceKg,
    this.fallbackMaxLiftKg = 60,
  });

  /// Force that must be reached to start a set.
  final int forceThresholdKg;

  /// Tolerance band around the target force.
  final int targetHysteresisKg;

  /// When true, force must return to 0 before a new set can be started.
  final bool requireZeroBeforeSetStart;

  /// Upper clamp for force readings and resolved targets.
  final int maxForceKg;

  /// Used for relative targets when an exercise has no benchmark yet.
  final int fallbackMaxLiftKg;
}

/// Pure state machine driving a guided workout session.
///
/// Contains no timers and no widget code: the UI feeds it force readings via
/// [onForceChanged] and time via [tick], both with explicit timestamps, which
/// makes the whole flow unit-testable and immune to timer drift when the app
/// is backgrounded (all countdowns are anchored to wall-clock end times).
class WorkoutSessionController extends ChangeNotifier {
  WorkoutSessionController({
    required this.workout,
    required this.exercisesById,
    required this.config,
  });

  final Workout workout;
  final Map<String, Exercise> exercisesById;
  final WorkoutSessionConfig config;

  /// Fired exactly once when the last entry of a non-empty workout completes
  /// (e.g. for confetti). Not fired for empty workouts.
  VoidCallback? onFinished;

  SessionPhase _phase = SessionPhase.waitingForForce;
  SessionPhase get phase => _phase;

  int currentEntryIndex = 0;
  int currentSet = 1;
  int currentForce = 0;
  bool setStartArmed = false;
  ExerciseHand? activeHand;
  ExerciseHand? suggestedSwitchHand;
  ExerciseHand? _pendingHandInSet;

  DateTime _now = DateTime.now();
  DateTime? _setStartedAt;
  DateTime? _setEndsAt;
  DateTime? _restEndsAt;
  int _plannedSetSeconds = 0;
  int _setPeakForce = 0;

  /// Wall-clock moment at which each hand finishes resting. Persists across
  /// entries on purpose: leftover rest debt carries over (see plan.md).
  final Map<ExerciseHand, DateTime> _handRestedAt = <ExerciseHand, DateTime>{};

  /// Completed sets of this session, oldest first.
  final List<SetLog> setLogs = <SetLog>[];

  WorkoutExerciseEntry? get currentEntry {
    if (currentEntryIndex >= workout.entries.length) {
      return null;
    }
    return workout.entries[currentEntryIndex];
  }

  Exercise? get currentExercise {
    final WorkoutExerciseEntry? entry = currentEntry;
    if (entry == null) {
      return null;
    }
    return exercisesById[entry.exerciseId];
  }

  bool get isUsingFallbackMaxLift {
    final Exercise? exercise = currentExercise;
    final WorkoutExerciseEntry? entry = currentEntry;
    if (exercise == null ||
        entry == null ||
        entry.targetForceMode != TargetForceMode.relativePercent) {
      return false;
    }
    return _effectiveMaxLift(exercise, entry).isFallback;
  }

  int get targetForceKg => _resolveTargetForceKg(currentExercise, currentEntry);

  int get targetMinForceKg =>
      max(0, targetForceKg - config.targetHysteresisKg);

  int get targetMaxForceKg =>
      min(config.maxForceKg, targetForceKg + config.targetHysteresisKg);

  bool get isInTargetZone =>
      currentForce >= targetMinForceKg && currentForce <= targetMaxForceKg;

  int get remainingSetSeconds => _secondsUntil(_setEndsAt);

  int get remainingRestSeconds {
    if (_phase == SessionPhase.resting && suggestedSwitchHand != null) {
      return remainingRestForHand(suggestedSwitchHand!);
    }
    return _secondsUntil(_restEndsAt);
  }

  int remainingRestForHand(ExerciseHand hand) =>
      _secondsUntil(_handRestedAt[hand]);

  int _secondsUntil(DateTime? end) {
    if (end == null) {
      return 0;
    }
    final int millis = end.difference(_now).inMilliseconds;
    return millis <= 0 ? 0 : (millis + 999) ~/ 1000;
  }

  /// Starts the session. An empty workout finishes immediately without
  /// firing [onFinished].
  void start(DateTime now) {
    _now = now;
    if (workout.entries.isEmpty) {
      _phase = SessionPhase.finished;
      return;
    }
    _prepareCurrentSet();
  }

  /// Feeds a new force reading (kg). Safe to call at any rate.
  void onForceChanged(int force, DateTime now) {
    _now = now;
    currentForce = force.clamp(0, config.maxForceKg);

    if (_phase == SessionPhase.activeSet && currentForce > _setPeakForce) {
      _setPeakForce = currentForce;
    }

    if (_phase == SessionPhase.waitingForForce) {
      if (config.requireZeroBeforeSetStart && currentForce == 0) {
        setStartArmed = true;
      } else {
        _attemptStart(now);
      }
    }
    notifyListeners();
  }

  /// Advances time-based transitions. Call regularly (e.g. every 200 ms)
  /// while the page is visible. Transitions are anchored to their scheduled
  /// end times and chained, so a long gap (app backgrounded) lands in the
  /// correct state immediately.
  void tick(DateTime now) {
    _now = now;
    for (var i = 0; i < 8; i++) {
      if (!_stepTimeTransition()) {
        break;
      }
    }
    notifyListeners();
  }

  /// Performs at most one time-based transition. Returns true when a
  /// transition happened and another one might be due.
  bool _stepTimeTransition() {
    if (_phase == SessionPhase.activeSet &&
        _setEndsAt != null &&
        !_now.isBefore(_setEndsAt!)) {
      // Anchor the completion to the scheduled end, not to the tick time,
      // so rest periods start exactly when the set ended.
      _completeCurrentSet(_setEndsAt!);
      return true;
    }
    if (_phase == SessionPhase.resting) {
      if (suggestedSwitchHand == null) {
        if (_restEndsAt != null && !_now.isBefore(_restEndsAt!)) {
          _advance(_now);
          return true;
        }
      } else if (remainingRestForHand(suggestedSwitchHand!) <= 0) {
        _advance(_now);
        return true;
      }
    }
    return false;
  }

  /// User pressed "Complete set" / "Finish set early".
  void completeCurrentSet(DateTime now) {
    if (_phase != SessionPhase.activeSet) {
      return;
    }
    _completeCurrentSet(now);
    notifyListeners();
  }

  /// User pressed "Skip rest". Only plain rests can be skipped; auto
  /// hand-switch rests run to completion.
  void skipRest(DateTime now) {
    if (_phase != SessionPhase.resting || suggestedSwitchHand != null) {
      return;
    }
    _advance(now);
    notifyListeners();
  }

  /// Skips the whole current entry (used when its exercise reference is
  /// missing and the set can never be performed).
  void skipEntry(DateTime now) {
    _now = now;
    if (_phase == SessionPhase.finished || currentEntry == null) {
      return;
    }
    _advanceToNextEntry();
    notifyListeners();
  }

  void _attemptStart(DateTime now) {
    if (_phase != SessionPhase.waitingForForce || !setStartArmed) {
      return;
    }
    if (currentForce < config.forceThresholdKg) {
      return;
    }

    final WorkoutExerciseEntry? entry = currentEntry;
    if (entry == null) {
      return;
    }

    setStartArmed = false;
    _phase = SessionPhase.activeSet;
    _setStartedAt = now;
    _setPeakForce = currentForce;

    if (entry.mode == ExerciseMode.duration) {
      if (_plannedSetSeconds <= 0) {
        _completeCurrentSet(now);
        return;
      }
      _setEndsAt = now.add(Duration(seconds: _plannedSetSeconds));
    }
  }

  void _completeCurrentSet(DateTime now) {
    final WorkoutExerciseEntry? entry = currentEntry;
    final Exercise? exercise = currentExercise;
    final ExerciseHand? completedHand =
        exercise?.isSideSwitching == true ? activeHand : null;

    _setEndsAt = null;

    if (entry == null || exercise == null) {
      _advance(now);
      return;
    }

    setLogs.add(
      SetLog(
        entryIndex: currentEntryIndex,
        setNumber: currentSet,
        exerciseId: entry.exerciseId,
        exerciseName: exercise.name,
        hand: completedHand,
        targetForceKg: _resolveTargetForceKg(exercise, entry),
        plannedDurationSeconds: entry.mode == ExerciseMode.duration
            ? (entry.durationSeconds ?? 0)
            : 0,
        plannedReps: entry.mode == ExerciseMode.reps ? (entry.reps ?? 0) : 0,
        actualDurationSeconds: _setStartedAt == null
            ? 0
            : max(0, now.difference(_setStartedAt!).inSeconds),
        peakForceKg: _setPeakForce,
      ),
    );

    if (completedHand != null) {
      _handRestedAt[completedHand] = now.add(
        Duration(seconds: entry.restSeconds),
      );
    }

    final ExerciseHand? switchTarget = _resolveSwitchTarget(
      exercise: exercise,
      entry: entry,
      completedHand: completedHand,
    );

    if (!_hasMoreWorkAfterCurrentCompletion(
      entry: entry,
      switchTarget: switchTarget,
    )) {
      _advance(now);
      return;
    }

    final int effectiveRestSeconds = switchTarget != null
        ? remainingRestForHand(switchTarget)
        : entry.restSeconds;

    if (effectiveRestSeconds <= 0) {
      _advance(now);
      return;
    }

    _phase = SessionPhase.resting;
    suggestedSwitchHand = switchTarget;
    setStartArmed = false;
    _restEndsAt = switchTarget == null
        ? now.add(Duration(seconds: effectiveRestSeconds))
        : null;
  }

  ExerciseHand? _resolveSwitchTarget({
    required Exercise exercise,
    required WorkoutExerciseEntry entry,
    required ExerciseHand? completedHand,
  }) {
    if (!exercise.isSideSwitching || completedHand == null) {
      return null;
    }

    if (completedHand == entry.startingHand) {
      _pendingHandInSet = _oppositeHand(completedHand);
    } else {
      _pendingHandInSet = null;
    }

    if (_pendingHandInSet != null) {
      return _pendingHandInSet;
    }

    if (currentSet < entry.sets) {
      // Both hands completed this set, next set starts from starting hand.
      return entry.startingHand;
    }

    return null;
  }

  bool _hasMoreWorkAfterCurrentCompletion({
    required WorkoutExerciseEntry entry,
    required ExerciseHand? switchTarget,
  }) {
    if (switchTarget != null) {
      return true;
    }
    if (currentSet < entry.sets) {
      return true;
    }
    return currentEntryIndex < workout.entries.length - 1;
  }

  void _advance(DateTime now) {
    _restEndsAt = null;

    final WorkoutExerciseEntry? entry = currentEntry;
    final Exercise? exercise = currentExercise;

    if (exercise != null &&
        exercise.isSideSwitching &&
        _pendingHandInSet != null) {
      activeHand = _pendingHandInSet;
      _pendingHandInSet = null;
      suggestedSwitchHand = null;
      setStartArmed = false;
      _prepareCurrentSet();
      return;
    }

    if (entry == null) {
      _finish();
      return;
    }

    if (currentSet < entry.sets) {
      currentSet++;
      suggestedSwitchHand = null;
      activeHand =
          exercise?.isSideSwitching == true ? entry.startingHand : null;
      _pendingHandInSet = null;
      setStartArmed = false;
      _prepareCurrentSet();
      return;
    }

    _advanceToNextEntry();
  }

  void _advanceToNextEntry() {
    currentEntryIndex++;
    currentSet = 1;
    suggestedSwitchHand = null;
    activeHand = null;
    _pendingHandInSet = null;
    setStartArmed = false;

    if (currentEntry == null) {
      _finish();
      return;
    }
    _prepareCurrentSet();
  }

  void _finish() {
    _phase = SessionPhase.finished;
    suggestedSwitchHand = null;
    activeHand = null;
    _pendingHandInSet = null;
    setStartArmed = false;
    onFinished?.call();
  }

  void _prepareCurrentSet() {
    final WorkoutExerciseEntry? entry = currentEntry;
    final Exercise? exercise = currentExercise;

    _setEndsAt = null;
    _restEndsAt = null;
    _setStartedAt = null;
    _setPeakForce = 0;

    if (entry == null) {
      _finish();
      return;
    }

    _plannedSetSeconds = entry.durationSeconds ?? 0;

    if (exercise == null) {
      _phase = SessionPhase.waitingForForce;
      suggestedSwitchHand = null;
      activeHand = null;
      _pendingHandInSet = null;
      setStartArmed =
          config.requireZeroBeforeSetStart ? currentForce == 0 : true;
      return;
    }

    if (exercise.isSideSwitching) {
      activeHand ??= entry.startingHand;
    } else {
      activeHand = null;
      _pendingHandInSet = null;
    }

    _phase = SessionPhase.waitingForForce;
    suggestedSwitchHand = null;
    setStartArmed =
        config.requireZeroBeforeSetStart ? currentForce == 0 : true;
  }

  int _resolveTargetForceKg(Exercise? exercise, WorkoutExerciseEntry? entry) {
    if (exercise == null || entry == null) {
      return config.forceThresholdKg;
    }
    if (entry.targetForceMode == TargetForceMode.relativePercent) {
      final ({int kg, bool isFallback}) effective =
          _effectiveMaxLift(exercise, entry);
      final double relativeKg = (effective.kg * entry.targetForceValue) / 100;
      return relativeKg.round().clamp(0, config.maxForceKg);
    }
    return entry.targetForceValue.round().clamp(0, config.maxForceKg);
  }

  ({int kg, bool isFallback}) _effectiveMaxLift(
    Exercise exercise,
    WorkoutExerciseEntry entry,
  ) {
    final ExerciseHand primaryHand = exercise.isSideSwitching
        ? (activeHand ?? entry.startingHand)
        : entry.startingHand;
    final ExerciseHand secondaryHand = _oppositeHand(primaryHand);

    final int primaryMaxLift = _maxLiftForHand(exercise, primaryHand);
    if (primaryMaxLift > 0) {
      return (kg: primaryMaxLift, isFallback: false);
    }

    final int secondaryMaxLift = _maxLiftForHand(exercise, secondaryHand);
    if (secondaryMaxLift > 0) {
      return (kg: secondaryMaxLift, isFallback: false);
    }

    return (kg: config.fallbackMaxLiftKg, isFallback: true);
  }

  int _maxLiftForHand(Exercise exercise, ExerciseHand hand) {
    return hand == ExerciseHand.left
        ? exercise.maxLiftLeftKg
        : exercise.maxLiftRightKg;
  }

  ExerciseHand _oppositeHand(ExerciseHand hand) {
    return hand == ExerciseHand.left ? ExerciseHand.right : ExerciseHand.left;
  }
}
