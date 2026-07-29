import 'dart:async';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pullcrane/data/app_stores.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/models/workout.dart';
import 'package:pullcrane/domain/services/bluetooth_manager.dart';
import 'package:pullcrane/domain/services/workout_session_controller.dart';
import 'package:pullcrane/ui/bluetooth_connection_sheet.dart';
import 'package:pullcrane/ui/force_chart.dart';
import 'package:pullcrane/ui/force_input_dummy.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'animated_instruction_overlay.dart';

class ActiveWorkoutPage extends StatefulWidget {
  const ActiveWorkoutPage({
    super.key,
    required this.workout,
    required this.exercisesById,
    required this.forceThresholdKg,
    required this.targetHysteresisKg,
    required this.enableTargetHaptics,
    required this.requireZeroBeforeSetStart,
    required this.maxForceKg,
  });

  final Workout workout;
  final Map<String, Exercise> exercisesById;
  final int forceThresholdKg;
  final int targetHysteresisKg;
  final bool enableTargetHaptics;
  final bool requireZeroBeforeSetStart;
  final int maxForceKg;

  @override
  State<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends State<ActiveWorkoutPage> {
  static const double dummySensitivity = 0.3;
  static const Duration targetVibrationInterval = Duration(milliseconds: 280);

  late final WorkoutSessionController controller;
  late final ConfettiController _confettiController;

  final List<FlSpot> dataPoints = List<FlSpot>.empty(growable: true);
  int _timeIndex = 0;
  int _observedMaxForce = 0;

  Timer? _ticker;
  Timer? _chartTimer;
  Timer? _targetVibrationTimer;
  bool _isVibrating = false;

  late final DateTime _sessionStartedAt;
  bool _sessionSaved = false;

  @override
  void initState() {
    super.initState();
    controller = WorkoutSessionController(
      workout: widget.workout,
      exercisesById: widget.exercisesById,
      config: WorkoutSessionConfig(
        forceThresholdKg: widget.forceThresholdKg,
        targetHysteresisKg: widget.targetHysteresisKg,
        requireZeroBeforeSetStart: widget.requireZeroBeforeSetStart,
        maxForceKg: widget.maxForceKg,
      ),
    );
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    controller.onFinished = () {
      _confettiController.play();
      unawaited(_saveSession(completed: true));
    };
    controller.addListener(_syncTargetHaptics);

    _sessionStartedAt = DateTime.now();

    CraneScaleService.instance.addListener(_onServiceForceChanged);
    controller.start(DateTime.now());
    // Push the current force immediately so the page never shows stale data.
    _onServiceForceChanged();

    // All countdowns are wall-clock anchored inside the controller, so the
    // tick rate only affects UI smoothness, not correctness.
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      controller.tick(DateTime.now());
    });
    _chartTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        final int force = controller.currentForce;
        dataPoints.add(FlSpot(_timeIndex.toDouble(), force.toDouble()));
        _timeIndex++;
        if (dataPoints.length > 220) {
          dataPoints.removeAt(0);
        }
        if (force > _observedMaxForce) {
          _observedMaxForce = force;
        }
      });
    });

    unawaited(WakelockPlus.enable().catchError((_) {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _chartTimer?.cancel();
    _targetVibrationTimer?.cancel();
    CraneScaleService.instance.removeListener(_onServiceForceChanged);
    controller.removeListener(_syncTargetHaptics);
    controller.dispose();
    _confettiController.dispose();
    unawaited(WakelockPlus.disable().catchError((_) {}));
    super.dispose();
  }

  void _onServiceForceChanged() {
    if (!mounted) {
      return;
    }
    // Forward unconditionally: on disconnect the service resets its force to
    // 0, and the engine/page must see that instead of a stale value.
    controller.onForceChanged(
      CraneScaleService.instance.currentForce,
      DateTime.now(),
    );
  }

  bool get _inActiveTargetZone {
    final bool gatedPhase = controller.phase == SessionPhase.activeSet ||
        (controller.phase == SessionPhase.waitingForForce &&
            controller.setStartArmed);
    return controller.isInTargetZone && gatedPhase;
  }

  void _syncTargetHaptics() {
    if (!mounted) {
      return;
    }
    final bool shouldVibrate =
        widget.enableTargetHaptics && _inActiveTargetZone;
    if (shouldVibrate == _isVibrating) {
      return;
    }

    _isVibrating = shouldVibrate;
    if (_isVibrating) {
      HapticFeedback.selectionClick();
      _targetVibrationTimer?.cancel();
      _targetVibrationTimer = Timer.periodic(targetVibrationInterval, (_) {
        HapticFeedback.lightImpact();
      });
    } else {
      _targetVibrationTimer?.cancel();
      _targetVibrationTimer = null;
    }
  }

  String _handLabel(ExerciseHand hand) {
    return hand == ExerciseHand.left ? 'Left' : 'Right';
  }

  /// Persists the session if at least one set was logged. Runs at most once.
  Future<void> _saveSession({required bool completed}) async {
    if (_sessionSaved || controller.setLogs.isEmpty) {
      return;
    }
    _sessionSaved = true;
    try {
      await AppStores.sessions.saveSession(
        workoutId: widget.workout.id,
        workoutName: widget.workout.name,
        startedAt: _sessionStartedAt,
        finishedAt: DateTime.now(),
        completed: completed,
        logs: controller.setLogs,
      );
    } catch (e) {
      debugPrint('Failed to save workout session: $e');
    }
  }

  Future<void> _handlePopAttempt() async {
    if (controller.phase == SessionPhase.finished) {
      Navigator.of(context).pop();
      return;
    }

    final bool? abort = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Abort workout?'),
        content: const Text(
          'The workout is still in progress. Remaining sets will be skipped.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continue'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Abort'),
          ),
        ],
      ),
    );

    if (abort == true && mounted) {
      await _saveSession(completed: false);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _cancelFromDisconnectedOverlay() async {
    await _saveSession(completed: false);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          return;
        }
        _handlePopAttempt();
      },
      child: Scaffold(
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
                } else if (state == ScaleConnectionState.scanning ||
                    state == ScaleConnectionState.connecting) {
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
            final bool isConnected = CraneScaleService.instance.state ==
                ScaleConnectionState.connected;

            return Stack(
              children: [
                ForceInputDummy(
                  isEnabled: CraneScaleService.instance.isSimulated,
                  sensitivity: dummySensitivity,
                  minForce: 0,
                  maxForce: widget.maxForceKg,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => _buildSessionContent(context),
                    ),
                  ),
                ),
                if (!isConnected) _buildDisconnectedOverlay(context),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSessionContent(BuildContext context) {
    final WorkoutExerciseEntry? entry = controller.currentEntry;
    final Exercise? exercise = controller.currentExercise;
    final ExerciseHand? activeHandForUi = controller.activeHand;
    final SessionPhase phase = controller.phase;

    String actionLabel = 'Target';
    String actionValue = '';
    Color? actionColor;

    if (phase == SessionPhase.activeSet) {
      if (entry?.mode == ExerciseMode.duration) {
        actionLabel = 'Hold';
        actionValue = '${controller.remainingSetSeconds}s';
      } else {
        actionLabel = 'Target';
        actionValue = '${controller.completedReps}/${entry?.reps ?? 0} Reps';
      }
    } else if (phase == SessionPhase.resting) {
      actionLabel = 'Rest';
      actionValue = '${controller.remainingRestSeconds}s';
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

    final int chartMaxForce = max(
      20,
      max(_observedMaxForce, controller.targetMaxForceKg) + 5,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (phase == SessionPhase.finished)
          Expanded(
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Center(
                  child: Text(
                    widget.workout.entries.isEmpty
                        ? 'No entries in this workout.'
                        : 'Workout complete.',
                  ),
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
                    Colors.purple,
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
                      Text(
                        'Entry ${controller.currentEntryIndex + 1}/${widget.workout.entries.length}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        exercise?.name ?? 'Missing exercise reference',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('Set ${controller.currentSet}/${entry.sets}'),
                      if (activeHandForUi != null) ...[
                        const SizedBox(height: 4),
                        Visibility(
                          visible: phase != SessionPhase.resting,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: Text(
                            'Active hand: ${_handLabel(activeHandForUi)}',
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'LIVE FORCE',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(letterSpacing: 1.2),
                                ),
                                Text(
                                  '${controller.currentForce}kg',
                                  style: Theme.of(context)
                                      .textTheme
                                      .displayMedium
                                      ?.copyWith(
                                        color: _inActiveTargetZone
                                            ? Colors.green
                                            : null,
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
                                Text(
                                  actionLabel.toUpperCase(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(letterSpacing: 1.2),
                                ),
                                Text(
                                  actionValue,
                                  style: Theme.of(context)
                                      .textTheme
                                      .displayMedium
                                      ?.copyWith(
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
                              chartMaxForce: chartMaxForce,
                              targetMinForce: controller.targetMinForceKg,
                              targetMaxForce: controller.targetMaxForceKg,
                              showTargetArea: phase != SessionPhase.resting,
                            ),
                            AnimatedInstructionOverlay(
                              mainText: (phase ==
                                          SessionPhase.waitingForForce &&
                                      controller.setStartArmed)
                                  ? 'PULL'
                                  : 'RELEASE',
                              subText: (activeHandForUi != null &&
                                      phase == SessionPhase.waitingForForce &&
                                      controller.setStartArmed)
                                  ? '${_handLabel(activeHandForUi)} Hand'
                                  : null,
                              backgroundColor: (phase ==
                                          SessionPhase.waitingForForce &&
                                      controller.setStartArmed)
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer,
                              textColor: (phase ==
                                          SessionPhase.waitingForForce &&
                                      controller.setStartArmed)
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer,
                              isVisible: phase == SessionPhase.waitingForForce ||
                                  (phase != SessionPhase.activeSet &&
                                      controller.currentForce > 0),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (phase == SessionPhase.waitingForForce)
                        Text(
                          controller.setStartArmed
                              ? 'Apply at least ${widget.forceThresholdKg} kg to start the set.'
                              : 'Release to 0 kg first, then apply at least ${widget.forceThresholdKg} kg to start.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      if (phase == SessionPhase.resting &&
                          controller.suggestedSwitchHand != null)
                        Text(
                          'Preparing ${_handLabel(controller.suggestedSwitchHand!)} hand...',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      if (controller.isUsingFallbackMaxLift)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'No benchmark saved for this exercise — '
                            'assuming a ${controller.config.fallbackMaxLiftKg} kg max lift. '
                            'Measure it from the exercise page for accurate targets.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.tertiary,
                                ),
                          ),
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
                  onPressed: () => controller.skipEntry(DateTime.now()),
                  child: const Text('Skip Missing Exercise'),
                ),
              )
            else if (phase == SessionPhase.resting)
              Expanded(
                child: FilledButton.tonal(
                  onPressed: controller.suggestedSwitchHand == null
                      ? () => controller.skipRest(DateTime.now())
                      : null,
                  child: Text(
                    controller.suggestedSwitchHand == null
                        ? 'Skip Rest'
                        : 'Waiting for auto switch',
                  ),
                ),
              )
            else
              Expanded(
                child: FilledButton(
                  onPressed: phase == SessionPhase.activeSet
                      ? () => controller.completeCurrentSet(DateTime.now())
                      : null,
                  child: Text(
                    entry?.mode == ExerciseMode.duration
                        ? 'Finish Set Early'
                        : 'Complete Set',
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDisconnectedOverlay(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.bluetooth_disabled,
                size: 64,
                color: Colors.orange,
              ),
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
                onPressed: _cancelFromDisconnectedOverlay,
                child: const Text('Cancel Workout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
