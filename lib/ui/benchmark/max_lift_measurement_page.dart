import 'package:flutter/material.dart';
import 'package:pullcrane/data/app_stores.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/ui/force_input_dummy.dart';
import 'package:pullcrane/domain/services/bluetooth_manager.dart';
import 'package:pullcrane/ui/bluetooth_connection_sheet.dart';

class MaxLiftMeasurementPage extends StatefulWidget {
  const MaxLiftMeasurementPage({super.key, required this.exercise});

  final Exercise exercise;

  @override
  State<MaxLiftMeasurementPage> createState() => _MaxLiftMeasurementPageState();
}

class _MaxLiftMeasurementPageState extends State<MaxLiftMeasurementPage> {
  static const int minForceKg = 0;
  static const int maxForceKg = 100;
  static const double dummySensitivity = 0.3;

  late Exercise currentExercise;
  late ExerciseHand selectedHand;
  int currentLeftForceKg = 0;
  int currentRightForceKg = 0;
  int maxLeftForceKg = 0;
  int maxRightForceKg = 0;

  int forceThresholdKg = 10;
  bool isSettingsLoaded = false;

  bool get isTwoHandMeasurement => currentExercise.isSideSwitching;

  bool get canSave {
    if (!isSettingsLoaded) return false;
    if (isTwoHandMeasurement) {
      return maxLeftForceKg >= forceThresholdKg &&
          maxRightForceKg >= forceThresholdKg;
    } else {
      return selectedHand == ExerciseHand.left
          ? maxLeftForceKg >= forceThresholdKg
          : maxRightForceKg >= forceThresholdKg;
    }
  }

  @override
  void initState() {
    super.initState();
    currentExercise = widget.exercise;
    selectedHand = ExerciseHand.left;
    maxLeftForceKg = 0;
    maxRightForceKg = 0;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await AppStores.settings.load();
    if (mounted) {
      setState(() {
        forceThresholdKg = settings.forceThresholdKg;
        isSettingsLoaded = true;
      });
    }
    CraneScaleService.instance.addListener(_onBleForceChanged);
    selectedHand = ExerciseHand.left;
  }

  @override
  void dispose() {
    CraneScaleService.instance.removeListener(_onBleForceChanged);
    super.dispose();
  }

  void _onBleForceChanged() {
    if (!mounted) return;
    if (CraneScaleService.instance.state == ScaleConnectionState.connected) {
      _onForceChanged(CraneScaleService.instance.currentForce);
    }
  }

  String _handLabel(ExerciseHand hand) {
    return hand == ExerciseHand.left ? 'Left' : 'Right';
  }

  void _onForceChanged(int forceKg) {
    if (CraneScaleService.instance.state == ScaleConnectionState.connected && forceKg != CraneScaleService.instance.currentForce) {
      return;
    }

    final int clamped = forceKg.clamp(minForceKg, maxForceKg);
    setState(() {
      if (selectedHand == ExerciseHand.left) {
        currentLeftForceKg = clamped;
        if (clamped > maxLeftForceKg) {
          maxLeftForceKg = clamped;
        }
        currentRightForceKg = 0;
      } else {
        currentRightForceKg = clamped;
        if (clamped > maxRightForceKg) {
          maxRightForceKg = clamped;
        }
        currentLeftForceKg = 0;
      }
    });
  }

  void _setSelectedHand(ExerciseHand hand) {
    if (selectedHand == hand) {
      return;
    }
    setState(() {
      selectedHand = hand;
      currentLeftForceKg = 0;
      currentRightForceKg = 0;
    });
  }

  Future<void> _saveMaxLift() async {
    final newRecord = MaxLiftRecord(
      date: DateTime.now(),
      leftKg: maxLeftForceKg,
      rightKg: maxRightForceKg,
    );

    final List<MaxLiftRecord> newHistory = List.from(
      currentExercise.maxLiftHistory,
    )..add(newRecord);

    int newAbsoluteMaxLeft = 0;
    int newAbsoluteMaxRight = 0;
    for (var record in newHistory) {
      if (record.leftKg > newAbsoluteMaxLeft) {
        newAbsoluteMaxLeft = record.leftKg;
      }
      if (record.rightKg > newAbsoluteMaxRight) {
        newAbsoluteMaxRight = record.rightKg;
      }
    }

    final Exercise updatedExercise = currentExercise.copyWith(
      maxLiftLeftKg: newAbsoluteMaxLeft,
      maxLiftRightKg: newAbsoluteMaxRight,
      maxLiftHistory: newHistory,
    );

    await AppStores.exercises.saveExercise(updatedExercise);

    if (!mounted) return;
    
    Navigator.of(context).pop(updatedExercise);
  }


  Widget _buildForceBar({
    required BuildContext context,
    required String label,
    required int currentForceKg,
    required int maxForceRecordedKg,
    required bool isActive,
  }) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isActive ? colors.primary : colors.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double barHeight = constraints.maxHeight;
                  final double currentRatio = (currentForceKg / maxForceKg)
                      .clamp(0, 1)
                      .toDouble();
                  final double maxRatio = (maxForceRecordedKg / maxForceKg)
                      .clamp(0, 1)
                      .toDouble();
                  final double currentHeight = barHeight * currentRatio;
                  final double maxLineBottom = ((barHeight * maxRatio) - 1)
                      .clamp(0, barHeight - 2)
                      .toDouble();

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withValues(
                              alpha: 0.35,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 90),
                          height: currentHeight,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: maxLineBottom,
                        child: Container(height: 2, color: colors.tertiary),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text('Current ${currentForceKg}kg • Max ${maxForceRecordedKg}kg'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Max Lift: ${widget.exercise.name}'),
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isTwoHandMeasurement) ...[
                Text(
                  'Tap a bar to select, then drag anywhere to measure ${_handLabel(selectedHand)} hand force.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _setSelectedHand(ExerciseHand.left),
                        child: _buildForceBar(
                          context: context,
                          label: 'Left hand',
                          currentForceKg: currentLeftForceKg,
                          maxForceRecordedKg: maxLeftForceKg,
                          isActive: selectedHand == ExerciseHand.left,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _setSelectedHand(ExerciseHand.right),
                        child: _buildForceBar(
                          context: context,
                          label: 'Right hand',
                          currentForceKg: currentRightForceKg,
                          maxForceRecordedKg: maxRightForceKg,
                          isActive: selectedHand == ExerciseHand.right,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const Text('Drag anywhere to measure force.'),
                const SizedBox(height: 12),
                _buildForceBar(
                  context: context,
                  label: 'Force',
                  currentForceKg: selectedHand == ExerciseHand.left
                      ? currentLeftForceKg
                      : currentRightForceKg,
                  maxForceRecordedKg: selectedHand == ExerciseHand.left
                      ? maxLeftForceKg
                      : maxRightForceKg,
                  isActive: true,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: canSave ? _saveMaxLift : null,
                      child: const Text('Save & Close'),
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
                    'Please connect a device or select the simulated device to continue measurement.',
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
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel'),
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
