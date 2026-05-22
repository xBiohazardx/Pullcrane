import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/models/workout.dart';
import 'package:pullcrane/ui/force_chart.dart';
import 'package:pullcrane/ui/force_input_dummy.dart';

enum SessionPhase { waitingForForce, activeSet, resting, finished }

class ActiveWorkoutPage extends StatefulWidget {
  const ActiveWorkoutPage({
    super.key,
    required this.workout,
    required this.exercisesById,
    required this.forceThresholdKg,
    required this.targetHysteresisKg,
    required this.userMaxLiftKg,
    required this.enableTargetHaptics,
    required this.requireZeroBeforeSetStart,
  });

  final Workout workout;
  final Map<String, Exercise> exercisesById;
  final int forceThresholdKg;
  final int targetHysteresisKg;
  final int userMaxLiftKg;
  final bool enableTargetHaptics;
  final bool requireZeroBeforeSetStart;

  @override
  State<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends State<ActiveWorkoutPage> {
  static const int minForceKg = 0;
  static const int maxForceKg = 100;
  static const double dummySensitivity = 0.3;
  static const Duration targetVibrationInterval = Duration(milliseconds: 280);

  List<FlSpot> dataPoints = List<FlSpot>.empty(growable: true);
  int currentEntryIndex = 0;
  int currentSet = 1;
  int currentForce = 0;
  int maxForce = 0;
  int timeIndex = 0;
  int remainingSetSeconds = 0;
  int remainingRestSeconds = 0;
  SessionPhase phase = SessionPhase.finished;
  bool isInTargetRange = false;
  Timer? chartTimer;
  Timer? handRestTimer;
  Timer? phaseTimer;
  Timer? targetVibrationTimer;
  ExerciseHand? suggestedSwitchHand;
  ExerciseHand? activeHand;
  ExerciseHand? pendingHandInSet;
  bool setStartArmed = false;
  final Map<ExerciseHand, int> handRemainingRest = <ExerciseHand, int>{
    ExerciseHand.left: 0,
    ExerciseHand.right: 0,
  };

  ExerciseHand _oppositeHand(ExerciseHand hand) {
    return hand == ExerciseHand.left ? ExerciseHand.right : ExerciseHand.left;
  }

  bool _isLastEntry() {
    return currentEntryIndex >= widget.workout.entries.length - 1;
  }

  ExerciseHand? _resolveSwitchTarget({
    required Exercise exercise,
    required WorkoutExerciseEntry entry,
    required ExerciseHand? completedHand,
  }) {
    if (!exercise.isSideSwitching || completedHand == null) {
      return null;
    }

    if (completedHand == exercise.startingHand) {
      pendingHandInSet = _oppositeHand(completedHand);
    } else {
      pendingHandInSet = null;
    }

    if (pendingHandInSet != null) {
      return pendingHandInSet;
    }

    if (currentSet < entry.sets) {
      // Both hands completed this set, next set starts from starting hand.
      return exercise.startingHand;
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
    return !_isLastEntry();
  }

  String _handLabel(ExerciseHand hand) {
    return hand == ExerciseHand.left ? 'Left' : 'Right';
  }

  int _remainingRestForHand(ExerciseHand hand) {
    return max(0, handRemainingRest[hand] ?? 0);
  }

  int _maxLiftForHand(Exercise exercise, ExerciseHand hand) {
    return hand == ExerciseHand.left
        ? exercise.maxLiftLeftKg
        : exercise.maxLiftRightKg;
  }

  int _effectiveExerciseMaxLiftKg(Exercise exercise) {
    final ExerciseHand primaryHand = exercise.isSideSwitching
        ? (activeHand ?? exercise.startingHand)
        : exercise.startingHand;
    final ExerciseHand secondaryHand = _oppositeHand(primaryHand);

    final int primaryMaxLift = _maxLiftForHand(exercise, primaryHand);
    if (primaryMaxLift > 0) {
      return primaryMaxLift;
    }

    final int secondaryMaxLift = _maxLiftForHand(exercise, secondaryHand);
    if (secondaryMaxLift > 0) {
      return secondaryMaxLift;
    }

    return widget.userMaxLiftKg;
  }

  int _resolveTargetForceKg(Exercise? exercise) {
    if (exercise == null) {
      return widget.forceThresholdKg;
    }
    if (exercise.targetForceMode == TargetForceMode.relativePercent) {
      final int effectiveMaxLift = _effectiveExerciseMaxLiftKg(exercise);
      final double relativeKg =
          (effectiveMaxLift * exercise.targetForceValue) / 100;
      return relativeKg.round().clamp(minForceKg, maxForceKg);
    }
    return exercise.targetForceValue.round().clamp(minForceKg, maxForceKg);
  }

  int _targetMinForceKg(Exercise? exercise) {
    final int baseTarget = _resolveTargetForceKg(exercise);
    return max(minForceKg, baseTarget - widget.targetHysteresisKg);
  }

  int _targetMaxForceKg(Exercise? exercise) {
    final int baseTarget = _resolveTargetForceKg(exercise);
    final int baseMax = min(maxForceKg, baseTarget + 5);
    return min(maxForceKg, baseMax + widget.targetHysteresisKg);
  }

  String _targetLabel(Exercise? exercise) {
    if (exercise == null) {
      return '${widget.forceThresholdKg} kg';
    }
    if (exercise.targetForceMode == TargetForceMode.relativePercent) {
      final String percent = exercise.targetForceValue.toStringAsFixed(
        exercise.targetForceValue % 1 == 0 ? 0 : 1,
      );
      return '$percent% (~${_resolveTargetForceKg(exercise)}kg)';
    }
    return '${exercise.targetForceValue.toStringAsFixed(exercise.targetForceValue % 1 == 0 ? 0 : 1)}kg';
  }

  bool _isInsideTarget(int force) {
    final Exercise? exercise = currentExercise;
    final int minTarget = _targetMinForceKg(exercise);
    final int maxTarget = _targetMaxForceKg(exercise);
    return force >= minTarget && force <= maxTarget;
  }

  void _syncTargetFeedback(int force) {
    final bool nextInTargetRange = _isInsideTarget(force);
    if (nextInTargetRange == isInTargetRange) {
      return;
    }

    isInTargetRange = nextInTargetRange;
    if (!widget.enableTargetHaptics) {
      targetVibrationTimer?.cancel();
      targetVibrationTimer = null;
      return;
    }

    if (isInTargetRange) {
      HapticFeedback.selectionClick();
      targetVibrationTimer?.cancel();
      targetVibrationTimer = Timer.periodic(targetVibrationInterval, (_) {
        HapticFeedback.lightImpact();
      });
    } else {
      targetVibrationTimer?.cancel();
      targetVibrationTimer = null;
    }
  }

  WorkoutExerciseEntry? get currentEntry {
    if (currentEntryIndex >= widget.workout.entries.length) {
      return null;
    }
    return widget.workout.entries[currentEntryIndex];
  }

  Exercise? get currentExercise {
    final WorkoutExerciseEntry? entry = currentEntry;
    if (entry == null) {
      return null;
    }
    return widget.exercisesById[entry.exerciseId];
  }

  @override
  void initState() {
    super.initState();
    chartTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        final int sampledForce = currentForce.clamp(minForceKg, maxForceKg);
        dataPoints.add(FlSpot(timeIndex.toDouble(), sampledForce.toDouble()));
        timeIndex++;
        if (dataPoints.length > 220) {
          dataPoints.removeAt(0);
        }
        if (sampledForce > maxForce) {
          maxForce = sampledForce;
        }
      });
    });
    handRestTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }

      bool shouldAdvance = false;
      setState(() {
        for (final ExerciseHand hand in ExerciseHand.values) {
          final int remaining = handRemainingRest[hand] ?? 0;
          if (remaining > 0) {
            handRemainingRest[hand] = remaining - 1;
          }
        }

        if (phase == SessionPhase.resting && suggestedSwitchHand != null) {
          remainingRestSeconds = _remainingRestForHand(suggestedSwitchHand!);
          if (remainingRestSeconds <= 0) {
            shouldAdvance = true;
          }
        }
      });

      if (shouldAdvance) {
        _goToNextSetOrEntry();
      }
    });
    _prepareCurrentSet();
  }

  @override
  void dispose() {
    chartTimer?.cancel();
    handRestTimer?.cancel();
    phaseTimer?.cancel();
    targetVibrationTimer?.cancel();
    super.dispose();
  }

  void _prepareCurrentSet() {
    phaseTimer?.cancel();
    final WorkoutExerciseEntry? entry = currentEntry;
    final Exercise? exercise = currentExercise;

    if (entry == null) {
      setState(() {
        phase = SessionPhase.finished;
        suggestedSwitchHand = null;
        activeHand = null;
        pendingHandInSet = null;
      });
      return;
    }

    if (exercise == null) {
      setState(() {
        phase = SessionPhase.waitingForForce;
        suggestedSwitchHand = null;
        activeHand = null;
        pendingHandInSet = null;
        setStartArmed = widget.requireZeroBeforeSetStart
            ? currentForce == 0
            : true;
      });
      return;
    }

    if (exercise.isSideSwitching) {
      activeHand ??= exercise.startingHand;
    } else {
      activeHand = null;
      pendingHandInSet = null;
    }

    setState(() {
      remainingSetSeconds = exercise.durationSeconds ?? 0;
      phase = SessionPhase.waitingForForce;
      suggestedSwitchHand = null;
      setStartArmed = widget.requireZeroBeforeSetStart
          ? currentForce == 0
          : true;
      _syncTargetFeedback(currentForce);
    });
  }

  void _onForceChanged(int force) {
    final int nextForce = force.clamp(minForceKg, maxForceKg);

    setState(() {
      currentForce = nextForce;
      _syncTargetFeedback(currentForce);
    });

    if (phase == SessionPhase.waitingForForce) {
      if (widget.requireZeroBeforeSetStart && currentForce == 0) {
        setState(() {
          setStartArmed = true;
        });
        return;
      }

      _attemptStartWaitingSet();
    }
  }

  void _attemptStartWaitingSet() {
    if (phase != SessionPhase.waitingForForce || !setStartArmed) {
      return;
    }
    if (currentForce < widget.forceThresholdKg) {
      return;
    }

    final Exercise? exercise = currentExercise;
    if (exercise?.mode == ExerciseMode.duration) {
      setState(() {
        setStartArmed = false;
      });
      _startDurationSetTimer();
    } else {
      setState(() {
        phase = SessionPhase.activeSet;
        setStartArmed = false;
      });
    }
  }

  void _startDurationSetTimer() {
    if (remainingSetSeconds <= 0) {
      _completeCurrentSet();
      return;
    }

    setState(() {
      phase = SessionPhase.activeSet;
    });

    phaseTimer?.cancel();
    phaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (remainingSetSeconds <= 1) {
        _completeCurrentSet();
        return;
      }
      setState(() {
        remainingSetSeconds--;
      });
    });
  }

  void _completeCurrentSet() {
    phaseTimer?.cancel();

    final WorkoutExerciseEntry? entry = currentEntry;
    final Exercise? exercise = currentExercise;
    final ExerciseHand? completedHand = exercise?.isSideSwitching == true
        ? activeHand
        : null;

    if (entry == null || exercise == null) {
      _goToNextSetOrEntry();
      return;
    }

    final int restSeconds =
        entry.restOverrideSeconds ?? exercise.defaultRestSeconds;
    if (completedHand != null) {
      handRemainingRest[completedHand] = restSeconds;
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
      _goToNextSetOrEntry();
      return;
    }

    final int effectiveRestSeconds = switchTarget != null
        ? _remainingRestForHand(switchTarget)
        : restSeconds;

    if (effectiveRestSeconds <= 0) {
      _goToNextSetOrEntry();
      return;
    }

    setState(() {
      remainingRestSeconds = effectiveRestSeconds;
      phase = SessionPhase.resting;
      suggestedSwitchHand = switchTarget;
      setStartArmed = false;
    });

    phaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (suggestedSwitchHand != null) {
        // Auto-switch rests are controlled by per-hand timers.
        return;
      }
      if (remainingRestSeconds <= 1) {
        _goToNextSetOrEntry();
        return;
      }
      setState(() {
        remainingRestSeconds--;
      });
    });
  }

  void _goToNextSetOrEntry() {
    phaseTimer?.cancel();

    final WorkoutExerciseEntry? entry = currentEntry;
    final Exercise? exercise = currentExercise;

    if (exercise != null &&
        exercise.isSideSwitching &&
        pendingHandInSet != null) {
      setState(() {
        activeHand = pendingHandInSet;
        pendingHandInSet = null;
        suggestedSwitchHand = null;
        setStartArmed = false;
      });
      _prepareCurrentSet();
      return;
    }

    if (entry == null) {
      setState(() {
        phase = SessionPhase.finished;
        suggestedSwitchHand = null;
        activeHand = null;
        pendingHandInSet = null;
        setStartArmed = false;
      });
      return;
    }

    if (currentSet < entry.sets) {
      setState(() {
        currentSet++;
        suggestedSwitchHand = null;
        activeHand = exercise?.isSideSwitching == true
            ? exercise!.startingHand
            : null;
        pendingHandInSet = null;
        setStartArmed = false;
      });
      _prepareCurrentSet();
      return;
    }

    setState(() {
      currentEntryIndex++;
      currentSet = 1;
      suggestedSwitchHand = null;
      activeHand = null;
      pendingHandInSet = null;
      setStartArmed = false;
    });
    _prepareCurrentSet();
  }

  @override
  Widget build(BuildContext context) {
    final WorkoutExerciseEntry? entry = currentEntry;
    final Exercise? exercise = currentExercise;
    final ExerciseHand? activeHandForUi = activeHand;
    final int targetMinForce = _targetMinForceKg(exercise);
    final int targetMaxForce = _targetMaxForceKg(exercise);

    return Scaffold(
      appBar: AppBar(title: Text('Active: ${widget.workout.name}')),
      body: ForceInputDummy(
        sensitivity: dummySensitivity,
        minForce: minForceKg,
        maxForce: maxForceKg,
        onForceChanged: _onForceChanged,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Force: ${currentForce}kg (target ${_targetLabel(exercise)})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: isInTargetRange ? Colors.green : null,
                ),
              ),
              const SizedBox(height: 16),
              if (phase == SessionPhase.finished)
                const Expanded(child: Center(child: Text('Workout complete.')))
              else if (entry == null)
                const Expanded(
                  child: Center(child: Text('No entries in this workout.')),
                )
              else
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Entry ${currentEntryIndex + 1}/${widget.workout.entries.length}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              exercise?.name ?? 'Missing exercise reference',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text('Set $currentSet/${entry.sets}'),
                            if (activeHandForUi != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Active hand: ${_handLabel(activeHandForUi)}',
                              ),
                            ],
                            if (exercise != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                exercise.mode == ExerciseMode.duration
                                    ? 'Hold ${exercise.durationSeconds ?? 0}s'
                                    : '${exercise.reps ?? 0} reps',
                              ),
                            ],
                            const SizedBox(height: 12),
                            Expanded(
                              child: ForceChart(
                                dataPoints: dataPoints,
                                chartMaxForce: maxForceKg,
                                targetMinForce: targetMinForce,
                                targetMaxForce: targetMaxForce,
                                showTargetArea: phase != SessionPhase.resting,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (phase == SessionPhase.waitingForForce)
                              Text(
                                setStartArmed
                                    ? 'Apply at least ${widget.forceThresholdKg} kg to start the set.'
                                    : 'Release to 0 kg first, then apply at least ${widget.forceThresholdKg} kg to start.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            if (exercise != null)
                              Text(
                                'Target zone: $targetMinForce-$targetMaxForce kg (hys ${widget.targetHysteresisKg}kg)',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            if (phase == SessionPhase.activeSet &&
                                exercise?.mode == ExerciseMode.duration)
                              Text(
                                'Remaining hold: $remainingSetSeconds s',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            if (phase == SessionPhase.resting)
                              Text(
                                'Rest: $remainingRestSeconds s',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            if (phase == SessionPhase.resting &&
                                suggestedSwitchHand != null)
                              Text(
                                'Preparing ${_handLabel(suggestedSwitchHand!)} hand...',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (phase == SessionPhase.finished)
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Done'),
                      ),
                    )
                  else if (exercise == null)
                    Expanded(
                      child: FilledButton(
                        onPressed: _goToNextSetOrEntry,
                        child: const Text('Skip Missing Entry'),
                      ),
                    )
                  else if (phase == SessionPhase.resting)
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: suggestedSwitchHand == null
                            ? _goToNextSetOrEntry
                            : null,
                        child: Text(
                          suggestedSwitchHand == null
                              ? 'Skip Rest'
                              : 'Waiting for auto switch',
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: FilledButton(
                        onPressed: phase == SessionPhase.activeSet
                            ? _completeCurrentSet
                            : null,
                        child: Text(
                          exercise.mode == ExerciseMode.duration
                              ? 'Finish Set Early'
                              : 'Complete Set',
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
