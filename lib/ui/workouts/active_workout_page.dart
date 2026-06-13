import 'dart:async';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/models/workout.dart';
import 'package:pullcrane/ui/force_chart.dart';
import 'package:pullcrane/ui/force_input_dummy.dart';
import 'package:pullcrane/domain/services/bluetooth_manager.dart';
import 'package:pullcrane/ui/bluetooth_connection_sheet.dart';
import 'animated_instruction_overlay.dart';

enum SessionPhase { waitingForForce, activeSet, resting, finished }

class ActiveWorkoutPage extends StatefulWidget {
  const ActiveWorkoutPage({
    super.key,
    required this.workout,
    required this.exercisesById,
    required this.forceThresholdKg,
    required this.targetHysteresisKg,
    required this.enableTargetHaptics,
    required this.requireZeroBeforeSetStart,
  });

  final Workout workout;
  final Map<String, Exercise> exercisesById;
  final int forceThresholdKg;
  final int targetHysteresisKg;
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
  int completedReps = 0;
  bool repIsAboveThreshold = false;
  final Map<ExerciseHand, int> handRemainingRest = <ExerciseHand, int>{
    ExerciseHand.left: 0,
    ExerciseHand.right: 0,
  };
  late final ConfettiController _confettiController;

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

    if (completedHand == entry.startingHand) {
      pendingHandInSet = _oppositeHand(completedHand);
    } else {
      pendingHandInSet = null;
    }

    if (pendingHandInSet != null) {
      return pendingHandInSet;
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

  int _effectiveExerciseMaxLiftKg(Exercise exercise, WorkoutExerciseEntry entry) {
    final ExerciseHand primaryHand = exercise.isSideSwitching
        ? (activeHand ?? entry.startingHand)
        : entry.startingHand;
    final ExerciseHand secondaryHand = _oppositeHand(primaryHand);

    final int primaryMaxLift = _maxLiftForHand(exercise, primaryHand);
    if (primaryMaxLift > 0) {
      return primaryMaxLift;
    }

    final int secondaryMaxLift = _maxLiftForHand(exercise, secondaryHand);
    if (secondaryMaxLift > 0) {
      return secondaryMaxLift;
    }

    return 60; // default fallback if max lift is not set
  }

  int _resolveTargetForceKg(Exercise? exercise, WorkoutExerciseEntry? entry) {
    if (exercise == null || entry == null) {
      return widget.forceThresholdKg;
    }
    if (entry.targetForceMode == TargetForceMode.relativePercent) {
      final int effectiveMaxLift = _effectiveExerciseMaxLiftKg(exercise, entry);
      final double relativeKg =
          (effectiveMaxLift * entry.targetForceValue) / 100;
      return relativeKg.round().clamp(minForceKg, maxForceKg);
    }
    return entry.targetForceValue.round().clamp(minForceKg, maxForceKg);
  }

  int _targetMinForceKg(Exercise? exercise, WorkoutExerciseEntry? entry) {
    final int baseTarget = _resolveTargetForceKg(exercise, entry);
    return max(minForceKg, baseTarget - widget.targetHysteresisKg);
  }

  int _targetMaxForceKg(Exercise? exercise, WorkoutExerciseEntry? entry) {
    final int baseTarget = _resolveTargetForceKg(exercise, entry);
    return min(maxForceKg, baseTarget + widget.targetHysteresisKg);
  }

  String _targetLabel(Exercise? exercise, WorkoutExerciseEntry? entry) {
    if (exercise == null || entry == null) {
      return '${widget.forceThresholdKg} kg';
    }
    if (entry.targetForceMode == TargetForceMode.relativePercent) {
      final String percent = entry.targetForceValue
          .toStringAsFixed(entry.targetForceValue % 1 == 0 ? 0 : 1);
      return '$percent% (~${_resolveTargetForceKg(exercise, entry)}kg)';
    }
    return '${entry.targetForceValue.toStringAsFixed(entry.targetForceValue % 1 == 0 ? 0 : 1)}kg';
  }

  bool _isInsideTarget(int force) {
    final Exercise? exercise = currentExercise;
    final WorkoutExerciseEntry? entry = currentEntry;
    final int minTarget = _targetMinForceKg(exercise, entry);
    final int maxTarget = _targetMaxForceKg(exercise, entry);
    return force >= minTarget && force <= maxTarget;
  }

  void _syncTargetFeedback(int force) {
    final bool isForceInTarget = _isInsideTarget(force);
    final bool shouldVibrate = (phase == SessionPhase.activeSet || (phase == SessionPhase.waitingForForce && setStartArmed));
    final bool nextInTargetRange = isForceInTarget && shouldVibrate;

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

  int get _repReleaseThresholdKg =>
      max(widget.forceThresholdKg ~/ 2, 2);

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    CraneScaleService.instance.addListener(_onBleForceChanged);
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
      if (CraneScaleService.instance.state != ScaleConnectionState.connected) {
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
    CraneScaleService.instance.removeListener(_onBleForceChanged);
    _confettiController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _onBleForceChanged() {
    if (!mounted) return;
    if (CraneScaleService.instance.state == ScaleConnectionState.connected) {
      _onForceChanged(CraneScaleService.instance.currentForce);
    }
  }

  void _prepareCurrentSet() {
    phaseTimer?.cancel();
    final WorkoutExerciseEntry? entry = currentEntry;
    final Exercise? exercise = currentExercise;

    if (entry == null) {
      setState(() {
        phase = SessionPhase.finished;
        _confettiController.play();
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
        setStartArmed =
            widget.requireZeroBeforeSetStart ? currentForce == 0 : true;
      });
      return;
    }

    if (exercise.isSideSwitching) {
      activeHand ??= entry.startingHand;
    } else {
      activeHand = null;
      pendingHandInSet = null;
    }

    setState(() {
      remainingSetSeconds = entry.durationSeconds ?? 0;
      phase = SessionPhase.waitingForForce;
      suggestedSwitchHand = null;
      setStartArmed =
          widget.requireZeroBeforeSetStart ? currentForce == 0 : true;
      completedReps = 0;
      repIsAboveThreshold = false;
      _syncTargetFeedback(currentForce);
    });
  }

  void _onForceChanged(int force) {
    final int nextForce = force.clamp(minForceKg, maxForceKg);
    final WorkoutExerciseEntry? entry = currentEntry;

    setState(() {
      currentForce = nextForce;
      _syncTargetFeedback(currentForce);

      if (phase == SessionPhase.activeSet && entry?.mode == ExerciseMode.reps) {
        if (!repIsAboveThreshold && currentForce >= widget.forceThresholdKg) {
          repIsAboveThreshold = true;
        } else if (repIsAboveThreshold && currentForce < _repReleaseThresholdKg) {
          repIsAboveThreshold = false;
          completedReps++;
        }
      }
    });

    if (phase == SessionPhase.activeSet &&
        entry?.mode == ExerciseMode.reps &&
        completedReps >= (entry?.reps ?? 0) &&
        (entry?.reps ?? 0) > 0) {
      _completeCurrentSet();
      return;
    }

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

    final WorkoutExerciseEntry? entry = currentEntry;
    if (entry?.mode == ExerciseMode.duration) {
      setState(() {
        setStartArmed = false;
      });
      _startDurationSetTimer();
    } else {
      setState(() {
        phase = SessionPhase.activeSet;
        setStartArmed = false;
        repIsAboveThreshold = true;
      });
      _syncTargetFeedback(currentForce);
      _syncTargetFeedback(currentForce);
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
    _syncTargetFeedback(currentForce);
    _syncTargetFeedback(currentForce);

    phaseTimer?.cancel();
    phaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (CraneScaleService.instance.state != ScaleConnectionState.connected) {
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
    final ExerciseHand? completedHand =
        exercise?.isSideSwitching == true ? activeHand : null;

    if (entry == null || exercise == null) {
      _goToNextSetOrEntry();
      return;
    }

    final int restSeconds = entry.restSeconds;
    if (completedHand != null) {
      handRemainingRest[completedHand] = restSeconds;
    }

    final ExerciseHand? switchTarget = _resolveSwitchTarget(
      exercise: exercise,
      entry: entry,
      completedHand: completedHand,
    );

    if (!_hasMoreWorkAfterCurrentCompletion(entry: entry, switchTarget: switchTarget)) {
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
    _syncTargetFeedback(currentForce);
    _syncTargetFeedback(currentForce);

    phaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (CraneScaleService.instance.state != ScaleConnectionState.connected) {
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

    if (exercise != null && exercise.isSideSwitching && pendingHandInSet != null) {
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
        _confettiController.play();
        suggestedSwitchHand = null;
        activeHand = null;
        pendingHandInSet = null;
        setStartArmed = false;
      });
      _syncTargetFeedback(currentForce);
      _syncTargetFeedback(currentForce);
      return;
    }

    if (currentSet < entry.sets) {
      setState(() {
        currentSet++;
        suggestedSwitchHand = null;
        activeHand = exercise?.isSideSwitching == true
            ? entry.startingHand
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
    _syncTargetFeedback(currentForce);
    _syncTargetFeedback(currentForce);
  }

  @override
  Widget build(BuildContext context) {
    final WorkoutExerciseEntry? entry = currentEntry;
    final Exercise? exercise = currentExercise;
    final ExerciseHand? activeHandForUi = activeHand;

    final int targetMinForce = _targetMinForceKg(exercise, entry);
    final int targetMaxForce = _targetMaxForceKg(exercise, entry);

    String actionLabel = 'Target';
    String actionValue = '';
    Color? actionColor;

    if (phase == SessionPhase.activeSet) {
      if (entry?.mode == ExerciseMode.duration) {
        actionLabel = 'Hold';
        actionValue = '${remainingSetSeconds}s';
      } else {
        actionLabel = 'Target';
        actionValue = '$completedReps/${entry?.reps ?? 0} Reps';
      }
    } else if (phase == SessionPhase.resting) {
      actionLabel = 'Rest';
      actionValue = '${remainingRestSeconds}s';
      actionColor = Colors.orange;
    } else if (phase == SessionPhase.waitingForForce) {
      actionLabel = 'Target';
      actionValue = entry?.mode == ExerciseMode.duration
          ? '${entry?.durationSeconds ?? 0}s'
          : '${entry?.reps ?? 0} Reps';
    } else {
      actionLabel = 'Status';
      actionValue = 'Done';
    }


    return Scaffold(
      appBar: AppBar(
        title: Text('Active: ${widget.workout.name}'),
        actions: [
          ListenableBuilder(
            listenable: CraneScaleService.instance,
            builder: (context, _) {
              final state = CraneScaleService.instance.state;
              IconData icon = Icons.bluetooth_disabled;
              Color? color = Theme.of(context).disabledColor;

              if (state == ScaleConnectionState.connected) {
                icon = Icons.bluetooth_connected;
                color = Colors.green;
              } else if (state == ScaleConnectionState.scanning || state == ScaleConnectionState.connecting) {
                icon = Icons.bluetooth_searching;
                color = Colors.orange;
              }

              return IconButton(
                icon: Icon(icon, color: color),
                onPressed: () => BluetoothConnectionSheet.show(context),
                tooltip: 'Bluetooth connection',
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: CraneScaleService.instance,
        builder: (context, _) {
          final bool isConnected = CraneScaleService.instance.state == ScaleConnectionState.connected;
          
          return Stack(
            children: [
              ForceInputDummy(
                isEnabled: CraneScaleService.instance.isSimulated,
                sensitivity: dummySensitivity,
                minForce: minForceKg,
                maxForce: maxForceKg,
                onForceChanged: _onForceChanged,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      if (phase == SessionPhase.finished)
                        Expanded(
                          child: Stack(
                            alignment: Alignment.topCenter,
                            children: [
                              const Center(
                                child: Text('Workout complete.'),
                              ),
                              ConfettiWidget(
                                confettiController: _confettiController,
                                blastDirectionality: BlastDirectionality.explosive,
                                particleDrag: 0.05,
                                emissionFrequency: 0.05,
                                numberOfParticles: 50,
                                gravity: 0.2,
                                shouldLoop: false,
                                colors: const [
                                  Colors.green,
                                  Colors.blue,
                                  Colors.pink,
                                  Colors.orange,
                                  Colors.purple
                                ],
                              ),
                            ],
                          ),
                        )
                      else if (entry == null)
                const Expanded(
                  child: Center(
                    child: Text('No entries in this workout.'),
                  ),
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
                          Text('Entry ${currentEntryIndex + 1}/${widget.workout.entries.length}'),
                          const SizedBox(height: 8),
                          Text(
                            exercise?.name ?? 'Missing exercise reference',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text('Set $currentSet/${entry.sets}'),
                          if (activeHandForUi != null) ...[
                            const SizedBox(height: 4),
                            Visibility(
                              visible: phase != SessionPhase.resting,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: Text('Active hand: ${_handLabel(activeHandForUi)}'),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('LIVE FORCE', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
                                    Text(
                                      '${currentForce}kg',
                                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                                        color: isInTargetRange ? Colors.green : null,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(actionLabel.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
                                    Text(
                                      actionValue,
                                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                                        color: actionColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Stack(
                              children: [
                                ForceChart(
                                  dataPoints: dataPoints,
                                  chartMaxForce: maxForceKg,
                                  targetMinForce: targetMinForce,
                                  targetMaxForce: targetMaxForce,
                                  showTargetArea: phase != SessionPhase.resting,
                                ),
                                AnimatedInstructionOverlay(
                                  mainText: (phase == SessionPhase.waitingForForce && setStartArmed)
                                      ? 'PULL'
                                      : 'RELEASE',
                                  subText: (activeHandForUi != null && phase == SessionPhase.waitingForForce && setStartArmed)
                                      ? '${_handLabel(activeHandForUi)} Hand'
                                      : null,
                                  backgroundColor: (phase == SessionPhase.waitingForForce && setStartArmed)
                                      ? Theme.of(context).colorScheme.primaryContainer
                                      : Theme.of(context).colorScheme.secondaryContainer,
                                  textColor: (phase == SessionPhase.waitingForForce && setStartArmed)
                                      ? Theme.of(context).colorScheme.onPrimaryContainer
                                      : Theme.of(context).colorScheme.onSecondaryContainer,
                                  isVisible: (phase == SessionPhase.waitingForForce && !setStartArmed) ||
                                      (phase == SessionPhase.waitingForForce && setStartArmed) ||
                                      (phase != SessionPhase.activeSet && currentForce > 0),
                                ),
                              ],
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
                          if (phase == SessionPhase.resting && suggestedSwitchHand != null)
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
                  else if (entry == null)
                    Expanded(
                      child: FilledButton(
                        onPressed: _goToNextSetOrEntry,
                        child: const Text('Skip Missing Entry'),
                      ),
                    )
                  else if (phase == SessionPhase.resting)
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: suggestedSwitchHand == null ? _goToNextSetOrEntry : null,
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
                          entry.mode == ExerciseMode.duration
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
      if (!isConnected)
        Container(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.orange),
                  const SizedBox(height: 16),
                  Text(
                    'Device Connection Required',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please connect a device or select the simulated device to continue the workout.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => BluetoothConnectionSheet.show(context),
                    child: const Text('Connect Device'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel Workout'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  },
),
    );
  }
}

